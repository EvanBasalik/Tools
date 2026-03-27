[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanvasBaseUrl,

    [Parameter(Mandatory = $true)]
    [int]$SourceCourseId,

    [Parameter(Mandatory = $true)]
    [int]$DestinationCourseId,

    [Parameter(Mandatory = $true)]
    [datetime]$SourceCourseStartDate,

    [Parameter(Mandatory = $true)]
    [datetime]$DestinationCourseStartDate,

    [Parameter()]
    [string]$CanvasApiToken = $env:CANVAS_API_TOKEN,

    [Parameter()]
    [switch]$SkipCourseCopy,

    [Parameter()]
    [int]$PollSeconds = 10,

    [Parameter()]
    [int]$MigrationTimeoutMinutes = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($CanvasApiToken)) {
    throw "Canvas API token not found. Pass -CanvasApiToken or set CANVAS_API_TOKEN."
}

$baseUrl = $CanvasBaseUrl.TrimEnd('/')
$headers = @{
    Authorization = "Bearer $CanvasApiToken"
}

function Get-NextLink {
    param(
        [Parameter()]
        [string]$LinkHeader
    )

    if ([string]::IsNullOrWhiteSpace($LinkHeader)) {
        return $null
    }

    $match = [regex]::Match($LinkHeader, '<([^>]+)>;\s*rel="next"')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return $null
}

function Invoke-CanvasApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "PUT")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Body
    )

    $responseHeaders = $null
    $invokeParams = @{
        Method                  = $Method
        Uri                     = $Uri
        Headers                 = $headers
        ResponseHeadersVariable = 'responseHeaders'
        ErrorAction             = 'Stop'
    }

    if ($Body) {
        $invokeParams.Body = $Body
    }

    $data = Invoke-RestMethod @invokeParams

    [pscustomobject]@{
        Data    = $data
        Headers = $responseHeaders
    }
}

function Get-CanvasPagedResults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InitialUri
    )

    $results = @()
    $currentUri = $InitialUri

    while ($null -ne $currentUri) {
        $response = Invoke-CanvasApi -Method GET -Uri $currentUri

        if ($null -ne $response.Data) {
            if ($response.Data -is [System.Array]) {
                $results += $response.Data
            }
            else {
                $results += ,$response.Data
            }
        }

        $linkHeader = $response.Headers.Link
        $currentUri = Get-NextLink -LinkHeader $linkHeader
    }

    return $results
}

function Shift-CanvasDateString {
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DateString,

        [Parameter(Mandatory = $true)]
        [timespan]$Offset
    )

    if ([string]::IsNullOrWhiteSpace($DateString)) {
        return $null
    }

    $parsed = [datetimeoffset]::Parse($DateString)
    $shifted = $parsed.Add($Offset)
    return $shifted.ToUniversalTime().ToString("o")
}

function Start-CourseCopy {
    param(
        [Parameter(Mandatory = $true)]
        [int]$FromCourseId,

        [Parameter(Mandatory = $true)]
        [int]$ToCourseId
    )

    $uri = "$baseUrl/api/v1/courses/$ToCourseId/content_migrations"
    $body = @{
        migration_type               = "course_copy_importer"
        "settings[source_course_id]" = "$FromCourseId"
    }

    $response = Invoke-CanvasApi -Method POST -Uri $uri -Body $body
    return $response.Data
}

function Wait-ForCourseCopy {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ToCourseId,

        [Parameter(Mandatory = $true)]
        [int]$MigrationId,

        [Parameter(Mandatory = $true)]
        [int]$PollEverySeconds,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMinutes
    )

    $uri = "$baseUrl/api/v1/courses/$ToCourseId/content_migrations/$MigrationId"
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    while ((Get-Date) -lt $deadline) {
        $response = Invoke-CanvasApi -Method GET -Uri $uri
        $state = $response.Data.workflow_state
        $progress = $response.Data.progress

        Write-Host "Course copy status: $state ($progress%)"

        if ($state -eq "completed") {
            return
        }

        if ($state -eq "failed") {
            throw "Canvas course copy failed. Check course migration details in Canvas UI."
        }

        Start-Sleep -Seconds $PollEverySeconds
    }

    throw "Timed out waiting for course copy to complete after $TimeoutMinutes minutes."
}

function Update-AssignmentDates {
    param(
        [Parameter(Mandatory = $true)]
        [int]$CourseId,

        [Parameter(Mandatory = $true)]
        [timespan]$Offset
    )

    $uri = "$baseUrl/api/v1/courses/$CourseId/assignments?per_page=100"
    $assignments = Get-CanvasPagedResults -InitialUri $uri

    foreach ($assignment in $assignments) {
        $updatedDueAt = Shift-CanvasDateString -DateString $assignment.due_at -Offset $Offset
        $updatedUnlockAt = Shift-CanvasDateString -DateString $assignment.unlock_at -Offset $Offset
        $updatedLockAt = Shift-CanvasDateString -DateString $assignment.lock_at -Offset $Offset

        $body = @{}
        if ($null -ne $updatedDueAt) {
            $body['assignment[due_at]'] = $updatedDueAt
        }
        if ($null -ne $updatedUnlockAt) {
            $body['assignment[unlock_at]'] = $updatedUnlockAt
        }
        if ($null -ne $updatedLockAt) {
            $body['assignment[lock_at]'] = $updatedLockAt
        }

        if ($body.Count -eq 0) {
            continue
        }

        $updateUri = "$baseUrl/api/v1/courses/$CourseId/assignments/$($assignment.id)"
        Invoke-CanvasApi -Method PUT -Uri $updateUri -Body $body | Out-Null
        Write-Host "Updated assignment dates: $($assignment.name)"
    }
}

function Update-ModuleUnlockDates {
    param(
        [Parameter(Mandatory = $true)]
        [int]$CourseId,

        [Parameter(Mandatory = $true)]
        [timespan]$Offset
    )

    $uri = "$baseUrl/api/v1/courses/$CourseId/modules?per_page=100"
    $modules = Get-CanvasPagedResults -InitialUri $uri

    foreach ($module in $modules) {
        $updatedUnlockAt = Shift-CanvasDateString -DateString $module.unlock_at -Offset $Offset

        if ($null -eq $updatedUnlockAt) {
            continue
        }

        $updateUri = "$baseUrl/api/v1/courses/$CourseId/modules/$($module.id)"
        $body = @{
            'module[unlock_at]' = $updatedUnlockAt
        }

        Invoke-CanvasApi -Method PUT -Uri $updateUri -Body $body | Out-Null
        Write-Host "Updated module unlock date: $($module.name)"
    }
}

$offset = $DestinationCourseStartDate - $SourceCourseStartDate
Write-Host "Calculated schedule offset: $([int]$offset.TotalDays) days"

if (-not $SkipCourseCopy) {
    Write-Host "Starting copy from course $SourceCourseId to $DestinationCourseId..."
    $migration = Start-CourseCopy -FromCourseId $SourceCourseId -ToCourseId $DestinationCourseId

    if ($null -eq $migration.id) {
        throw "Canvas did not return a migration id."
    }

    Wait-ForCourseCopy -ToCourseId $DestinationCourseId -MigrationId $migration.id -PollEverySeconds $PollSeconds -TimeoutMinutes $MigrationTimeoutMinutes
}
else {
    Write-Host "Skipping course copy because -SkipCourseCopy was provided."
}

Write-Host "Shifting assignment dates..."
Update-AssignmentDates -CourseId $DestinationCourseId -Offset $offset

Write-Host "Shifting module unlock dates..."
Update-ModuleUnlockDates -CourseId $DestinationCourseId -Offset $offset

Write-Host "Canvas copy + schedule shift complete."
