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

if (-not (Test-Path $Exe))        { Write-Error "bzip2.exe not found. Run compile.ps1 first." }
if (-not (Test-Path $SampleFile)) { Write-Error "Sample file not found: $SampleFile" }
if ($Runs -lt 1)                  { Write-Error "-Runs must be >= 1." }

$inputSize = (Get-Item $SampleFile).Length
Write-Host "bzip2 benchmark"
Write-Host "  Sample : $SampleFile ($([math]::Round($inputSize / 1KB, 1)) KB)"
Write-Host "  Runs   : $Runs (+ 1 warm-up)"
Write-Host ""

# --- build reference .bz2 for decompress benchmark (binary-safe) ------
# Uses .NET Process directly to avoid PowerShell pipeline encoding issues.

$tmpBz2 = [System.IO.Path]::GetTempFileName() + ".bz2"
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Exe
    $psi.Arguments              = "-c -9 `"$SampleFile`""
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow         = $true

    $ref = [System.Diagnostics.Process]::Start($psi)
    $fs  = [System.IO.File]::OpenWrite($tmpBz2)
    $ref.StandardOutput.BaseStream.CopyTo($fs)
    $fs.Close()
    $ref.WaitForExit()
    if ($ref.ExitCode -ne 0) { throw "bzip2 exited $($ref.ExitCode)" }
} catch {
    Remove-Item $tmpBz2 -ErrorAction SilentlyContinue
    Write-Error "Failed to build reference compressed file: $_"
}

$compressedSize = (Get-Item $tmpBz2).Length
$compressRatio  = [double]$compressedSize / $inputSize
Write-Host ("  Compressed size : {0} bytes  (ratio {1:F6})" -f $compressedSize, $compressRatio)
Write-Host ""

# --- warm-up (not counted) --------------------------------------------

Write-Host "  [warm-up] ..."
$null = & $Exe -c -9 $SampleFile
$null = & $Exe -d -c $tmpBz2
Write-Host ""

# --- stats helper ------------------------------------------------------

function Get-Stats ([System.Collections.Generic.List[double]]$data) {
    if ($data.Count -eq 0) { return [ordered]@{ mean = 0.0; stdev = 0.0 } }
    $mean  = ($data | Measure-Object -Average).Average
    $sumSq = 0.0
    foreach ($x in $data) { $sumSq += [math]::Pow($x - $mean, 2) }
    $stdev = if ($data.Count -gt 1) { [math]::Sqrt($sumSq / $data.Count) } else { 0.0 }
    return [ordered]@{ mean = $mean; stdev = $stdev }
}

# --- timed runs --------------------------------------------------------

$cList  = [System.Collections.Generic.List[double]]::new()
$dList  = [System.Collections.Generic.List[double]]::new()
$errors = 0

for ($i = 1; $i -le $Runs; $i++) {
    try {
        # compress: original file → stdout (discarded); time the wall-clock
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $Exe -c -9 $SampleFile
        $sw.Stop()
        $cOk = ($LASTEXITCODE -eq 0)

        # decompress: reference .bz2 → stdout (discarded); time the wall-clock
        $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $Exe -d -c $tmpBz2
        $sw2.Stop()
        $dOk = ($LASTEXITCODE -eq 0)

        if (-not ($cOk -and $dOk)) {
            $errors++
            Write-Warning "  Run $i/$Runs FAILED (compress=$cOk decompress=$dOk)"
            continue
        }

        $cMbps = ($inputSize / $sw.Elapsed.TotalSeconds)  / 1MB
        $dMbps = ($inputSize / $sw2.Elapsed.TotalSeconds) / 1MB
        $cList.Add($cMbps)
        $dList.Add($dMbps)

        Write-Host ("  Run {0}/{1}  compress {2:F2} MB/s   decompress {3:F2} MB/s" -f $i, $Runs, $cMbps, $dMbps)
    } catch {
        $errors++
        Write-Warning "  Run $i/$Runs threw: $_"
    }
}

Remove-Item $tmpBz2 -ErrorAction SilentlyContinue

if ($cList.Count -eq 0) { Write-Error "All runs failed - cannot compute statistics." }

# --- statistics --------------------------------------------------------

$cs = Get-Stats $cList
$ds = Get-Stats $dList

# Overall score: geometric mean of compress speed, decompress speed, and compression quality.
# compression quality = 1 - ratio  (0 = no compression, 1 = perfect compression)
# Scaled by 100 so the cube-root yields a human-readable number; higher is better.
$quality      = 1.0 - $compressRatio
$overallScore = [math]::Round([math]::Pow($cs.mean * $ds.mean * $quality * 100.0, 1.0 / 3.0), 2)

# --- write JSON --------------------------------------------------------

$result = @(
    [ordered]@{
        runs                        = $Runs
        compress_mbps_mean          = [math]::Round($cs.mean,        2)
        compress_mbps_stdev         = [math]::Round($cs.stdev,       2)
        compress_mbps_better_when   = "higher"
        decompress_mbps_mean        = [math]::Round($ds.mean,        2)
        decompress_mbps_stdev       = [math]::Round($ds.stdev,       2)
        decompress_mbps_better_when = "higher"
        compress_ratio_mean         = [math]::Round($compressRatio,  6)
        compress_ratio_stdev        = [math]::Round([double]0.0,     6)
        compress_ratio_better_when  = "lower"
        overall_score               = $overallScore
        overall_score_better_when   = "higher"
    }
)

$json = ConvertTo-Json -InputObject $result -Depth 3
Set-Content -Path $OutputFile -Value $json -Encoding UTF8

# --- console summary ---------------------------------------------------

Write-Host ""
Write-Host "Results:"
Write-Host ("  Compress    : {0:F2} +/- {1:F2} MB/s" -f $cs.mean, $cs.stdev)
Write-Host ("  Decompress  : {0:F2} +/- {1:F2} MB/s" -f $ds.mean, $ds.stdev)
Write-Host ("  Ratio       : {0:F6}  ({1:F1} pct size reduction)" -f $compressRatio, ($quality * 100))
Write-Host ("  Score       : {0}" -f $overallScore)
Write-Host ""
Write-Host "Written to: $OutputFile"
