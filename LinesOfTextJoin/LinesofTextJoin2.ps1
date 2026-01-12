$text = @"
apple
banana
cherry
date
"@

# Split lines, remove empty entries, join with semicolons
$result = ($text -split "`r?`n" | Where-Object { $_ -ne "" }) -join ";"
Write-Output $result