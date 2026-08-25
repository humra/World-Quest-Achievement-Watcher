param(
    [Parameter(Mandatory = $false)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# World Quest Achievement Watcher - CurseForge release builder
#
# Usage:
#   .\build-release.ps1
#   .\build-release.ps1 -Version 1.0.1
#
# The version in WorldQuestAchievementWatcher.toc is the source of truth.
# If -Version is supplied, it must match the TOC version.
# ---------------------------------------------------------------------------

$AddonFolderName = "WorldQuestAchievementWatcher"
$TocFileName = "WorldQuestAchievementWatcher.toc"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TocPath = Join-Path $RepoRoot $TocFileName
$DistDir = Join-Path $RepoRoot "dist"
$StageRoot = Join-Path $DistDir "_stage"
$StageAddonDir = Join-Path $StageRoot $AddonFolderName

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Remove-IfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

Write-Host ""
Write-Host "World Quest Achievement Watcher release builder" -ForegroundColor Cyan
Write-Host "Repository: $RepoRoot"

if (-not (Test-Path -LiteralPath $TocPath -PathType Leaf)) {
    Fail "Could not find $TocFileName in the repository root."
}

# Read and validate version from the TOC.
$TocContent = Get-Content -LiteralPath $TocPath
$VersionLine = $TocContent | Where-Object { $_ -match '^\s*##\s*Version\s*:\s*(.+?)\s*$' } | Select-Object -First 1

if (-not $VersionLine) {
    Fail "The TOC does not contain a '## Version:' line."
}

$TocVersion = ([regex]::Match($VersionLine, '^\s*##\s*Version\s*:\s*(.+?)\s*$')).Groups[1].Value.Trim()

if ([string]::IsNullOrWhiteSpace($TocVersion)) {
    Fail "The version in the TOC is empty."
}

if ($Version) {
    $RequestedVersion = $Version.Trim()
    if ($RequestedVersion -ne $TocVersion) {
        Fail "Requested version '$RequestedVersion' does not match TOC version '$TocVersion'. Update the TOC first."
    }
}
else {
    $Version = $TocVersion
}

# Allow normal semantic versions and prerelease suffixes such as 1.0.1-rc1.
if ($Version -notmatch '^\d+\.\d+\.\d+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$') {
    Fail "Version '$Version' does not look like a valid release version."
}

Write-Host "Version:    $Version" -ForegroundColor Green

# Verify every non-comment runtime path listed by the TOC exists.
$MissingTocFiles = @()

foreach ($Line in $TocContent) {
    $Entry = $Line.Trim()

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        continue
    }

    if ($Entry.StartsWith("##")) {
        continue
    }

    # TOC entries use backslashes. Join-Path handles them correctly on Windows.
    $RuntimePath = Join-Path $RepoRoot $Entry

    if (-not (Test-Path -LiteralPath $RuntimePath -PathType Leaf)) {
        $MissingTocFiles += $Entry
    }
}

if ($MissingTocFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing file(s) referenced by the TOC:" -ForegroundColor Red
    foreach ($Missing in $MissingTocFiles) {
        Write-Host "  - $Missing" -ForegroundColor Red
    }
    Fail "Release aborted because the TOC references missing files."
}

Write-Host "TOC check:  all referenced runtime files exist" -ForegroundColor Green

# Clean only our temporary staging directory. Existing release ZIPs remain intact.
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
Remove-IfExists $StageRoot
New-Item -ItemType Directory -Path $StageAddonDir -Force | Out-Null

# Repository content that must never be shipped as part of the installed addon.
$ExcludedTopLevelDirectories = @(
    ".git",
    ".github",
    ".vs",
    ".vscode",
    "CurseForge icons",
    "dist"
)

$ExcludedTopLevelFiles = @(
    ".gitignore",
    ".gitattributes",
    "build-release.ps1"
)

function Should-Exclude {
    param(
        [string]$RelativePath,
        [bool]$IsDirectory
    )

    $Normalized = $RelativePath.Replace("/", "\")
    $TopLevel = ($Normalized -split '\\')[0]

    if ($IsDirectory -and ($ExcludedTopLevelDirectories -contains $TopLevel)) {
        return $true
    }

    if (-not $IsDirectory -and ($ExcludedTopLevelFiles -contains $Normalized)) {
        return $true
    }

    # Common local/editor/temp files anywhere in the tree.
    $Leaf = Split-Path -Leaf $Normalized

    if ($Leaf -match '~$') { return $true }
    if ($Leaf -match '\.bak$') { return $true }
    if ($Leaf -match '\.tmp$') { return $true }
    if ($Leaf -eq "Thumbs.db") { return $true }
    if ($Leaf -eq ".DS_Store") { return $true }

    return $false
}

# Copy the repository into the correctly named addon folder.
$Items = Get-ChildItem -LiteralPath $RepoRoot -Force

foreach ($Item in $Items) {
    $Relative = $Item.Name

    if (Should-Exclude -RelativePath $Relative -IsDirectory $Item.PSIsContainer) {
        Write-Host "Excluding:  $Relative" -ForegroundColor DarkGray
        continue
    }

    $Destination = Join-Path $StageAddonDir $Item.Name

    if ($Item.PSIsContainer) {
        Copy-Item -LiteralPath $Item.FullName -Destination $Destination -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $Item.FullName -Destination $Destination -Force
    }
}

# Defensive cleanup in case excluded files were nested or copied indirectly.
Get-ChildItem -LiteralPath $StageAddonDir -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq ".git" -or
        $_.Name -eq ".github" -or
        $_.Name -eq ".DS_Store" -or
        $_.Name -eq "Thumbs.db"
    } |
    Sort-Object FullName -Descending |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Validate the package root.
$PackagedToc = Join-Path $StageAddonDir $TocFileName
if (-not (Test-Path -LiteralPath $PackagedToc -PathType Leaf)) {
    Fail "The staged addon does not contain $TocFileName."
}

# Make sure the staged TOC still reports the intended version.
$PackagedVersionLine = Get-Content -LiteralPath $PackagedToc |
    Where-Object { $_ -match '^\s*##\s*Version\s*:\s*(.+?)\s*$' } |
    Select-Object -First 1

$PackagedVersion = ([regex]::Match(
    $PackagedVersionLine,
    '^\s*##\s*Version\s*:\s*(.+?)\s*$'
)).Groups[1].Value.Trim()

if ($PackagedVersion -ne $Version) {
    Fail "Staged TOC version '$PackagedVersion' does not match release version '$Version'."
}

$ZipName = "$AddonFolderName-$Version.zip"
$ZipPath = Join-Path $DistDir $ZipName

Remove-IfExists $ZipPath

# Compress the ADDON FOLDER itself so the ZIP has:
# WorldQuestAchievementWatcher/
#   WorldQuestAchievementWatcher.toc
#   ...
Compress-Archive -LiteralPath $StageAddonDir -DestinationPath $ZipPath -CompressionLevel Optimal -Force

if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    Fail "ZIP creation failed."
}

$ZipInfo = Get-Item -LiteralPath $ZipPath
if ($ZipInfo.Length -le 0) {
    Fail "The generated ZIP is empty."
}

# Remove temporary staging content after a successful build.
Remove-IfExists $StageRoot

Write-Host ""
Write-Host "Release package created successfully." -ForegroundColor Green
Write-Host "ZIP: $ZipPath" -ForegroundColor Cyan
Write-Host ("Size: {0:N2} MB" -f ($ZipInfo.Length / 1MB))
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  1. Extract this exact ZIP into a temporary folder."
Write-Host "  2. Confirm it contains a single '$AddonFolderName' folder."
Write-Host "  3. Test that packaged copy in WoW."
Write-Host "  4. Upload the ZIP from 'dist' to CurseForge."
Write-Host ""
