$ErrorActionPreference = "Stop"

Write-Host "Checking Tennis Tracker iOS Windows prerequisites..."
Write-Host ""

Write-Host "Git repository:"
git status --short --branch
git remote -v
Write-Host ""

Write-Host "GitHub repository:"
gh repo view --json nameWithOwner,isPrivate,url,defaultBranchRef
Write-Host ""

Write-Host "Installed packages:"
winget list --id Apple.AppleMobileDeviceSupport --accept-source-agreements
winget list --id Apple.iTunes --accept-source-agreements
winget list --id Apple.iCloud --accept-source-agreements
Write-Host ""

Write-Host "Apple services:"
Get-Service | Where-Object {
    $_.Name -match "Apple|Bonjour|Mobile" -or $_.DisplayName -match "Apple|Bonjour|Mobile Device"
} | Select-Object Status,Name,DisplayName
Write-Host ""

Write-Host "Detected Apple devices:"
Get-PnpDevice -PresentOnly | Where-Object {
    $_.FriendlyName -match "iPhone|Apple|Mobile Device|iPad|iPod" -or $_.InstanceId -match "VID_05AC"
} | Select-Object Status,Class,FriendlyName,InstanceId

