#requires -Version 5.1
<#
    Packages ForeverPanel into dist/ForeverPanel-<version>.zip.

    The zip contains a single top-level ForeverPanel/ folder, so it can be
    extracted straight into Interface/AddOns.

    -Install also copies the addon into a WoW AddOns folder. Pass -WowPath to
    point at a different install; the default is the Classic beta client.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$toc = "ForeverPanel.toc"
if (-not (Test-Path $toc)) {
    Write-Error "$toc not found."
}

$tocLines = Get-Content $toc

$version = ($tocLines | Where-Object { $_ -match "^##\s*Version:\s*(.+)$" } |
    ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
if (-not $version) {
    Write-Error "No '## Version:' line in $toc."
}

# Everything the TOC loads, plus the TOC and readme.
$files = @($toc, "README.md")
foreach ($line in $tocLines) {
    $trimmed = $line.Trim()
    if ($trimmed -and -not $trimmed.StartsWith("#")) {
        $files += ($trimmed -replace "\\", "/")
    }
}

$missing = $files | Where-Object { -not (Test-Path $_) }
if ($missing) {
    Write-Error "Listed in $toc but missing on disk: $($missing -join ', ')"
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("ForeverPanel-pkg-" + [guid]::NewGuid().ToString("N"))
$addonRoot = Join-Path $staging "ForeverPanel"

try {
    foreach ($file in $files) {
        $target = Join-Path $addonRoot $file
        $targetDir = Split-Path $target -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item $file $target
    }

    $dist = Join-Path $PSScriptRoot "dist"
    if (-not (Test-Path $dist)) {
        New-Item -ItemType Directory -Path $dist | Out-Null
    }

    $zip = Join-Path $dist "ForeverPanel-$version.zip"
    if (Test-Path $zip) {
        Remove-Item $zip -Force
    }

    Compress-Archive -Path $addonRoot -DestinationPath $zip
    Write-Host "Packaged $($files.Count) files -> $zip"

    if ($Install) {
        $addons = Join-Path $WowPath "Interface\AddOns"
        if (-not (Test-Path $addons)) {
            New-Item -ItemType Directory -Path $addons -Force | Out-Null
        }

        $installed = Join-Path $addons "ForeverPanel"
        if (Test-Path $installed) {
            Remove-Item $installed -Recurse -Force
        }

        Copy-Item $addonRoot $addons -Recurse
        Write-Host "Installed -> $installed"
    }
}
finally {
    if (Test-Path $staging) {
        Remove-Item $staging -Recurse -Force
    }
}
