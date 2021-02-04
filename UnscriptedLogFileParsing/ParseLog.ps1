$file = "C:\\Users\\evanba\\OneDrive - Microsoft\Desktop\\dbhostname.txt"

[array]$rawText = $file_data = Get-Content $file | Where-Object {$_ -like "*Start Time*" -or $_ -like "*End Time*" }

$deltaSum
for ($i = 0; $i -lt $rawText.Count; $i+=2) {

    Write-Progress -Activity "Scanning $($file)" -PercentComplete ($i/$rawText.Count);

    $startTime = [datetime]::ParseExact((($rawText[$i] -Split(" Time :  "))[1] -split " ")[3],"HH:mm:ss",$null)
    $endTime = [datetime]::ParseExact((($rawText[$i+1] -Split(" Time :  "))[1] -split " ")[3],"HH:mm:ss",$null)
    $delta = $endTime - $startTime
    if ($delta.milliseconds -gt 500 ) {
        write-host "long delta of $($delta.milliseconds)"
    }
}