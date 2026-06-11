#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$BuildDir    = Join-Path $ProjectRoot "build"

# --- dependency check --------------------------------------------------

function Assert-ScoopPackage([string]$Pkg, [string]$Cmd = $Pkg) {
    if (Get-Command $Cmd -ErrorAction SilentlyContinue) {
        Write-Host "  [ok] $Pkg"
        return
    }
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Error "scoop is not installed and '$Cmd' is missing. Install scoop from https://scoop.sh, then re-run."
    }
    Write-Host "  [installing] $Pkg ..."
    scoop install $Pkg
    # Refresh PATH so the new shim is visible in this session
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','User') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH','Machine')
    if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Failed to install '$Pkg'. Please install it manually and retry."
    }
    Write-Host "  [ok] $Pkg"
}

Write-Host "Checking build dependencies..."
Assert-ScoopPackage cmake
Assert-ScoopPackage gcc
Assert-ScoopPackage ninja

# --- configure ---------------------------------------------------------

Write-Host ""
Write-Host "Configuring (CMake + Ninja + GCC, Release)..."
cmake -S $ProjectRoot -B $BuildDir `
      -G "Ninja" `
      -DCMAKE_C_COMPILER=gcc `
      -DCMAKE_BUILD_TYPE=Release

# --- build -------------------------------------------------------------

Write-Host ""
Write-Host "Building..."
cmake --build $BuildDir --config Release

# --- done --------------------------------------------------------------

$exe = Join-Path $BuildDir "bzip2.exe"
if (-not (Test-Path $exe)) {
    Write-Error "Build finished but bzip2.exe was not found at: $exe"
}

Write-Host ""
Write-Host "Build successful: $exe"
