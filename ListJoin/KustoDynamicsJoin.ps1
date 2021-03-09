(@"
one
two
three
four
"@.Split("`n") | %{ $_.Trim() }) -join ""","""  ##for use with Azure Data Explorer dynamics