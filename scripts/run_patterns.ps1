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
$HealthUrl = "http://gateway-service:8081/actuator/health"
$TargetUrl = "http://gateway-service:8081/api/summary"

$Concurrency = 10
$WarmupSeconds = 10

# ============================
# RUN CONFIG (YOU REQUESTED)
# ============================
$Reps = 5
$PatternsToRun = @("daynight")
$StrategiesToRun = @("baseline", "reactive", "proactive", "hybrid")

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
    $out = & minikube status 2>&1
    $exitCode = $LASTEXITCODE

    if ($out) { $out | ForEach-Object { Write-Host $_ } }

    if ($exitCode -ne 0) {
        throw "minikube is not running or the profile is broken. Run: minikube start"
    }
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
        & $KubectlCmd -n $ns rollout status deployment/$dep --timeout=180s
        if ($LASTEXITCODE -ne 0) {
            throw "Rollout failed for deployment/$dep"
        }
    }
}

function Wait-PodsReady([string]$ns, [string]$selector) {
    Log "Waiting pods Ready for selector: $selector"
    & $KubectlCmd -n $ns wait pod -l $selector --for=condition=Ready --timeout=180s
    if ($LASTEXITCODE -ne 0) {
        throw "Pods did not become Ready for selector: $selector"
    }
}


function Check-GatewayHealth([string]$ns) {
    Log "Checking gateway health (in-cluster): $HealthUrl"
    & $KubectlCmd -n $ns run nettest --rm --stdin=true --restart=Never --image=busybox:1.36 -- `
        wget -q -O- $HealthUrl | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Gateway health check failed: $HealthUrl"
    }
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
function Save-RunMetadata([string]$outDir, [string]$strategy, [string]$pattern, [int]$rep) {
    $metaFile = Join-Path $outDir "run_metadata.txt"

    "SCRIPT_VERSION=$SCRIPT_VERSION" | Out-File -Encoding utf8 $metaFile
    "TIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -Append -Encoding utf8 $metaFile
    "STRATEGY=$strategy" | Out-File -Append -Encoding utf8 $metaFile
    "PATTERN=$pattern" | Out-File -Append -Encoding utf8 $metaFile
    "REPETITION=$rep" | Out-File -Append -Encoding utf8 $metaFile
    "TARGET_URL=$TargetUrl" | Out-File -Append -Encoding utf8 $metaFile
    "HEALTH_URL=$HealthUrl" | Out-File -Append -Encoding utf8 $metaFile
    "CONCURRENCY=$Concurrency" | Out-File -Append -Encoding utf8 $metaFile
    "WARMUP_SECONDS=$WarmupSeconds" | Out-File -Append -Encoding utf8 $metaFile

    try { "MINIKUBE_VERSION=$(& minikube version)" | Out-File -Append -Encoding utf8 $metaFile } catch {}
    try { "KUBECTL_VERSION=$(& $KubectlCmd version --client -o yaml)" | Out-File -Append -Encoding utf8 $metaFile } catch {}
    try { "K8S_CONTEXT=$(& $KubectlCmd config current-context)" | Out-File -Append -Encoding utf8 $metaFile } catch {}
    try { "DOCKER_VERSION=$(docker version --format '{{.Client.Version}} / {{.Server.Version}}')" | Out-File -Append -Encoding utf8 $metaFile } catch {}

    try { Invoke-Kubectl "-n" $Namespace "get" "deploy" "-o" "yaml" | Out-File -Encoding utf8 (Join-Path $outDir "deployments.yaml") } catch {}
    try { Invoke-Kubectl "-n" $Namespace "get" "hpa" "-o" "yaml" | Out-File -Encoding utf8 (Join-Path $outDir "hpa.yaml") } catch {}
    try { Invoke-Kubectl "-n" $Namespace "get" "cronjob" "-o" "yaml" | Out-File -Encoding utf8 (Join-Path $outDir "cronjobs.yaml") } catch {}
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

    function Invoke-FortioOnce([string]$podName, [string]$jsonSuffix) {
        Log "Starting fortio pod: $podName | $segmentName | qps=$qps | t=${durationSec}s | c=$concurrency"

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
        Save-Snapshot $ns $outDir ("segment_{0}_start{1}" -f $segmentName, $jsonSuffix)

        $phase = Wait-PodFinished $ns $podName 900
        Log "Fortio finished: $podName (phase=$phase)"

        $jsonFile = Join-Path $outDir ("fortio_{0}{1}.json" -f $segmentName, $jsonSuffix)
        Invoke-Kubectl "-n" $ns "logs" $podName "--all-containers=true" | Out-File -Encoding utf8 $jsonFile

        $descFile = Join-Path $outDir ("fortio_{0}{1}.describe.txt" -f $segmentName, $jsonSuffix)
        try { Invoke-Kubectl "-n" $ns "describe" "pod" $podName | Out-File -Encoding utf8 $descFile } catch {}

        Save-Snapshot $ns $outDir ("segment_{0}_end{1}" -f $segmentName, $jsonSuffix)

        try { Invoke-Kubectl "-n" $ns "delete" "pod" $podName "--ignore-not-found" | Out-Null } catch {}

        return $phase
    }

    $podName = New-FortioPodName $segmentName
    $phase = Invoke-FortioOnce -podName $podName -jsonSuffix ""

    if ($phase -eq "Succeeded") {
        return
    }

    if ($segmentName -eq "warmup") {
        Log "Warmup failed once; waiting 5 seconds and retrying..."
        Start-Sleep -Seconds 5

        $retryPodName = New-FortioPodName ($segmentName + "-retry")
        $retryPhase = Invoke-FortioOnce -podName $retryPodName -jsonSuffix "_retry"

        if ($retryPhase -ne "Succeeded") {
            throw "Warmup failed twice (initial + retry)."
        }

        return
    }

    throw "Fortio segment failed: $segmentName (phase=$phase)"
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
    Save-Snapshot $Namespace $OutRoot ("strategy_{0}_applied" -f $strategy)
    Log "Settling after strategy application..."
    Start-Sleep -Seconds 10

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
            Save-RunMetadata -outDir $repDir -strategy $strategy -pattern $pattern -rep $rep

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




