$ErrorActionPreference = "Stop"

$workflowName = "iOS free development build"
$artifactName = "tennis-tracker-ios-development-unsigned"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$artifactsRoot = Join-Path $projectRoot "artifacts"
$buildsRoot = Join-Path $projectRoot "builds"

New-Item -ItemType Directory -Force -Path $artifactsRoot,$buildsRoot | Out-Null

$runJson = gh run list --workflow $workflowName --branch codex/ios-poc --status success --limit 1 --json databaseId,createdAt,headSha | ConvertFrom-Json
if (-not $runJson) {
    throw "No successful GitHub Actions run was found for workflow '$workflowName'."
}

$runId = $runJson[0].databaseId
$downloadDir = Join-Path $artifactsRoot "github-run-$runId"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

gh run download $runId --name $artifactName --dir $downloadDir

$sourceIpa = Join-Path $downloadDir "TennisTracker-unsigned.ipa"
if (-not (Test-Path $sourceIpa)) {
    throw "Downloaded artifact did not contain TennisTracker-unsigned.ipa."
}

$destinationIpa = Join-Path $buildsRoot "TennisTracker-development-unsigned-$runId.ipa"
Copy-Item -Path $sourceIpa -Destination $destinationIpa -Force

$ipa = Get-Item $destinationIpa
if ($ipa.Length -le 0) {
    throw "Downloaded IPA is empty: $($ipa.FullName)"
}

Write-Host "Downloaded IPA:"
Write-Host $ipa.FullName
Write-Host "Size in bytes: $($ipa.Length)"

& (Join-Path $PSScriptRoot "verify_ipa_watch_embed.ps1")
