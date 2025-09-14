param([string]$inputfile="input.txt", [string]$outputfile="output.txt") 
$text = Get-Content .\$inputfile -Raw 
($text.Split("`n") | %{ $_.Trim() }) -join """,""" >> $outputfile

($text.Split("`n") | ForEach-Object { $_.Trim() }) -join ";" | Set-Content $outputfile