#requires -Version 5.1
<#
    Runs the test suites of every addon in this repo, or just the ones named.

        .\run-tests.ps1                 every addon
        .\run-tests.ps1 ForeverPanel    just that one

    An addon is any top-level folder holding a .toc. Its specs run with that
    folder as the working directory, so a suite never needs to know where the
    repo sits or that other addons exist.

    Lua 5.4 is found on PATH, or at one of the locations winget's DEVCOM.Lua
    package installs to. Set $env:LUA_EXE to override.
#>
[CmdletBinding()]
param([string[]]$Addon)

$ErrorActionPreference = "Stop"

$lua = $env:LUA_EXE

if (-not $lua) {
    $onPath = Get-Command "lua.exe" -ErrorAction SilentlyContinue
    if ($onPath) {
        $lua = $onPath.Source
    }
}

if (-not $lua) {
    # winget links user-scope installs here; older ones landed under Programs\Lua.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\lua.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\lua.exe")
    )
    $lua = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $lua -or -not (Test-Path $lua)) {
    Write-Error "Lua not found on PATH or in the usual install locations. Install it with: winget install --id DEVCOM.Lua"
}

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

$failed = @()

foreach ($folder in $folders) {
    $specs = Get-ChildItem -Path (Join-Path $folder.FullName "tests") -Filter "*_spec.lua" -ErrorAction SilentlyContinue
    if (-not $specs) {
        Write-Host "$($folder.Name): no tests"
        continue
    }

    Write-Host "== $($folder.Name)"

    Push-Location $folder.FullName
    try {
        & $lua "tests/runner.lua" @($specs | ForEach-Object { "tests/$($_.Name)" })
        if ($LASTEXITCODE -ne 0) {
            $failed += $folder.Name
        }
    }
    finally {
        Pop-Location
    }
}

if ($failed) {
    Write-Error "Failing suites: $($failed -join ', ')"
}
