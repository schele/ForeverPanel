#requires -Version 5.1
<#
    Packages each addon in this repo into dist/<name>-<version>.zip.

        .\package.ps1                          every addon
        .\package.ps1 ForeverPanel             just that one
        .\package.ps1 ForeverPanel -Install    and copy it into the client

    An addon is any top-level folder holding a .toc. The zip contains a single
    top-level folder named after the addon, so it extracts straight into
    Interface/AddOns.

    -Install copies into a WoW client; -WowPath picks which one.
#>
[CmdletBinding()]
param(
    [string[]]$Addon,
    [switch]$Install,
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$folders = Get-ChildItem -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "$($_.Name).toc")
}

if ($Addon) {
    $folders = $folders | Where-Object { $Addon -contains $_.Name }
    $missing = $Addon | Where-Object { $folders.Name -notcontains $_ }
    if ($missing) {
        Write-Error "No such addon: $($missing -join ', ')"
    }
}

if (-not $folders) {
    Write-Error "No addons found. An addon is a folder containing <name>.toc."
}

foreach ($folder in $folders) {
    $name = $folder.Name
    $toc = Join-Path $folder.FullName "$name.toc"
    $tocLines = Get-Content $toc

    $version = ($tocLines | Where-Object { $_ -match "^##\s*Version:\s*(.+)$" } |
        ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
    if (-not $version) {
        Write-Error "No '## Version:' line in $toc."
    }

    # Everything the TOC loads, plus the TOC itself. Read from the .toc rather
    # than globbed, so anything added there ships and anything missing fails
    # the build instead of shipping broken.
    $required = @("$name.toc")
    foreach ($line in $tocLines) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith("#")) {
            $required += ($trimmed -replace "\\", "/")
        }
    }

    $missingFiles = $required | Where-Object { -not (Test-Path (Join-Path $folder.FullName $_)) }
    if ($missingFiles) {
        Write-Error "Listed in $name.toc but missing on disk: $($missingFiles -join ', ')"
    }

    # The readme rides along when there is one, but is not required.
    $files = $required
    if (Test-Path (Join-Path $folder.FullName "README.md")) {
        $files += "README.md"
    }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("$name-pkg-" + [guid]::NewGuid().ToString("N"))
    $addonRoot = Join-Path $staging $name

    try {
        foreach ($file in $files) {
            $target = Join-Path $addonRoot $file
            $targetDir = Split-Path $target -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item (Join-Path $folder.FullName $file) $target
        }

        $dist = Join-Path $PSScriptRoot "dist"
        if (-not (Test-Path $dist)) {
            New-Item -ItemType Directory -Path $dist | Out-Null
        }

        $zip = Join-Path $dist "$name-$version.zip"
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

            $installed = Join-Path $addons $name
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
}
