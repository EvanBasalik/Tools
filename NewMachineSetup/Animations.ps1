# Script generated with Opus 4.6
# Due diligence: SystemParametersInfo is documented at https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow .
# For some info on SystemParemetersInfo vs SystemParametersInfoW, see https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow#remarks . 
# i.e. The winuser.h header defines SystemParametersInfo as an alias that automatically selects the ANSI or Unicode version of this function based on the definition of the UNICODE preprocessor constant. Mixing usage of the encoding-neutral alias with code that is not encoding-neutral can lead to mismatches that result in compilation or runtime errors. For more information, see Conventions for Function Prototypes.

if (-not ([System.Management.Automation.PSTypeName]'AnimationHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class AnimationHelper {
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
}
"@
}

# SPI_SETCLIENTAREAANIMATION = 0x1043 (Accessibility > Visual effects > Animation effects)
# SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 0x03
$result = [AnimationHelper]::SystemParametersInfo(0x1043, 0, [IntPtr]1, 0x03)

if ($result) {
    Write-Host "Animation effects enabled successfully."
} else {
    Write-Host "Failed to enable animation effects." -ForegroundColor Red
    exit 1
}
 