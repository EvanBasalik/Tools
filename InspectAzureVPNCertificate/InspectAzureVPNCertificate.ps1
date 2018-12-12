##Taken liberally from https://stackoverflow.com/questions/22233702/how-to-download-the-ssl-certificate-from-a-website-using-powershell
##Full credit to that answer for the general flow
$GWVIP = "104.42.9.178"
$uri = "https://$($GWVIP):8081/healthprobe"

$request = [System.Net.HttpWebRequest]::Create($uri)
try
{
    #Make the request but ignore (dispose it) the response, since we only care about the service point
    $request.GetResponse().Dispose()
}
catch [System.Net.WebException]
{
    if ($_.Exception.Status -eq [System.Net.WebExceptionStatus]::TrustFailure)
    {
        #We ignore trust failures, since we only want the certificate, and the service point is still populated at this point
    }
    else
    {
        #Let other exceptions bubble up, or write-error the exception and return from this method
        throw
    }
}

#The ServicePoint object should now contain the Certificate for the site.
$servicePoint = $request.ServicePoint
[System.Security.Cryptography.X509Certificates.X509Certificate]$cert=$servicePoint.Certificate
Write-Output $cert | Format-List * -f