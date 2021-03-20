$activeRequests = [System.Collections.ArrayList]@()
$count=0

Import-Csv .\RequestData.csv | ForEach-Object {

    $count++

    ##Write-Host $_.StartTime, $_.Duration, $_.EndTime
    $currentTime = [datetime]::Parse($_.StartTime)
    $activeRequests.Add([datetime]::Parse($_.EndTime)) > $null

    if ($activeRequests.Count -gt 7) {
        Write-Host "$($currentTime) Active requests = $($activeRequests.Count)"
    } 
    for ($i = 0; $i -lt $activeRequests.Count; $i++) {
        ##Write-Host "requestEndTime = "$activeRequests[$i].TimeOfDay" vs. currentTime = "$currentTime.TimeOfDay
        if ($activeRequests[$i].TimeOfDay -lt $currentTime.TimeOfDay) {
            $activeRequests.RemoveAt($i)
            $i--
        }
    }

    if ($count % 50000 -eq 0) {
        Write-Host "Processed $($count) requests"
    }
}

Write-Host "Processed a total of $($count) requests"
