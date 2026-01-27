<#
extract_fortio_results.ps1
- Crawls results\exp_patterns_minikube_v1
- Reads all fortio_*.json (even if they contain "Successfully wrote ...")
- Outputs one CSV: summary_fortio.csv (one row per fortio json)

Run from repo root:
  Set-ExecutionPolicy -Scope Process Bypass -Force
  .\scripts\extract_fortio_results.ps1
#>

$ErrorActionPreference = "Stop"

# ===== CONFIG =====
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Root = Join-Path $RepoRoot "results\exp_patterns_minikube_v1"
$Out = Join-Path $Root "summary_fortio.csv"

Write-Host "Root:" $Root
Write-Host "Out :" $Out

if (!(Test-Path $Root)) {
    throw "Root folder does not exist: $Root"
}

# ===== HELPERS =====

function Parse-FortioJson([string]$file) {
    $raw = Get-Content $file -Raw

    # keep only the JSON block (some files contain Fortio text before/inside)
    $start = $raw.IndexOf('{')
    $end   = $raw.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }

    $jsonText = $raw.Substring($start, $end - $start + 1)

    # remove noise lines
    $jsonText = (
    $jsonText -split "`r?`n" | Where-Object {
        $_ -notmatch '^Successfully wrote .* bytes of Json data to stdout$' -and
                $_ -notmatch '^Sockets used:' -and
                $_ -notmatch '^Uniform:' -and
                $_ -notmatch '^IP addresses distribution:' -and
                $_ -notmatch '^Code 200' -and
                $_ -notmatch '^All done ' -and
                $_ -notmatch '^Fortio ' -and
                $_ -notmatch '^$'
    }
    ) -join "`n"

    try {
        return ($jsonText | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-P($j, [int]$p) {
    if (-not $j.DurationHistogram) { return $null }
    if (-not $j.DurationHistogram.Percentiles) { return $null }
    ($j.DurationHistogram.Percentiles | Where-Object { $_.Percentile -eq $p } | Select-Object -First 1).Value
}

# ===== MAIN =====

$skips = 0

$rows = Get-ChildItem $Root -Recurse -Filter "fortio_*.json" | ForEach-Object {

    $j = Parse-FortioJson $_.FullName
    if (-not $j) {
        Write-Host "SKIP (bad json): $($_.FullName)"
        $script:skips++
        return
    }

    # infer meta from folder path: pattern\strategy\repX\fortio_segment.json
    $rel = $_.FullName.Substring((Resolve-Path $Root).Path.Length).TrimStart('\')
    $parts = $rel.Split('\')

    # expected: pattern\strategy\repX\fortio_*.json
    if ($parts.Count -lt 4) {
        Write-Host "SKIP (path too short): $rel"
        $script:skips++
        return
    }

    $pattern  = $parts[0]
    $strategy = $parts[1]
    $rep      = $parts[2]
    $segment  = $_.BaseName -replace '^fortio_',''

    $p50 = Get-P $j 50
    $p90 = Get-P $j 90
    $p99 = Get-P $j 99

    [pscustomobject]@{
        pattern  = $pattern
        strategy = $strategy
        rep      = $rep
        segment  = $segment
        qps_req  = $j.RequestedQPS
        qps_act  = [math]::Round([double]$j.ActualQPS, 3)
        count    = [int]$j.DurationHistogram.Count
        avg_ms   = [math]::Round(([double]$j.DurationHistogram.Avg) * 1000, 3)
        p50_ms   = if ($null -ne $p50) { [math]::Round(([double]$p50) * 1000, 3) } else { $null }
        p90_ms   = if ($null -ne $p90) { [math]::Round(([double]$p90) * 1000, 3) } else { $null }
        p99_ms   = if ($null -ne $p99) { [math]::Round(([double]$p99) * 1000, 3) } else { $null }
        max_ms   = [math]::Round(([double]$j.DurationHistogram.Max) * 1000, 3)
        code200  = $j.RetCodes."200"
        errors   = $j.ErrorsDurationHistogram.Count
        start    = $j.StartTime
        file     = $rel
    }
}

# write CSV
$rows |
        Sort-Object pattern, strategy, rep, segment |
        Export-Csv $Out -NoTypeInformation -Force

Write-Host "OK: CSV written to $Out"
Write-Host "Rows:" ($rows | Measure-Object).Count " | Skipped:" $skips