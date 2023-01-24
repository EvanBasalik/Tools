param([string]$inputfile="input.txt", [string]$outputfile="output.txt") 
$text = Get-Content .\$inputfile -Raw 
($text.Split("`n") | %{ $_.Trim() }) -join """,""" >> $outputfile