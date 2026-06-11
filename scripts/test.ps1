#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$BuildDir    = Join-Path $ProjectRoot "build"
$Exe         = Join-Path $BuildDir "bzip2.exe"

if (-not (Test-Path $Exe)) {
    Write-Error "bzip2.exe not found at '$Exe'. Run compile.ps1 first."
}

Write-Host "Running test suite..."
Write-Host ""

ctest --test-dir $BuildDir -C Release -V
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "All tests passed."
} else {
    Write-Error "One or more tests failed (ctest exit code $exitCode)."
}
