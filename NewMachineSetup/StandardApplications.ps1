#Must be run as admin
##Requires -RunAsAdministrator

# Define a list of package IDs to include
$personalinclude = @(
    "Apple.iTunes",
    "Apple.AppleMobileDeviceSupport",
    "Quicken.Quicken",
    #"Spotify.Spotify",
    "Microsoft.PowerToys",
    "Google.GoogleDrive",
    "Zoom.Zoom",
    "File-New-Project.EarTrumpet", # EarTrumpet
    "Microsoft.Powershell"
)

$workinclude = @(
    "Git.Git",
    "Microsoft.VisualStudio.2022.Community",
    "Microsoft.VisualStudioCode"
)

# Define a list of package IDs to exclude - typically for known version issues or conflicts
$exclude = @(
    "Microsoft.PowerToys"
    # , "Microsoft.VisualStudio.2022.Community"
)

# install the Microsoft.WinGet.Client module if not already installed
if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    Install-Module -Name Microsoft.WinGet.Client -Force
}
Import-Module -Name Microsoft.WinGet.Client

$packagestoinstall = ($personalinclude + $workinclude) | Where-Object { $exclude -notcontains $_ }

# Ensure each package is installed
$installed = (Get-WinGetPackage | Where-Object Source -eq winget).Id | Sort-Object
foreach ($pkg in $packagestoinstall) {
    Write-Host "Processing package: $pkg"
    if ($installed -contains $pkg) {
        $isInstalled = $true
    }
    else {
        $isInstalled = $false
    }
    if (-not $isInstalled) {
        #special case for Visual Studio 2022 Community Edition to account for the base.vsconfig file
        if ($pkg -eq "Microsoft.VisualStudio.2022.Community") {
            Write-Host "Installing missing package: $pkg"
            winget install Microsoft.VisualStudio.2022.Community -e --override "--wait --quiet --addProductLang En-us --config base.vsconfig" 
        }
        else {
            Write-Host "Installing missing package: $pkg"
            winget install --id $pkg --accept-source-agreements --accept-package-agreements
        }
    } else {
        Write-Host "Package already installed: $pkg. Updating if necessary."
        winget upgrade --id $pkg --accept-source-agreements --accept-package-agreements -e
    }
}




