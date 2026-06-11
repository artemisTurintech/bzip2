#Requires -Version 5.1
param(
    [int]$Runs = 1
)
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Exe         = Join-Path $ProjectRoot "build\bzip2.exe"
$SampleFile  = Join-Path $ProjectRoot "tests\sample2.ref"
$OutputFile  = Join-Path $ProjectRoot "artemis_results.json"

# --- validate ----------------------------------------------------------

if (-not (Test-Path $Exe)) {
    Write-Error "bzip2.exe not found at '$Exe'. Run compile.ps1 first."
}
if (-not (Test-Path $SampleFile)) {
    Write-Error "Sample file not found: $SampleFile"
}
if ($Runs -lt 1) {
    Write-Error "-Runs must be >= 1."
}

$inputSize = (Get-Item $SampleFile).Length

Write-Host "bzip2 throughput benchmark"
Write-Host "  Sample : $SampleFile ($([math]::Round($inputSize / 1KB, 1)) KB)"
Write-Host "  Runs   : $Runs  (+ 1 warm-up)"
Write-Host ""

# --- warm-up (not counted) ---------------------------------------------

Write-Host "  [warm-up] ..."
$null = & $Exe -c -9 $SampleFile
Write-Host ""

# --- measured runs -----------------------------------------------------

$throughputs = [System.Collections.Generic.List[double]]::new()
$errors = 0

for ($i = 1; $i -le $Runs; $i++) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $Exe -c -9 $SampleFile
        $sw.Stop()

        if ($LASTEXITCODE -ne 0) {
            $errors++
            Write-Warning "  Run $i/$Runs  FAILED (exit code $LASTEXITCODE)"
        } else {
            $tput = [double]$inputSize / $sw.Elapsed.TotalSeconds
            $throughputs.Add($tput)
            Write-Host ("  Run {0}/{1}  {2:F2} MB/s" -f $i, $Runs, ($tput / 1MB))
        }
    } catch {
        $errors++
        Write-Warning "  Run $i/$Runs  threw: $_"
    }
}

# --- statistics --------------------------------------------------------

if ($throughputs.Count -eq 0) {
    Write-Error "All $Runs runs failed. Cannot compute throughput statistics."
}

$mean = ($throughputs | Measure-Object -Average).Average

$sumSq = 0.0
foreach ($t in $throughputs) { $sumSq += [math]::Pow($t - $mean, 2) }
$stddev = [math]::Sqrt($sumSq / $throughputs.Count)

$errorRate = [math]::Round([double]$errors / $Runs, 4)

# --- output ------------------------------------------------------------

$result = @(
    [ordered]@{
        runs                = $Runs
        throughput_mean     = [math]::Round($mean,   2)
        throughput_stddev   = [math]::Round($stddev, 2)
        error_rate          = $errorRate
    }
)

$json = ConvertTo-Json -InputObject $result -Depth 3
Set-Content -Path $OutputFile -Value $json -Encoding UTF8

Write-Host ""
Write-Host "Results:"
Write-Host ("  Mean throughput  : {0:F3} MB/s  ({1:N0} bytes/s)" -f ($mean / 1MB), $mean)
Write-Host ("  Std deviation    : {0:F3} MB/s  ({1:N0} bytes/s)" -f ($stddev / 1MB), $stddev)
Write-Host ("  Error rate       : {0}" -f $errorRate)
Write-Host ""
Write-Host "Written to: $OutputFile"
