$locks = Get-AzResourceLock
 
$targetLocks = $locks | Where-Object { $_.Name -like "*-lock" }
 
 
foreach ($lock in $targetLocks) 
{
    Write-Host "Removing lock: $($lock.Name) on $($lock.ResourceName)"
    Remove-AzResourceLock -LockId $lock.LockId -Force
}