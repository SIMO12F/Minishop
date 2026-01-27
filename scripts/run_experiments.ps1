# SCRIPT_VERSION: 2026-01-24-MATRIX+METRICS-v4 (FIX selector wait)
# Run from repo root:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\scripts\run_experiments.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------- CONFIG ----------------
$Namespace      = "minishop"
$BaseManifest   = "k8s\minishop.yaml"
$AutoscalingDir = "k8s\autoscaling"

# Minimal experiment matrix
$Strategies = @("baseline","reactive","proactive","hybrid")
$QpsList    = @(10,30,60)
$Reps       = 3

# Target
$TargetUrl = "http://gateway-service:8081/api/products"
$HealthUrl = "http://gateway-service:8081/actuator/health"

# Fortio settings
$Connections      = 10
$WarmupSeconds    = 5
$DurationSeconds  = 30

# Metrics sampling
$SampleEverySeconds = 2

# Output root
$OutRoot = Join-Path (Resolve-Path ".").Path "results\exp_matrix_minikube_v1"

# ---------------- HELPERS ----------------
function Log([string]$msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$ts] $msg"
}

function Assert-Cmd([string]$cmd) {
    $null = Get-Command $cmd -ErrorAction Stop
}

function Ensure-Minikube-And-Metrics {
    Assert-Cmd "minikube"
    Assert-Cmd "kubectl"

    Log "Checking minikube status..."
    & minikube status | Out-Host

    Log "Ensuring metrics-server addon..."
    & minikube addons enable metrics-server | Out-Host
}

function Apply-Base {
    $full = (Resolve-Path $BaseManifest).Path
    Log "Applying base manifest: $full"
    Log "kubectl apply -f $full"
    & kubectl apply -f $full | Out-Host
}

function Wait-DeploymentsAvailable([int]$timeoutSec = 300) {
    Log "Waiting for deployments to be Available..."
    $timeout = "${timeoutSec}s"
    & kubectl -n $Namespace wait --for=condition=Available deploy --all --timeout=$timeout | Out-Host
}

function Wait-PodsReadyBySelector([string]$labelSelector, [int]$timeoutSec = 240) {
    Log "Waiting until pods are Ready for selector: $labelSelector"
    $timeout = "${timeoutSec}s"
    & kubectl -n $Namespace wait --for=condition=Ready pod -l $labelSelector --timeout=$timeout | Out-Host
}

function Check-Gateway-Health {
    Log "Checking gateway health (in-cluster): wget -S -O- $HealthUrl --timeout=3"
    & kubectl -n $Namespace run nettest --rm -i --restart=Never --image=busybox:1.36 -- `
        sh -c "wget -S -O- $HealthUrl --timeout=3" | Out-Host
}

function Reset-Autoscaling-All {
    if (-not (Test-Path $AutoscalingDir)) { return }
    $full = (Resolve-Path $AutoscalingDir).Path
    Log "kubectl delete -f $full (ignore-not-found)"
    & kubectl -n $Namespace delete -f $full --ignore-not-found | Out-Host
}

function Apply-Strategy([string]$strategy) {
    $dirFull  = (Resolve-Path $AutoscalingDir).Path
    $reactive = Join-Path $dirFull "reactive-hpa.yaml"
    $proactive = Join-Path $dirFull "proactive-cron.yaml"
    $hybrid   = Join-Path $dirFull "hybrid-cron.yaml"
    $rbacHpa  = Join-Path $dirFull "autoscaler-rbac-hpa.yaml"

    Log "=============================="
    Log "STRATEGY: $strategy"
    Log "=============================="

    # Always delete everything first so strategies don't mix
    Reset-Autoscaling-All

    switch ($strategy) {
        "baseline" {
            Log "Strategy=baseline -> no autoscaling resources applied."
        }
        "reactive" {
            Log "Applying reactive HPA: $reactive"
            & kubectl -n $Namespace apply -f $reactive | Out-Host
        }
        "proactive" {
            Log "Applying proactive cron scaling: $proactive"
            & kubectl -n $Namespace apply -f $proactive | Out-Host
        }
        "hybrid" {
            Log "Applying hybrid = reactive HPA + hybrid cron + RBAC for patching HPA"
            Log "Apply: $reactive"
            & kubectl -n $Namespace apply -f $reactive | Out-Host
            Log "Apply: $rbacHpa"
            & kubectl -n $Namespace apply -f $rbacHpa | Out-Host
            Log "Apply: $hybrid"
            & kubectl -n $Namespace apply -f $hybrid | Out-Host
        }
        default {
            throw "Unknown strategy: $strategy"
        }
    }

    Wait-DeploymentsAvailable 300
    Wait-PodsReadyBySelector "app=gateway-service" 240
    Check-Gateway-Health
}

function New-FortioPodName([string]$prefix="fortio") {
    $hex = -join ((48..57 + 97..102) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    return "$prefix-$hex"
}

function Wait-PodCompleted([string]$podName, [int]$timeoutSec = 600) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ($true) {
        $phase = & kubectl -n $Namespace get pod $podName -o jsonpath='{.status.phase}' 2>$null
        if ($phase -eq "Succeeded" -or $phase -eq "Failed") { return $phase }

        if ((Get-Date) -gt $deadline) {
            & kubectl -n $Namespace describe pod $podName | Out-Host
            throw "Timeout waiting for pod completion: $podName"
        }
        Start-Sleep -Seconds 1
    }
}

function Run-Fortio([int]$qps, [string]$phase, [int]$seconds, [string]$outFile) {
    $podName = New-FortioPodName "fortio"
    Log "Starting fortio pod: $podName | $phase | qps=$qps | t=${seconds}s | c=$Connections"

    & kubectl -n $Namespace run $podName `
        --image=fortio/fortio:1.63.0 `
        --restart=Never `
        --command -- fortio load -qps $qps -t "${seconds}s" -c $Connections $TargetUrl | Out-Null

    $phaseDone = Wait-PodCompleted $podName 600

    $dir = Split-Path -Parent $outFile
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    & kubectl -n $Namespace logs $podName | Out-File -Encoding utf8 $outFile
    Log "Saved: $outFile (pod phase: $phaseDone)"

    & kubectl -n $Namespace delete pod $podName --ignore-not-found | Out-Null
}

function Start-MetricsCollector([string]$runDir) {
    $metricsFile = Join-Path $runDir "metrics_pods.csv"
    $hpaFile     = Join-Path $runDir "hpa_status.txt"
    $stopFile    = Join-Path $runDir "_STOP.txt"

    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    if (Test-Path $stopFile) { Remove-Item $stopFile -Force }

    "timestamp,namespace,pod,cpu(m),memory(Mi)" | Out-File -Encoding utf8 $metricsFile
    "timestamp hpa_name min max current target" | Out-File -Encoding utf8 $hpaFile

    $job = Start-Job -ScriptBlock {
        param($ns, $metricsFile, $hpaFile, $stopFile, $sampleEvery)

        while (-not (Test-Path $stopFile)) {
            $ts = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")

            try {
                $lines = & kubectl -n $ns top pod --no-headers 2>$null
                foreach ($l in $lines) {
                    $parts = $l -split "\s+"
                    if ($parts.Length -ge 3) {
                        "$ts,$ns,$($parts[0]),$($parts[1].TrimEnd('m')),$($parts[2].TrimEnd('Mi'))" | Add-Content -Encoding utf8 $metricsFile
                    }
                }
            } catch { }

            try {
                $hpa = & kubectl -n $ns get hpa --no-headers 2>$null
                foreach ($h in $hpa) { "$ts $h" | Add-Content -Encoding utf8 $hpaFile }
            } catch { }

            Start-Sleep -Seconds $sampleEvery
        }
    } -ArgumentList $Namespace, $metricsFile, $hpaFile, $stopFile, $SampleEverySeconds

    return @{ Job=$job; StopFile=$stopFile }
}

function Stop-MetricsCollector($collector) {
    if ($null -eq $collector) { return }
    "stop" | Out-File -Encoding ascii $collector.StopFile
    Wait-Job $collector.Job | Out-Null
    Receive-Job $collector.Job | Out-Null
    Remove-Job $collector.Job | Out-Null
}

function Save-RunState([string]$runDir) {
    & kubectl -n $Namespace get pods -o wide    | Out-File -Encoding utf8 (Join-Path $runDir "state_pods.txt")
    & kubectl -n $Namespace get deploy -o wide  | Out-File -Encoding utf8 (Join-Path $runDir "state_deploy.txt")
    & kubectl -n $Namespace get svc -o wide     | Out-File -Encoding utf8 (Join-Path $runDir "state_svc.txt")
    & kubectl -n $Namespace get hpa -o wide     | Out-File -Encoding utf8 (Join-Path $runDir "state_hpa.txt") 2>$null
    & kubectl -n $Namespace get cronjob -o wide | Out-File -Encoding utf8 (Join-Path $runDir "state_cronjob.txt") 2>$null
}

function Save-Events([string]$runDir) {
    & kubectl -n $Namespace get events --sort-by=.metadata.creationTimestamp | Out-File -Encoding utf8 (Join-Path $runDir "events.txt")
}

function Parse-FortioSummary([string]$fortioLogPath) {
    $txt = Get-Content $fortioLogPath -ErrorAction Stop

    $p50 = ($txt | Select-String -Pattern "^# target 50%").Line
    $p90 = ($txt | Select-String -Pattern "^# target 90%").Line
    $p99 = ($txt | Select-String -Pattern "^# target 99%").Line
    $ended = ($txt | Select-String -Pattern "^Ended after .* : .* calls\. qps=").Line

    function LastNumber([string]$line) {
        if (-not $line) { return "" }
        $m = [regex]::Match($line, "([0-9]+(\.[0-9]+)?)\s*$")
        if ($m.Success) { return $m.Groups[1].Value }
        return ""
    }

    $aq = ""
    if ($ended) {
        $m2 = [regex]::Match($ended, "qps=([0-9]+(\.[0-9]+)?)")
        if ($m2.Success) { $aq = $m2.Groups[1].Value }
    }

    return @{ p50 = LastNumber $p50; p90 = LastNumber $p90; p99 = LastNumber $p99; actualQps = $aq }
}

# ---------------- MAIN ----------------
try {
    Log "SCRIPT_VERSION: 2026-01-24-MATRIX+METRICS-v4"
    Log "RepoRoot: $((Resolve-Path '.').Path)"
    Log "Namespace: $Namespace"
    Log "OutRoot: $OutRoot"

    Ensure-Minikube-And-Metrics
    Apply-Base
    Wait-DeploymentsAvailable 300
    Check-Gateway-Health

    Log "Strategies: $($Strategies -join ', ')"
    Log "QPS: $($QpsList -join ', ') | Reps: $Reps"

    New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

    $summaryCsv = Join-Path $OutRoot "summary.csv"
    "strategy,rep,qps,actual_qps,p50_s,p90_s,p99_s,run_dir" | Out-File -Encoding utf8 $summaryCsv

    foreach ($strategy in $Strategies) {
        Apply-Strategy $strategy

        for ($rep = 1; $rep -le $Reps; $rep++) {
            foreach ($qps in $QpsList) {
                $runDir = Join-Path $OutRoot (Join-Path $strategy (Join-Path ("rep$rep") ("qps$qps")))
                New-Item -ItemType Directory -Force -Path $runDir | Out-Null

                Log "---- Run: strategy=$strategy | rep=$rep | qps=$qps ----"
                Save-RunState $runDir

                $collector = Start-MetricsCollector $runDir

                Log "Warmup: ${WarmupSeconds}s at qps=$qps"
                Run-Fortio $qps "warmup" $WarmupSeconds (Join-Path $runDir "warmup.log")
                Run-Fortio $qps "fortio" $DurationSeconds (Join-Path $runDir "fortio.log")

                Stop-MetricsCollector $collector
                Save-Events $runDir
                Save-RunState $runDir

                $sum = Parse-FortioSummary (Join-Path $runDir "fortio.log")
                "$strategy,$rep,$qps,$($sum.actualQps),$($sum.p50),$($sum.p90),$($sum.p99),$runDir" | Add-Content -Encoding utf8 $summaryCsv

                Log "Completed: $runDir"
                Start-Sleep -Seconds 2
            }
        }
    }

    Log "Done. Summary: $summaryCsv"
}
catch {
    Log ("ERROR: " + $_.Exception.Message)
    throw
}







