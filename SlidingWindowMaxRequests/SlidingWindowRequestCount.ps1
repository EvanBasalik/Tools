$activeRequests = [System.Collections.ArrayList]@()
$count=0
$highCount=10
$filename = "requests.csv"

#Get-ChildItem -Filter *.csv | Select-Object -ExpandProperty FullName | Import-Csv | Export-Csv .\combinedcsvs.csv -NoTypeInformation
Write-Host "Analyzing $($filename) looking for instances processing more than $($highCount) requests simultaneously"
$file = Import-Csv .\$filename 
Write-Host "$($file.Count) records"

$file | ForEach-Object {

    $count++
    if ($count % 1000 -eq 0) {
        Write-Progress -Activity "Searching logs" -Status "$count records processed" -PercentComplete ($count/$file.Count*100)
    }

    ##Write-Host $_.StartTime, $_.Duration, $_.EndTime
    $currentTime = [datetime]::Parse($_.StartTime)
    $newRequest = [PSCustomObject]@{
        EndTime = [datetime]::Parse($_.EndTime)
        Instance = $_.cloud_RoleInstance
    }

    $activeRequests.Add($newRequest) > $null

    ##age out any completed requests
    for ($i = 0; $i -lt $activeRequests.Count; $i++) {
        ##Write-Host "requestEndTime = "$activeRequests[$i].EndTime.TimeOfDay" vs. currentTime = "$currentTime.TimeOfDay" on instance "$activeRequests[$i].Instance
        if ($activeRequests[$i].EndTime.TimeOfDay -lt $currentTime.TimeOfDay) {
            $activeRequests.RemoveAt($i)
            $i--
        }
    }

    ##Write-Host "Total active requests ="$activeRequests.Count
    $highReqCountInstances = ($activeRequests | Group-Object -Property Instance -NoElement | Where-Object {$_.Count -ge $highCount} | 
Select -ExpandProperty Count)
    if ($highReqCountInstances.Count -gt 0 ) {
        Write-Host "Timestamp = "$currentTime
        Write-Host "Total active requests ="$activeRequests.Count
        Write-Host "Instances with more than "$highCount" active requests"
        $activeRequests | Group-Object -Property Instance -NoElement | Where-Object {$_.Count -ge $highCount}
    }
}

Write-Host "Processed a total of $($count) requests"



