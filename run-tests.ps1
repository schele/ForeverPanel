#requires -Version 5.1
<#
    Runs the ForeverPanel test suite.

    Lua 5.4 is expected at the location winget's DEVCOM.Lua package installs to.
    Set $env:LUA_EXE to override.
#>

$ErrorActionPreference = "Stop"

$lua = $env:LUA_EXE
if (-not $lua) {
    $lua = Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\lua.exe"
}

if (-not (Test-Path $lua)) {
    Write-Error "Lua not found at '$lua'. Install it with: winget install --id DEVCOM.Lua"
}

Set-Location $PSScriptRoot

$specs = Get-ChildItem -Path "tests" -Filter "*_spec.lua" | ForEach-Object { "tests/$($_.Name)" }
if (-not $specs) {
    Write-Error "No spec files found in tests/."
}

& $lua "tests/runner.lua" @specs
exit $LASTEXITCODE
