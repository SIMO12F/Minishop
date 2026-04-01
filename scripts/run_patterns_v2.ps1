<#
run_patterns_v2.ps1
SCRIPT_VERSION: 2026-03-30-PATTERNS-v8.0

FIXES vs v7.5:
  1. CRITICAL: Reset all deployments to 1 replica between strategies AND reps
  2. CRITICAL: Proactive scaling via direct kubectl scale (not CronJob on clock)
  3. CRITICAL: Hybrid via direct HPA minReplicas patch (not CronJob on clock)
  4. CRITICAL: Added ?work=2 to generate real CPU load on ALL three services
  5. Added explicit wait-for-ready after every replica change
  6. Added verification logging of replica counts before each pattern

Run from repo root:
  Set-ExecutionPolicy -Scope Process Bypass -Force
  .\scripts\run_patterns_v2.ps1
#>

$ErrorActionPreference = "Stop"

$SCRIPT_VERSION = "2026-03-30-PATTERNS-v8.0 (reset+direct-scale+cpu-work)"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Namespace = "minishop"

$OutRoot = Join-Path $RepoRoot "results\exp_patterns_minikube_v6"
$BaseManifest = Join-Path $RepoRoot "k8s\minishop.yaml"
$AutoscalingDir = Join-Path $RepoRoot "k8s\autoscaling"
$HealthUrl = "http://gateway-service:8081/actuator/health"

# FIX #4: Add CPU work parameter so HPA actually triggers on all services
# work=2 means each service burns 2ms of CPU per request
# Gateway calls burnCpuMs 3x per /api/summary -> 6ms CPU per request at gateway
# At 10 QPS: gateway ~60m CPU (at threshold), downstream ~20m (idle)
# At 30 QPS: gateway ~180m CPU (scales), downstream ~60m (at threshold)
# At 60 QPS: gateway ~360m CPU (max scale), downstream ~120m (scales)
$TargetUrl = "http://gateway-service:8081/api/summary?work=2"

$Concurrency = 10
$WarmupSeconds = 10

# ============================
# RUN CONFIG
# ============================
$Reps = 3
$PatternsToRun = @("spike", "daynight")
$StrategiesToRun = @("hybrid")

# Proactive/hybrid target replica counts
$ProactiveGatewayReplicas = 4
$ProactiveOrderReplicas   = 3
$ProactiveProductReplicas = 3
$HybridMinGateway = 3
$HybridMinOrder   = 2
$HybridMinProduct = 2

# pick ONE kubectl.exe
$kubectlCandidates = @(Get-Command kubectl -All -CommandType Application -ErrorAction Stop)
$preferred = $kubectlCandidates | Where-Object { $_.Source -match "WinGet\\Links\\kubectl\.exe" } | Select-Object -First 1
if (-not $preferred) {
    $preferred = $kubectlCandidates | Where-Object { $_.Source -match "Docker\\Docker\\resources\\bin\\kubectl\.exe" } | Select-Object -First 1
}
if (-not $preferred) { $preferred = $kubectlCandidates | Select-Object -First 1 }
$KubectlCmd = $preferred.Source

# ============================
# HELPERS
# ============================

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
    if ($LASTEXITCODE -ne 0) {
        throw "minikube is not running. Run: minikube start"
    }
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
        Log "  Waiting rollout: deployment/$dep"
        & $KubectlCmd -n $ns rollout status deployment/$dep --timeout=600s
        if ($LASTEXITCODE -ne 0) {
            throw "Rollout failed for deployment/$dep"
        }
    }
}

function Wait-PodsReady([string]$ns, [string]$selector) {
    Log "  Waiting pods Ready: $selector"
    & $KubectlCmd -n $ns wait pod -l $selector --for=condition=Ready --timeout=600s
    if ($LASTEXITCODE -ne 0) {
        throw "Pods not Ready for: $selector"
    }
}

function Check-GatewayHealth([string]$ns) {
    Log "Checking gateway health: $HealthUrl"
    & $KubectlCmd -n $ns run nettest --rm --stdin=true --restart=Never --image=busybox:1.36 -- `
        wget -q -O- $HealthUrl | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Gateway health check failed"
    }
}

function Cleanup-Autoscaling([string]$ns) {
    if (Test-Path $AutoscalingDir) {
        Log "Deleting autoscaling resources..."
        try { Invoke-Kubectl "-n" $ns "delete" "-f" $AutoscalingDir "--ignore-not-found" | Out-Null } catch {}
    }
}

# ============================
# FIX #1: RESET REPLICAS
# ============================
function Reset-AllReplicas([string]$ns) {
    Log "RESETTING all deployments to 1 replica..."

    # Delete any active HPA first — otherwise HPA immediately scales back up
    try { Invoke-Kubectl "-n" $ns "delete" "hpa" "--all" "--ignore-not-found" | Out-Null } catch {}
    Start-Sleep -Seconds 2

    Invoke-Kubectl "-n" $ns "scale" "deployment" "gateway-service"  "--replicas=1" | Out-Null
    Invoke-Kubectl "-n" $ns "scale" "deployment" "order-service"    "--replicas=1" | Out-Null
    Invoke-Kubectl "-n" $ns "scale" "deployment" "product-service"  "--replicas=1" | Out-Null

    # Wait for rollout (handles termination of excess pods)
    Wait-Rollout $ns

    # Wait for terminating pods to fully disappear before checking readiness
    Log "  Waiting for old pods to terminate..."
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        $gw = (Invoke-Kubectl "-n" $ns "get" "deploy" "gateway-service" "-o" "jsonpath={.status.readyReplicas}") 2>$null
        $ord = (Invoke-Kubectl "-n" $ns "get" "deploy" "order-service" "-o" "jsonpath={.status.readyReplicas}") 2>$null
        $prod = (Invoke-Kubectl "-n" $ns "get" "deploy" "product-service" "-o" "jsonpath={.status.readyReplicas}") 2>$null
        if ($gw -eq "1" -and $ord -eq "1" -and $prod -eq "1") {
            # Also check no extra pods exist
            $podCount = (Invoke-Kubectl "-n" $ns "get" "pods" "-l" "app=gateway-service" "--no-headers" 2>$null | Measure-Object -Line).Lines
            if ($podCount -le 1) { break }
        }
        Start-Sleep -Seconds 3
    }

    Log "Replica counts after reset:"
    Invoke-Kubectl "-n" $ns "get" "deploy" "--no-headers" | ForEach-Object { Log "  $_" }

    Start-Sleep -Seconds 5
}

# ============================
# FIX #2: PROACTIVE DIRECT SCALE
# ============================
function Proactive-ScaleUp([string]$ns) {
    Log "PROACTIVE: Scaling up to target replicas..."
    Invoke-Kubectl "-n" $ns "scale" "deployment" "gateway-service"  "--replicas=$ProactiveGatewayReplicas" | Out-Null
    Invoke-Kubectl "-n" $ns "scale" "deployment" "order-service"    "--replicas=$ProactiveOrderReplicas"   | Out-Null
    Invoke-Kubectl "-n" $ns "scale" "deployment" "product-service"  "--replicas=$ProactiveProductReplicas" | Out-Null

    Wait-Rollout $ns
    Wait-PodsReady $ns "app=gateway-service"
    Wait-PodsReady $ns "app=order-service"
    Wait-PodsReady $ns "app=product-service"

    Log "Proactive scale-up complete. Replica counts:"
    Invoke-Kubectl "-n" $ns "get" "deploy" "--no-headers" | ForEach-Object { Log "  $_" }
}

function Proactive-ScaleDown([string]$ns) {
    Log "PROACTIVE: Scaling down to 1 replica..."
    Invoke-Kubectl "-n" $ns "scale" "deployment" "gateway-service"  "--replicas=1" | Out-Null
    Invoke-Kubectl "-n" $ns "scale" "deployment" "order-service"    "--replicas=1" | Out-Null
    Invoke-Kubectl "-n" $ns "scale" "deployment" "product-service"  "--replicas=1" | Out-Null
    # Don't wait for rollout here - let scale-down happen during low_2/night_2
}

# ============================
# FIX #3: HYBRID DIRECT PATCH
# ============================
function Hybrid-SetMinHigh([string]$ns) {
    Log "HYBRID: Patching HPA minReplicas to high floor..."

    # Write JSON to temp files to bypass PowerShell escaping entirely
    $gwFile  = [System.IO.Path]::GetTempFileName()
    $ordFile = [System.IO.Path]::GetTempFileName()
    $prdFile = [System.IO.Path]::GetTempFileName()

    Set-Content -Path $gwFile  -Value ('{"spec":{"minReplicas":' + $HybridMinGateway + '}}') -NoNewline
    Set-Content -Path $ordFile -Value ('{"spec":{"minReplicas":' + $HybridMinOrder   + '}}') -NoNewline
    Set-Content -Path $prdFile -Value ('{"spec":{"minReplicas":' + $HybridMinProduct + '}}') -NoNewline

    Invoke-Kubectl "-n" $ns "patch" "hpa" "gateway-hpa" "--type=merge" "--patch-file=$gwFile"  | Out-Null
    Invoke-Kubectl "-n" $ns "patch" "hpa" "order-hpa"   "--type=merge" "--patch-file=$ordFile" | Out-Null
    Invoke-Kubectl "-n" $ns "patch" "hpa" "product-hpa" "--type=merge" "--patch-file=$prdFile" | Out-Null

    Remove-Item $gwFile, $ordFile, $prdFile -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 5
    Wait-Rollout $ns
    Wait-PodsReady $ns "app=gateway-service"
    Wait-PodsReady $ns "app=order-service"
    Wait-PodsReady $ns "app=product-service"

    Log "Hybrid floor set. Current state:"
    Invoke-Kubectl "-n" $ns "get" "hpa" "--no-headers" | ForEach-Object { Log "  $_" }
}

function Hybrid-SetMinLow([string]$ns) {
    Log "HYBRID: Patching HPA minReplicas back to 1..."

    $tmpFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmpFile -Value '{"spec":{"minReplicas":1}}' -NoNewline

    Invoke-Kubectl "-n" $ns "patch" "hpa" "gateway-hpa" "--type=merge" "--patch-file=$tmpFile" | Out-Null
    Invoke-Kubectl "-n" $ns "patch" "hpa" "order-hpa"   "--type=merge" "--patch-file=$tmpFile" | Out-Null
    Invoke-Kubectl "-n" $ns "patch" "hpa" "product-hpa" "--type=merge" "--patch-file=$tmpFile" | Out-Null

    Remove-Item $tmpFile -ErrorAction SilentlyContinue
}

# ============================
# APPLY STRATEGY
# ============================
function Apply-Strategy([string]$ns, [string]$strategy) {
    Cleanup-Autoscaling $ns

    # FIX #1: Always reset replicas to 1 before applying new strategy
    Reset-AllReplicas $ns

    $rbacHpa     = Join-Path $AutoscalingDir "autoscaler-rbac-hpa.yaml"
    $reactiveHpa = Join-Path $AutoscalingDir "reactive-hpa.yaml"

    switch ($strategy) {
        "baseline" {
            Log "Strategy=baseline -> no autoscaling, 1 replica each."
        }
        "reactive" {
            Log "Strategy=reactive -> applying HPA only."
            Invoke-Kubectl "-n" $ns "apply" "-f" $reactiveHpa | Out-Null
        }
        "proactive" {
            Log "Strategy=proactive -> no autoscaling resources applied."
            Log "  (Script will trigger scale-up directly before each pattern)"
        }
        "hybrid" {
            Log "Strategy=hybrid -> applying HPA (script will patch minReplicas)."
            Invoke-Kubectl "-n" $ns "apply" "-f" $rbacHpa     | Out-Null
            Invoke-Kubectl "-n" $ns "apply" "-f" $reactiveHpa | Out-Null
        }
        default { throw "Unknown strategy: $strategy" }
    }

    Start-Sleep -Seconds 3

    Log "Verified state after applying $strategy :"
    Invoke-Kubectl "-n" $ns "get" "deploy" "--no-headers" | ForEach-Object { Log "  $_" }
    try { Invoke-Kubectl "-n" $ns "get" "hpa" "--no-headers" | ForEach-Object { Log "  $_" } } catch {}

    Wait-PodsReady $ns "app=gateway-service"
    Check-GatewayHealth $ns
}

# ============================
# FORTIO HELPERS
# ============================
function Sanitize-K8sName([string]$s) {
    $x = $s.ToLower() -replace "_", "-" -replace "[^a-z0-9\-\.]", "-"
    return $x.Trim("-")
}

function New-FortioPodName([string]$segmentName) {
    $rand = -join ((48..57) + (97..102) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    return ("fortio-{0}-{1}" -f (Sanitize-K8sName $segmentName), $rand)
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
    throw "Timeout waiting pod: $podName"
}

function Save-Snapshot([string]$ns, [string]$outDir, [string]$label) {
    $snapDir = Join-Path $outDir "metrics"
    Ensure-Dir $snapDir
    $prefix = Join-Path $snapDir $label

    try { Invoke-Kubectl "-n" $ns "get" "pods" "-o" "wide"    | Out-File -Encoding utf8 "$prefix.pods.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "get" "deploy" "-o" "wide"  | Out-File -Encoding utf8 "$prefix.deploy.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "get" "hpa" "-o" "wide"     | Out-File -Encoding utf8 "$prefix.hpa.txt" } catch {}
    try { Invoke-Kubectl "-n" $ns "top" "pods"                | Out-File -Encoding utf8 "$prefix.top_pods.txt" } catch {}
    try { Invoke-Kubectl "top" "nodes"                        | Out-File -Encoding utf8 "$prefix.top_nodes.txt" } catch {}
}

function Save-RunMetadata([string]$outDir, [string]$strategy, [string]$pattern, [int]$rep) {
    $metaFile = Join-Path $outDir "run_metadata.txt"
    @(
        "SCRIPT_VERSION=$SCRIPT_VERSION",
        "TIMESTAMP=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "STRATEGY=$strategy",
        "PATTERN=$pattern",
        "REPETITION=$rep",
        "TARGET_URL=$TargetUrl",
        "HEALTH_URL=$HealthUrl",
        "CONCURRENCY=$Concurrency",
        "WARMUP_SECONDS=$WarmupSeconds",
        "WORK_MS=2",
        "CPU_REQUEST=100m",
        "CPU_LIMIT=500m"
    ) | Out-File -Encoding utf8 $metaFile

    try { "MINIKUBE_VERSION=$(& minikube version)"                          | Out-File -Append -Encoding utf8 $metaFile } catch {}
    try { "KUBECTL_VERSION=$(& $KubectlCmd version --client -o yaml)"       | Out-File -Append -Encoding utf8 $metaFile } catch {}
    try { "K8S_CONTEXT=$(& $KubectlCmd config current-context)"             | Out-File -Append -Encoding utf8 $metaFile } catch {}
    try { "DOCKER_VERSION=$(docker version --format '{{.Client.Version}}')" | Out-File -Append -Encoding utf8 $metaFile } catch {}

    try { Invoke-Kubectl "-n" $Namespace "get" "deploy" "-o" "yaml" | Out-File -Encoding utf8 (Join-Path $outDir "deployments.yaml") } catch {}
    try { Invoke-Kubectl "-n" $Namespace "get" "hpa"    "-o" "yaml" | Out-File -Encoding utf8 (Join-Path $outDir "hpa.yaml")         } catch {}
}

function Run-FortioSegment {
    param(
        [string]$ns, [string]$outDir, [string]$segmentName,
        [int]$qps, [int]$durationSec, [int]$concurrency, [string]$url
    )

    $maxAttempts = 3
    $succeeded = $false

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {

        $suffix = if ($attempt -eq 1) { "" } else { "_attempt$attempt" }
        $podName = New-FortioPodName "$segmentName$suffix"
        Log "  Fortio: $segmentName | qps=$qps | t=${durationSec}s | c=$concurrency (attempt $attempt/$maxAttempts)"

        # Exact same args as original v7.5 that completed baseline successfully
        $fArgs = @(
            "-n", $ns, "run", $podName,
            "--restart=Never",
            "--image=fortio/fortio:1.63.0",
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
        Invoke-Kubectl @fArgs | Out-Null

        Wait-PodExists $ns $podName 60
        if ($attempt -eq 1) {
            Save-Snapshot $ns $outDir "segment_${segmentName}_start"
        }

        $phase = Wait-PodFinished $ns $podName 900
        Log "  Fortio done: $segmentName (phase=$phase)"

        # Save results
        $jsonFile = Join-Path $outDir "fortio_${segmentName}${suffix}.json"
        Invoke-Kubectl "-n" $ns "logs" $podName "--all-containers=true" | Out-File -Encoding utf8 $jsonFile

        if ($attempt -eq 1) {
            $descFile = Join-Path $outDir "fortio_${segmentName}.describe.txt"
            try { Invoke-Kubectl "-n" $ns "describe" "pod" $podName | Out-File -Encoding utf8 $descFile } catch {}
        }

        Save-Snapshot $ns $outDir "segment_${segmentName}_end"
        try { Invoke-Kubectl "-n" $ns "delete" "pod" $podName "--ignore-not-found" | Out-Null } catch {}

        if ($phase -eq "Succeeded") {
            if ($attempt -gt 1) {
                $canonicalJson = Join-Path $outDir "fortio_${segmentName}.json"
                Copy-Item $jsonFile $canonicalJson -Force
            }
            $succeeded = $true
            break
        }

        Log "  Attempt $attempt failed. Waiting 10s before retry..."
        Start-Sleep -Seconds 10
    }

    if (-not $succeeded) {
        throw "Fortio failed after $maxAttempts attempts: $segmentName"
    }
}

function Get-PatternSegments([string]$pattern) {
    switch ($pattern) {
        "spike" {
            return @(
                [PSCustomObject]@{ Name="low_1"; Qps=10; DurationSec=60 },
                [PSCustomObject]@{ Name="spike"; Qps=60; DurationSec=30 },
                [PSCustomObject]@{ Name="low_2"; Qps=10; DurationSec=60 }
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

function Get-HighLoadSegment([string]$pattern) {
    switch ($pattern) {
        "spike"    { return "spike" }
        "daynight" { return "day" }
        default    { throw "Unknown pattern: $pattern" }
    }
}

# ============================
# MAIN
# ============================

Log "============================================"
Log "SCRIPT_VERSION: $SCRIPT_VERSION"
Log "RepoRoot: $RepoRoot"
Log "Namespace: $Namespace"
Log "OutRoot: $OutRoot"
Log "TargetUrl: $TargetUrl"
Log "Using kubectl: $KubectlCmd"
Log "============================================"

Ensure-Dir $OutRoot

Check-Minikube
Ensure-MetricsServer
Apply-BaseManifest
Wait-Rollout $Namespace
Wait-PodsReady $Namespace "app=gateway-service"
Check-GatewayHealth $Namespace

Log "Strategies: $($StrategiesToRun -join ', ')"
Log "Patterns: $($PatternsToRun -join ', ') | Reps: $Reps"

foreach ($strategy in $StrategiesToRun) {

    Log ""
    Log "######################################################"
    Log "# STRATEGY: $strategy"
    Log "######################################################"

    Apply-Strategy $Namespace $strategy

    foreach ($pattern in $PatternsToRun) {
        $segments = Get-PatternSegments $pattern
        $highSeg = Get-HighLoadSegment $pattern

        for ($rep = 1; $rep -le $Reps; $rep++) {

            Log ""
            Log "=========================================="
            Log "PATTERN=$pattern | STRATEGY=$strategy | REP=$rep"
            Log "=========================================="

            # FIX #1: Reset replicas to 1 before EVERY rep
            if ($strategy -ne "baseline") {
                Log "Resetting replicas to 1 before rep $rep..."
                Reset-AllReplicas $Namespace

                # Re-apply HPA (Reset deletes it to prevent scale-up fight)
                if ($strategy -eq "reactive" -or $strategy -eq "hybrid") {
                    $reactiveHpa = Join-Path $AutoscalingDir "reactive-hpa.yaml"
                    Log "Re-applying HPA after reset..."
                    Invoke-Kubectl "-n" $Namespace "apply" "-f" $reactiveHpa | Out-Null
                    Start-Sleep -Seconds 5
                }
            }

            $repDir = Join-Path $OutRoot (Join-Path $pattern (Join-Path $strategy ("rep{0}" -f $rep)))
            Ensure-Dir $repDir
            Save-RunMetadata -outDir $repDir -strategy $strategy -pattern $pattern -rep $rep

            # FIX #5: Log verified replica state before pattern starts
            Log "Replica state before pattern:"
            Invoke-Kubectl "-n" $Namespace "get" "deploy" "--no-headers" | ForEach-Object { Log "  $_" }

            # ---- WARMUP ----
            Log "Warmup: qps=10, t=${WarmupSeconds}s"
            Run-FortioSegment -ns $Namespace -outDir $repDir -segmentName "warmup" `
                -qps 10 -durationSec $WarmupSeconds -concurrency $Concurrency -url $TargetUrl
            Start-Sleep -Seconds 2

            # ---- FIX #2/#3: PRE-SCALE for proactive/hybrid BEFORE high-load segment ----
            if ($strategy -eq "proactive") {
                Log "PROACTIVE: Pre-scaling before pattern..."
                Proactive-ScaleUp $Namespace
                Log "Letting pre-scaled pods settle for 10s..."
                Start-Sleep -Seconds 10
            }
            elseif ($strategy -eq "hybrid") {
                Log "HYBRID: Setting HPA floor before pattern..."
                Hybrid-SetMinHigh $Namespace
                Log "Letting hybrid floor settle for 10s..."
                Start-Sleep -Seconds 10
            }

            # ---- RUN PATTERN SEGMENTS ----
            foreach ($s in $segments) {
                Run-FortioSegment -ns $Namespace -outDir $repDir -segmentName $s.Name `
                    -qps $s.Qps -durationSec $s.DurationSec -concurrency $Concurrency -url $TargetUrl

                # After the high-load segment ends, trigger scale-down for proactive/hybrid
                if ($s.Name -eq $highSeg) {
                    if ($strategy -eq "proactive") {
                        Log "PROACTIVE: Triggering scale-down after $highSeg segment..."
                        Proactive-ScaleDown $Namespace
                    }
                    elseif ($strategy -eq "hybrid") {
                        Log "HYBRID: Lowering HPA floor after $highSeg segment..."
                        Hybrid-SetMinLow $Namespace
                    }
                }

                Start-Sleep -Seconds 2
            }

            # ---- FINAL SNAPSHOT ----
            Save-Snapshot $Namespace $repDir "final"
            Log "Completed: $repDir"
            Log "Final replica state:"
            Invoke-Kubectl "-n" $Namespace "get" "deploy" "--no-headers" | ForEach-Object { Log "  $_" }
        }
    }

    # Cleanup before next strategy
    Cleanup-Autoscaling $Namespace
}

# Final reset
Reset-AllReplicas $Namespace

Log ""
Log "============================================"
Log "ALL DONE. Results: $OutRoot"
Log "============================================"