
[CmdletBinding()]
param(
  
    #[Parameter(Mandatory = $true)]
    #[string] $DevCenter,

    #[Parameter(Mandatory = $true)]
    #[string] $Project,

    [Parameter(Mandatory = $true)]
    [string] $DevBoxName,

    [Parameter(Mandatory = $true, ParameterSetName = 'SetHours')]
    [string] $StartTimeHour,

    [Parameter(Mandatory = $true, ParameterSetName = 'SetHours')]
    [string] $EndTimeHour,

    [Parameter(Mandatory = $true, ParameterSetName = 'GetConfig')]
    [switch] $GetCurrentConfig,

    [Parameter(ParameterSetName = 'GetConfig')]
    [switch] $Full
)

$armToken = (Get-AzAccessToken -AsSecureString).Token
$secureToken = (Get-AzAccessToken -ResourceUrl "https://devcenter.azure.com" -AsSecureString).Token

$devCenterApiVersions = @(
    "2025-03-01-preview",
    "2024-10-01-preview",
    "2024-08-01-preview",
    "2024-05-01-preview",
    "2024-02-01",
    "2023-10-01-preview",
    "2023-07-01-preview",
    "2023-04-01"
)

function Invoke-DevCenterRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $UriBase,

        [Parameter(Mandatory = $true)]
        [string] $Method,

        [Parameter(Mandatory = $true)]
        [securestring] $Token,

        [Parameter(Mandatory = $true)]
        [string[]] $ApiVersions,

        [string] $ContentType,
        [string] $Body
    )

    $candidateCalls = @()
    if ($UriBase -match '(?i)[?&]api-version=') {
        $candidateCalls += [pscustomobject]@{
            Uri        = $UriBase
            ApiVersion = "<from-uri>"
        }
    }
    else {
        foreach ($version in $ApiVersions) {
            $separator = "?"
            if ($UriBase.Contains("?")) {
                $separator = "&"
            }

            $candidateCalls += [pscustomobject]@{
                Uri        = "${UriBase}${separator}api-version=${version}"
                ApiVersion = $version
            }
        }
    }

    $lastError = $null
    foreach ($call in $candidateCalls) {
        try {
            if ($Method -ieq 'GET') {
                $response = Invoke-WebRequest -Authentication Bearer -Token $Token -Method $Method -Uri $call.Uri
            }
            elseif ($null -ne $Body -and $Body -ne "") {
                $response = Invoke-WebRequest -Authentication Bearer -Token $Token -Method $Method -Uri $call.Uri -ContentType $ContentType -Body $Body
            }
            else {
                $response = Invoke-WebRequest -Authentication Bearer -Token $Token -Method $Method -Uri $call.Uri -ContentType $ContentType
            }

            return [pscustomobject]@{
                Response   = $response
                ApiVersion = $call.ApiVersion
                Uri        = $call.Uri
            }
        }
        catch {
            $lastError = $_
            $errorCode = $null
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try {
                    $parsedError = $_.ErrorDetails.Message | ConvertFrom-Json
                    $errorCode = $parsedError.error.code
                }
                catch {
                }
            }

            if ($errorCode -eq 'UnsupportedApiVersion') {
                continue
            }
        }
    }

    if ($null -ne $lastError) {
        throw $lastError
    }

    throw "No supported API version found for URI: $UriBase"
}

$body = @{
    "query" = "resources | where ['type'] =~ 'microsoft.devcenter/projects' | extend devCenterUri = tostring(properties['devCenterUri']) | project devCenterUri | distinct devCenterUri"
}
$bodyStr = ConvertTo-Json $body
$argUri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01"

$response = Invoke-WebRequest -Authentication Bearer -Token $armToken -Method 'POST' -Uri $argUri -ContentType "application/json" -Body $bodyStr
$obj = $response.Content | ConvertFrom-Json

$devBox = $null
$allDevBoxes = @()
$namePattern = [regex]::Escape($DevBoxName)
foreach ($item in $obj.data) {
    if ($null -eq $item.devCenterUri -or $item.devCenterUri -eq "") {
        Write-Host "Skipping item with null devCenterUri"
        continue
    }

    $devCenterUri = $item.devCenterUri
    $nextDevBoxesUri = "${devCenterUri}users/me/devboxes"
    while ($null -ne $nextDevBoxesUri -and $nextDevBoxesUri -ne "") {
        $listDevBoxResponse = $null
        try {
            $listCall = Invoke-DevCenterRequest -UriBase $nextDevBoxesUri -Method 'GET' -Token $secureToken -ApiVersions $devCenterApiVersions
            $listDevBoxResponse = $listCall.Response
        }
        catch {
            Write-Information "Error connecting to ${devCenterUri}: $($_.Exception.Message)"
            break
        }

        $listDevBoxResult = $listDevBoxResponse.Content | ConvertFrom-Json
        if ($null -ne $listDevBoxResult.value) {
            $allDevBoxes += @($listDevBoxResult.value)
            $db = $listDevBoxResult.value | Where-Object {
                $_.name -ieq $DevBoxName -or
                $_.displayName -ieq $DevBoxName -or
                ($_.id -split '/')[-1] -ieq $DevBoxName
            } | Select-Object -First 1

            if ($null -ne $db) {
                $devBox = $db
                break
            }
        }

        $nextDevBoxesUri = $listDevBoxResult.nextLink
    }

    if ($null -ne $devBox) {
        break
    }
}

if ($null -eq $devBox) {
    $partialMatches = $allDevBoxes | Where-Object {
        $_.name -match $namePattern -or $_.displayName -match $namePattern
    } | Select-Object -First 1

    if ($null -ne $partialMatches) {
        Write-Warning "No exact DevBox match found. Using partial match '$($partialMatches.name)'."
        $devBox = $partialMatches
    }
}

if ($null -eq $devBox) {
    $availableDevBoxes = $allDevBoxes |
        Sort-Object name -Unique |
        ForEach-Object {
            if ($_.displayName -and $_.displayName -ne $_.name) {
                "$($_.name) (displayName: $($_.displayName))"
            }
            else {
                "$($_.name)"
            }
        }

    if ($availableDevBoxes.Count -gt 0) {
        Write-Error "DevBox '$DevBoxName' not found. Available DevBoxes: $($availableDevBoxes -join ', ')"
    }
    else {
        Write-Error "DevBox '$DevBoxName' not found and no DevBoxes were returned for user/me."
    }
    exit
}

if ($GetCurrentConfig) {
    $devBoxUri = $devBox.uri
    $configSource = $devBox
    $activeHoursData = $null

    # Try users/me path first (avoids GUID-based URI which may not support action endpoints)
    $devCenterBase = ($devBoxUri -replace '/users/[^/]+/devboxes/.*', '')
    $devBoxNameFromUri = ($devBoxUri -split '/')[-1]
    $projectNameFromUri = ($devBoxUri -split '/projects/')[1] -split '/' | Select-Object -First 1
    $meBasedUri = "${devCenterBase}/projects/${projectNameFromUri}/users/me/devboxes/${devBoxNameFromUri}"

    $getActiveHoursUriBases = @(
        "${meBasedUri}:getactivehours",
        "${devBoxUri}:getactivehours",
        "${meBasedUri}/activeHours",
        "${devBoxUri}/activeHours"
    )

    foreach ($getActiveHoursUriBase in $getActiveHoursUriBases) {
        try {
            $getCall = Invoke-DevCenterRequest -UriBase $getActiveHoursUriBase -Method 'GET' -Token $secureToken -ApiVersions $devCenterApiVersions
            $parsed = $getCall.Response.Content | ConvertFrom-Json
            # If this looks like an active-hours object (has StartTimeHour or startTimeHour), use it separately
            if ($null -ne $parsed.StartTimeHour -or $null -ne $parsed.startTimeHour -or
                $null -ne $parsed.EndTimeHour -or $null -ne $parsed.endTimeHour) {
                $activeHoursData = $parsed
            }
            else {
                # Might be the full devbox object returned by some endpoints
                $configSource = $parsed
            }
            break
        }
        catch {
            continue
        }
    }

    if ($Full) {
        if ($null -ne $activeHoursData) {
            [PSCustomObject]@{
                DevBox      = $configSource
                ActiveHours = $activeHoursData
            } | ConvertTo-Json -Depth 10 | Write-Output
        }
        else {
            Write-Output ($configSource | ConvertTo-Json -Depth 10)
        }
    }
    else {
        $startHour = if ($null -ne $activeHoursData) { $activeHoursData.StartTimeHour ?? $activeHoursData.startTimeHour } else { $null }
        $endHour   = if ($null -ne $activeHoursData) { $activeHoursData.EndTimeHour   ?? $activeHoursData.endTimeHour   } else { $null }
        $tz        = if ($null -ne $activeHoursData) { $activeHoursData.Timezone       ?? $activeHoursData.timezone       } else { $null }

        $startDisplay = if ($null -ne $startHour) { "${startHour}:00" } else { "(none)" }
        $endDisplay   = if ($null -ne $endHour)   { "${endHour}:00"   } else { "(none)" }
        $tzDisplay    = if ($null -ne $tz)         { $tz               } else { "(none)" }

        [PSCustomObject][ordered]@{
            Name              = $configSource.name
            PowerState        = $configSource.powerState
            ActionState       = $configSource.actionState
            ProvisioningState = $configSource.provisioningState
            ActiveHoursStart  = $startDisplay
            ActiveHoursEnd    = $endDisplay
            ActiveHoursTimezone = $tzDisplay
            Location          = $configSource.location
            PoolName          = $configSource.poolName
            LocalAdmin        = $configSource.localAdministrator
            OSType            = $configSource.osType
            vCPUs             = $configSource.hardwareProfile.vCPUs
            MemoryGB          = $configSource.hardwareProfile.memoryGB
            DiskGB            = $configSource.storageProfile.osDisk.diskSizeGB
            LastConnected     = $configSource.lastConnectedTime
        } | Format-List
    }
    exit
}

$usertz = tzutil /g

# Validate input parameters
if (-not [int]::TryParse($StartTimeHour, [ref]$null)) {
    Write-Error "StartTimeHour must be an integer."
    exit
}
if (-not [int]::TryParse($EndTimeHour, [ref]$null)) {
    Write-Error "EndTimeHour must be an integer."
    exit
}

$startHour = [int]$StartTimeHour
$endHour = [int]$EndTimeHour

if ($endHour -le $startHour) {
    Write-Error "EndTimeHour must be after StartTimeHour."
    exit
}

$body = @{
    StartTimeHour = $startHour
    EndTimeHour   = $endHour
    Timezone      = $usertz
}

$bodyStr = ConvertTo-Json $body

$devBoxUri = $devBox.uri
$activeHoursUriBase = "${devBoxUri}:setactivehours"

try {
    $setCall = Invoke-DevCenterRequest -UriBase $activeHoursUriBase -Method 'POST' -Token $secureToken -ApiVersions $devCenterApiVersions -ContentType "application/json" -Body $bodyStr
    $response = $setCall.Response
}
catch {
    Write-Error "Failed to set active hours: $($_.Exception.Message)"
    exit
}

if ($response.StatusCode -in @(200, 202, 204)) {
    Write-Host "Active hours set successfully."
}
else {
    Write-Error "Failed to set active hours. Status code: $($response.StatusCode)"
}
