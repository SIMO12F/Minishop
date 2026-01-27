<#
run_patterns.ps1
SCRIPT_VERSION: 2026-01-25-PATTERNS-v7.5

Fixes:
- Root cause fix: fortio cannot create /tmp or /var/tmp -> use `-json -` (stdout)
- Save JSON locally via `kubectl logs` => fortio does NOT need write permissions
- No kubectl exec, no kubectl cp
- Keep debug artifacts: describe + logs for every segment
- Keep kubectl selection (single exe)
- Keep K8s name sanitization
#>

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "2026-01-25-PATTERNS-v7.5 (fortio json via stdout + no cp/exec)"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Namespace = "minishop"

$OutRoot = Join-Path $RepoRoot "results\exp_patterns_minikube_v1"
$BaseManifest = Join-Path $RepoRoot "k8s\minishop.yaml"
$AutoscalingDir = Join-Path $RepoRoot "k8s\autoscaling"

$TargetUrl = "http://gateway-service:8081/actuator/health"

$Concurrency = 10
$WarmupSeconds = 5

# ============================
# RUN CONFIG (YOU REQUESTED)
# ============================
$Reps = 3
$PatternsToRun = @("spike")
$StrategiesToRun = @("hybrid")

# pick ONE kubectl.exe (avoid the "two paths" bug)
$kubectlCandidates = @(Get-Command kubectl -All -CommandType Application -ErrorAction Stop)
$preferred = $kubectlCandidates | Where-Object { $_.Source -match "WinGet\\Links\\kubectl\.exe" } | Select-Object -First 1
if (-not $preferred) {
    $preferred = $kubectlCandidates | Where-Object { $_.Source -match "Docker\\Docker\\resources\\bin\\kubectl\.exe" } | Select-Object -First 1
}
if (-not $preferred) { $preferred = $kubectlCandidates | Select-Object -First 1 }
$KubectlCmd = $preferred.Source

function Log([string]$msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$ts] $msg"
}

function Ensure-Dir([string]$path) {
    if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

function Invoke-Kubectl {
    param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Args)
    & $KubectlCmd @Args
}

function Check-Minikube {
    Log "Checking minikube status..."
    $out = & minikube status 2>$null
    if ($LASTEXITCODE -ne 0) { throw "minikube is not running. Start it: minikube start" }
    $out | ForEach-Object { Write-Host $_ }
}

function Ensure-MetricsServer {
    Log "Ensuring metrics-server addon..."
    & minikube addons enable metrics-server | Out-Null
}

function Apply-BaseManifest {
    Log "Applying base manifest: $BaseManifest"
    Invoke-Kubectl "apply" "-f" $BaseManifest | Out-Null
}

function Wait-Rollout([string]$ns) {
    foreach ($dep in @("gateway-service","order-service","product-service")) {
        Log "Waiting rollout: deployment/$dep"
        Invoke-Kubectl "-n" $ns "rollout" "status" ("deployment/$dep") "--timeout=180s" | Out-Null
    }
}

function Wait-PodsReady([string]$ns, [string]$selector) {
    Log "Waiting pods Ready for selector: $selector"
    Invoke-Kubectl "-n" $ns "wait" "pod" "-l" $selector "--for=condition=Ready" "--timeout=180s" | Out-Null
}

function Check-GatewayHealth([string]$ns) {
    Log "Checking gateway health (in-cluster): $TargetUrl"
    Invoke-Kubectl "-n" $ns "run" "nettest" "--rm" "--stdin=true" "--restart=Never" "--image=busybox:1.36" "--" `
        "wget" "-q" "-O-" $TargetUrl | Out-Null
}

function Cleanup-Autoscaling([string]$ns) {
    if (Test-Path $AutoscalingDir) {
        Log "kubectl delete -f $AutoscalingDir (ignore-not-found)"
        try { Invoke-Kubectl "-n" $ns "delete" "-f" $AutoscalingDir "--ignore-not-found" | Out-Null } catch {}
    }
}

function Apply-Strategy([string]$ns, [string]$strategy) {
    Cleanup-Autoscaling $ns

    if ($strategy -eq "baseline") {
        Log "Strategy=baseline -> no autoscaling resources applied."
        return
    }

    $rbacHpa       = Join-Path $AutoscalingDir "autoscaler-rbac-hpa.yaml"
    $reactiveHpa   = Join-Path $AutoscalingDir "reactive-hpa.yaml"
    $proactiveCron = Join-Path $AutoscalingDir "proactive-cron.yaml"
    $hybridCron    = Join-Path $AutoscalingDir "hybrid-cron.yaml"

    $files = @()

    switch ($strategy) {
        "reactive"   { $files += $rbacHpa; $files += $reactiveHpa }
        "proactive"  { $files += $proactiveCron }
        "hybrid"     { $files += $rbacHpa; $files += $reactiveHpa; $files += $hybridCron }
        default      { throw "Unknown strategy: $strategy" }
    }

    foreach ($f in $files) {
        if (!(Test-Path $f)) { throw "Missing strategy file: $f" }
        Log "Applying: $f"
        Invoke-Kubectl "-n" $ns "apply" "-f" $f | Out-Null
    }

    Start-Sleep -Seconds 2
}

function Save-Snapshot([string]$ns, [string]$outDir, [string]$label) {
    $snapDir = Join-Path $outDir "metrics"
    Ensure-Dir $snapDir
    $prefix = Join-Path $snapDir $label

    try { Invoke-Kubectl "-n" $ns "get" "pods" "-o" "wide"   | Out-File -Encoding utf8 "$prefix.pods.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "get" "deploy" "-o" "wide"  | Out-File -Encoding utf8 "$prefix.deploy.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "get" "hpa" "-o" "wide"     | Out-File -Encoding utf8 "$prefix.hpa.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "get" "cronjob" "-o" "wide"  | Out-File -Encoding utf8 "$prefix.cronjob.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "top" "pods"                | Out-File -Encoding utf8 "$prefix.top_pods.txt" } catch {}
    try { Invoke-Kubectl "top" "nodes"                         | Out-File -Encoding utf8 "$prefix.top_nodes.txt" } catch {}
}

function Sanitize-K8sName([string]$s) {
    $x = $s.ToLower()
    $x = $x -replace "_", "-"
    $x = $x -replace "[^a-z0-9\-\.]", "-"
    $x = $x.Trim("-")
    if ($x.Length -eq 0) { $x = "x" }
    return $x
}

function New-FortioPodName([string]$segmentName) {
    $rand = -join ((48..57) + (97..102) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    $seg = Sanitize-K8sName $segmentName
    return ("fortio-{0}-{1}" -f $seg, $rand)
}

function Wait-PodExists([string]$ns, [string]$podName, [int]$timeoutSec = 60) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { Invoke-Kubectl "-n" $ns "get" "pod" $podName | Out-Null; return } catch {}
        Start-Sleep -Milliseconds 500
    }
    throw "Pod did not appear: $podName"
}

function Wait-PodFinished([string]$ns, [string]$podName, [int]$timeoutSec = 900) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $phase = (Invoke-Kubectl "-n" $ns "get" "pod" $podName "-o" "jsonpath={.status.phase}")
            if ($phase -eq "Succeeded" -or $phase -eq "Failed") { return $phase }
        } catch {}
        Start-Sleep -Seconds 1
    }
    throw "Timeout waiting pod to finish: $podName"
}

function Run-FortioSegment {
    param(
        [string]$ns,
        [string]$outDir,
        [string]$segmentName,
        [int]$qps,
        [int]$durationSec,
        [int]$concurrency,
        [string]$url
    )

    $podName = New-FortioPodName $segmentName

    Log "Starting fortio pod: $podName | $segmentName | qps=$qps | t=${durationSec}s | c=$concurrency"

    # IMPORTANT: -json - writes JSON to stdout. No file write in container => no crash.
    # -quiet + -logger-json=false => keep logs clean (JSON-only)
    $args = @(
        "-n", $ns, "run", $podName,
        "--restart=Never",
        "--image=fortio/fortio:latest",
        "--",
        "load",
        "-qps", "$qps",
        "-t", "${durationSec}s",
        "-c", "$concurrency",
        "-json", "-",
        "-quiet",
        "-logger-json=false",
        "$url"
    )

    $out = Invoke-Kubectl @args
    if ($out) { Log "kubectl run> $out" }

    Wait-PodExists $ns $podName 60
    Save-Snapshot $ns $outDir ("segment_{0}_start" -f $segmentName)

    $phase = Wait-PodFinished $ns $podName 900
    Log "Fortio finished: $podName (phase=$phase)"

    # JSON result (stdout)
    $jsonFile = Join-Path $outDir ("fortio_{0}.json" -f $segmentName)
    Invoke-Kubectl "-n" $ns "logs" $podName "--all-containers=true" | Out-File -Encoding utf8 $jsonFile

    # Describe for debugging always
    $descFile = Join-Path $outDir ("fortio_{0}.describe.txt" -f $segmentName)
    try { Invoke-Kubectl "-n" $ns "describe" "pod" $podName | Out-File -Encoding utf8 $descFile } catch {}

    Save-Snapshot $ns $outDir ("segment_{0}_end" -f $segmentName)

    # Cleanup
    try { Invoke-Kubectl "-n" $ns "delete" "pod" $podName "--ignore-not-found" | Out-Null } catch {}
}

function Get-PatternSegments([string]$pattern) {
    switch ($pattern) {
        "spike" {
            return @(
                [PSCustomObject]@{ Name="low_1";  Qps=10; DurationSec=60 },
                [PSCustomObject]@{ Name="spike";  Qps=60; DurationSec=30 },
                [PSCustomObject]@{ Name="low_2";  Qps=10; DurationSec=60 }
            )
        }
        "daynight" {
            return @(
                [PSCustomObject]@{ Name="night_1"; Qps=10; DurationSec=60 },
                [PSCustomObject]@{ Name="day";     Qps=30; DurationSec=90 },
                [PSCustomObject]@{ Name="night_2"; Qps=10; DurationSec=60 }
            )
        }
        default { throw "Unknown pattern: $pattern" }
    }
}

Log "SCRIPT_VERSION: $SCRIPT_VERSION"
Log "RepoRoot: $RepoRoot"
Log "Namespace: $Namespace"
Log "OutRoot: $OutRoot"
Log "Using kubectl: $KubectlCmd"

Ensure-Dir $OutRoot

Check-Minikube
Ensure-MetricsServer

Apply-BaseManifest
Wait-Rollout $Namespace
Wait-PodsReady $Namespace "app=gateway-service"
Check-GatewayHealth $Namespace

Log ("Strategies: {0}" -f ($StrategiesToRun -join ", "))
Log ("Patterns: {0} | Reps: {1}" -f ($PatternsToRun -join ", "), $Reps)

foreach ($strategy in $StrategiesToRun) {
    Log "=============================="
    Log "STRATEGY: $strategy"
    Log "=============================="

    Apply-Strategy $Namespace $strategy
    Wait-Rollout $Namespace
    Wait-PodsReady $Namespace "app=gateway-service"

    foreach ($pattern in $PatternsToRun) {
        $segments = Get-PatternSegments $pattern
        $segStr = ($segments | ForEach-Object { "{0}:qps={1},t={2}s" -f $_.Name,$_.Qps,$_.DurationSec }) -join " | "

        for ($rep = 1; $rep -le $Reps; $rep++) {
            Log "-------------------------------------------"
            Log "PATTERN=$pattern | STRATEGY=$strategy | REP=$rep"
            Log "Segments: $segStr"
            Log "-------------------------------------------"

            $repDir = Join-Path $OutRoot (Join-Path $pattern (Join-Path $strategy ("rep{0}" -f $rep)))
            Ensure-Dir $repDir

            Log "Warmup: qps=10 t=${WarmupSeconds}s"
            Run-FortioSegment -ns $Namespace -outDir $repDir -segmentName "warmup" -qps 10 -durationSec $WarmupSeconds -concurrency $Concurrency -url $TargetUrl
            Start-Sleep -Seconds 2

            foreach ($s in $segments) {
                Run-FortioSegment -ns $Namespace -outDir $repDir -segmentName $s.Name -qps $s.Qps -durationSec $s.DurationSec -concurrency $Concurrency -url $TargetUrl
                Start-Sleep -Seconds 2
            }

            Log "Completed: $repDir"
        }
    }

    Cleanup-Autoscaling $Namespace
}

Log "Done. Results saved under: $OutRoot"




