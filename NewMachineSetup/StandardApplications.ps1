#Must be run as admin
#Requires -RunAsAdministrator

###   Personal   ###
#iTunes
winget install Apple.Itunes -e
winget install Apple.AppleMobileDeviceSupport -e

#Quicken
winget install Quicken.Quicken -e

#EarTrumpet
winget install --Id 9NBLGGH516XP -e

#Spotify
winget install Spotify.Spotify -e

###   Work   ###
#VSCode
winget install Microsoft.VisualStudioCode -e

#PowerToys
winget install --id=Microsoft.PowerToys -e

#Git
winget install --id Git.Git -e --source winget

#Visual Studio
winget install Microsoft.VisualStudio.2022.Community -e --override "--wait --quiet --addProductLang En-us --config base.vsconfig"