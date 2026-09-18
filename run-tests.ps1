#requires -Version 5.1
<#
    Runs the ForeverPanel test suite.

    Lua 5.4 is found on PATH, or at one of the locations winget's DEVCOM.Lua
    package installs to. Set $env:LUA_EXE to override.
#>

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

$specs = Get-ChildItem -Path "tests" -Filter "*_spec.lua" | ForEach-Object { "tests/$($_.Name)" }
if (-not $specs) {
    Write-Error "No spec files found in tests/."
}

& $lua "tests/runner.lua" @specs
exit $LASTEXITCODE
