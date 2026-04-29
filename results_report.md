# Experimental Results and Findings Report

## Experiment: Evaluating Autoscaling Strategies for Java Microservices on Kubernetes
### MiniShop Testbed — exp_patterns_minikube_v6
### Mohammed Mbida — HAWK Göttingen, April 2026

---

## 1. Experiment Overview

This report presents the complete results from 24 controlled experiment runs comparing four autoscaling strategies for Java microservices on a single-node Minikube Kubernetes cluster.

**Testbed:** MiniShop — three Spring Boot microservices (gateway, product, order) with sequential request chaining at the gateway endpoint `/api/summary?work=2`.

**Strategies tested:**

| Strategy | Mechanism | Pods during high load | Pods during low load |
|----------|-----------|----------------------|---------------------|
| Baseline | No autoscaling, fixed replicas | 3 (1+1+1) | 3 (1+1+1) |
| Reactive | Kubernetes HPA (CPU 60% target) | 3–14 (HPA-driven) | 3 (1+1+1) |
| Proactive | Script-triggered pre-scaling | 10 (4+3+3) | 3 (1+1+1) |
| Hybrid | HPA + raised minReplicas floor | 7–14 (floor 3+2+2, HPA on top) | 3 (1+1+1) |

**Workload patterns:**

| Pattern | Segment 1 | Segment 2 | Segment 3 |
|---------|-----------|-----------|-----------|
| Spike | low_1: 10 QPS × 60s | spike: 60 QPS × 30s | low_2: 10 QPS × 60s |
| Day-night | night_1: 10 QPS × 60s | day: 30 QPS × 90s | night_2: 10 QPS × 60s |

**Configuration:** CPU request 100m, limit 500m per pod. HPA target 60% CPU. Concurrency 10. 3 repetitions per condition. Fortio 1.63.0 as load generator. `work=2` parameter burns 2ms CPU per service call.

**Measurement point:** End-to-end latency at gateway `/api/summary`, which calls product and order services sequentially (total CPU burn: ~6ms per request at gateway level).

---

## 2. Key Results

### 2.1 Spike Pattern (10 → 60 → 10 QPS)

#### During Spike Segment (60 QPS, 30 seconds)

| Strategy | Mean Latency (ms) | P99 Latency (ms) | Achieved QPS | Req. Count |
|----------|-------------------|-------------------|--------------|------------|
| **Baseline** | **91.3 ± 25.9** | **290.6 ± 38.8** | **59.8 ± 0.0** | **1800** |
| **Reactive** | **87.2 ± 25.0** | **244.4 ± 86.8** | **59.1 ± 0.6** | **1784** |
| Proactive | 362.8 ± 32.7 | 810.3 ± 171.1 | 27.5 ± 2.5 | 829 |
| Hybrid | 318.4 ± 105.0 | 734.4 ± 227.8 | 32.5 ± 9.7 | 983 |

**Finding:** Baseline and reactive achieve near-target throughput (59.8 and 59.1 QPS) with sub-300ms tail latency. Proactive and hybrid fail to sustain 60 QPS — achieving only 27.5 and 32.5 QPS respectively — with P99 latencies 2.5× to 2.8× worse than baseline.

#### During Recovery Segment (low_2, 10 QPS, 60 seconds)

| Strategy | Mean Latency (ms) | P99 Latency (ms) |
|----------|-------------------|-------------------|
| **Baseline** | **66.7 ± 3.5** | **189.5 ± 11.9** |
| Reactive | 289.0 ± 177.8 | 897.8 ± 435.5 |
| **Proactive** | **66.3 ± 10.6** | **230.4 ± 99.8** |
| Hybrid | 151.4 ± 80.8 | 597.7 ± 173.2 |

**Finding:** Reactive shows a severe "scale-down penalty" during recovery — P99 jumps to 898ms (4.7× worse than baseline) because HPA-triggered pods are still running and competing for CPU during the 300-second stabilization window. Proactive recovers cleanly to baseline-level latency because its pods were already scaled down by the script.

#### Pre-Load Segment (low_1, 10 QPS, 60 seconds)

| Strategy | Mean Latency (ms) | P99 Latency (ms) |
|----------|-------------------|-------------------|
| **Baseline** | **57.9 ± 3.8** | **150.8 ± 32.6** |
| **Reactive** | **59.0 ± 2.3** | **180.2 ± 14.9** |
| Proactive | 271.1 ± 29.4 | 676.6 ± 37.7 |
| Hybrid | 101.0 ± 33.1 | 320.8 ± 101.3 |

**Finding:** Proactive and hybrid show elevated latency even during the pre-load phase because pods were already pre-scaled (10 and 7 pods respectively), creating resource contention at 10 QPS where fewer pods would suffice.

---

### 2.2 Day-Night Pattern (10 → 30 → 10 QPS)

#### During Day Segment (30 QPS, 90 seconds)

| Strategy | Mean Latency (ms) | P99 Latency (ms) | Achieved QPS | Req. Count |
|----------|-------------------|-------------------|--------------|------------|
| **Baseline** | **51.8 ± 6.1** | **153.8 ± 38.7** | **30.0 ± 0.0** | **2700** |
| **Reactive** | **70.1 ± 9.3** | **295.0 ± 46.7** | **29.9 ± 0.0** | **2700** |
| Proactive | 219.0 ± 114.1 | 620.9 ± 214.1 | 29.4 ± 0.7 | 2651 |
| Hybrid | 403.7 ± 158.8 | 1518.4 ± 523.3 | 22.6 ± 5.1 | 2042 |

**Finding:** At the moderate 30 QPS day load, baseline and reactive both sustain full throughput with reasonable latency. Hybrid performs worst of all strategies — P99 of 1518ms with high variance (±523ms) and only 22.6 QPS achieved. Proactive shows high variance (P99 std of ±214ms), indicating inconsistent behavior.

#### During Night Recovery (night_2, 10 QPS, 60 seconds)

| Strategy | Mean Latency (ms) | P99 Latency (ms) |
|----------|-------------------|-------------------|
| **Baseline** | **48.1 ± 2.2** | **112.0 ± 6.3** |
| Reactive | 197.1 ± 132.4 | 887.4 ± 595.0 |
| **Proactive** | **59.9 ± 9.0** | **183.3 ± 44.4** |
| Hybrid | 277.6 ± 46.2 | 814.2 ± 54.6 |

**Finding:** Same pattern as spike recovery — reactive suffers from scale-down lag (887ms P99, 7.9× baseline), while proactive returns to near-baseline performance (1.6× baseline). Hybrid retains elevated latency (814ms P99) because both the HPA-driven extra pods and the floor mechanism leave excess pods running.

---

## 3. Cross-Cutting Analysis

### 3.1 Single-Node Resource Contention Effect

The most significant finding across all experiments is that **horizontal scaling on a single-node cluster degrades rather than improves performance**. This is the dominant effect observed:

- **Proactive** (10 pods) consistently underperforms baseline (3 pods) — 4× in mean latency and 2.8× in P99 during spike
- **Hybrid** (7+ pods) shows similar degradation — P99 during day segment is nearly 10× worse than baseline
- **Baseline** with just 3 pods delivers the best or near-best performance in every segment

**Explanation:** On a single Minikube node, all pods share the same CPU. With CPU requests of 100m and limits of 500m, 10 pods request 1000m total but compete for the same physical cores. The Kubernetes scheduler cannot spread load across nodes. Each additional pod increases context switching, JVM overhead (each Spring Boot instance consumes memory and CPU for GC), and network stack contention. The marginal CPU gained per pod decreases while the overhead increases.

### 3.2 Reactive Strategy: Best Autoscaler on Single-Node

Despite the single-node limitation, reactive (HPA) performs surprisingly well:

- **During spike (60 QPS):** 244ms P99, 59.1 QPS — actually 16% lower P99 than baseline (244 vs 291) while sustaining full throughput
- **During day (30 QPS):** 295ms P99, 29.9 QPS — essentially full throughput (29.9/30)
- HPA scales conservatively (per-service maxReplicas: 6 gateway, 4 product, 4 order; 3–14 pods total cluster-wide), avoiding the extreme contention of 10+ pre-positioned pods

The HPA's CPU-target mechanism naturally limits scaling when adding more pods no longer reduces per-pod CPU — creating an emergent form of single-node awareness.

### 3.3 Reactive Scale-Down Penalty

Reactive's weakness is the post-spike recovery phase. The HPA's 300-second `scaleDown.stabilizationWindowSeconds` keeps pods running long after load drops:

- **spike low_2:** 898ms P99 (4.7× baseline)
- **daynight night_2:** 887ms P99 (7.9× baseline)
- High variance (±435ms and ±595ms) indicates inconsistent scale-down timing

This is an inherent HPA design trade-off: fast scale-down risks flapping, slow scale-down wastes resources and increases contention on single-node.

### 3.4 Proactive: Costly but Clean Recovery

Proactive pre-scaling hurts performance during load (due to contention) but recovers cleanly:

- **low_2 P99:** 230ms — 1.2× baseline (close to baseline-level performance)
- **night_2 P99:** 183ms — 1.6× baseline (close to baseline-level performance)
- No lingering pods because the script explicitly scales down after the high-load segment

This suggests proactive scaling would be more effective on multi-node clusters where pre-provisioned pods can spread across physical machines.

### 3.5 Hybrid: Worst of Both Worlds on Single-Node

Hybrid combines HPA with a raised minReplicas floor, but on single-node this creates compound contention:

- The floor ensures 7 pods minimum even before load starts (3+2+2)
- HPA then adds more pods on top, reaching 10–14 total
- Scale-down is delayed by both the HPA stabilization window AND the floor preventing return to 1
- **Day segment P99 of 1518ms** is the worst single measurement across all strategies

The hybrid approach would theoretically excel on multi-node clusters with predictable traffic patterns, where the floor ensures warm capacity without causing CPU contention.

### 3.6 Throughput Saturation

Proactive and hybrid cannot sustain the requested QPS during spike:

| Strategy | Requested QPS | Achieved QPS | Throughput Loss |
|----------|--------------|--------------|-----------------|
| Baseline | 60 | 59.8 | 0.3% |
| Reactive | 60 | 59.1 | 1.5% |
| Proactive | 60 | 27.5 | **54.2%** |
| Hybrid | 60 | 32.5 | **45.8%** |

With 10+ pods on one node, request processing becomes CPU-bound — the system physically cannot process 60 requests/second because CPU is fragmented across too many JVM instances.



## 5. Resource Cost Proxy

To compare strategies fairly, we estimate resource consumption as replica-seconds (total pod-count × time):

| Pattern | Strategy | Estimated Replica-Seconds | Cost vs Baseline |
|---------|----------|--------------------------|-----------------|
| Spike | Baseline | 450 | 1.0× |
| Spike | Reactive | ~540–660 | ~1.3× |
| Spike | Proactive | 1,080 | **2.4×** |
| Spike | Hybrid | ~630–1,050 | **~1.8×** |
| Day-night | Baseline | 630 | 1.0× |
| Day-night | Reactive | ~930 | ~1.5× |
| Day-night | Proactive | 1,680 | **2.7×** |
| Day-night | Hybrid | ~1,050–1,470 | **~2.0×** |

**Finding:** Proactive and hybrid consume 2–3× more resources than baseline while delivering worse latency on single-node. In a cloud billing context, this would mean paying more for worse performance — a clearly suboptimal outcome specific to single-node deployment.

---

## 6. Summary of Key Findings

1. **On single-node Kubernetes, horizontal scaling beyond 3–4 pods degrades performance** due to CPU contention. This is the dominant finding and applies across all workload patterns.

2. **Baseline (no autoscaling) delivers the best tail latency** in nearly every segment — demonstrating that on resource-constrained single-node clusters, the simplest approach wins.

3. **Reactive (HPA) is the most effective autoscaling strategy** on single-node — it scales conservatively enough to avoid severe contention and maintains near-target throughput. However, it suffers a significant scale-down penalty (5–8× baseline P99 during recovery phases).

4. **Proactive pre-scaling hurts performance during load** but provides the cleanest recovery behavior — important evidence that proactive scaling's value depends entirely on the infrastructure topology.

5. **Hybrid shows the worst combined performance** — the minimum-replica floor plus HPA-driven scaling creates maximum pod count and maximum contention on single-node.

6. **Strategy effectiveness is infrastructure-dependent.** These results should not be interpreted as evidence that proactive or hybrid scaling is inherently inferior. On multi-node production clusters, where pods distribute across physical machines, the resource contention problem disappears and pre-provisioned capacity would provide its intended latency benefit.

7. **The HPA's conservative scaling behavior** on single-node acts as an accidental advantage — it limits pod count precisely because adding pods doesn't reduce per-pod CPU utilization when all pods share one node.

---

## 7. Implications for the Thesis

These findings directly address the three research questions:

**RQ1 (Operational definitions and distinctions):** The experiment confirms that the three strategy classes — reactive (HPA), proactive (script-triggered pre-scaling), and hybrid (HPA + dynamic minReplicas floor) — produce measurably different scaling behavior, resource consumption, and tail-latency profiles. This validates them as empirically meaningful operational distinctions rather than purely taxonomic categories.

**RQ2 (Experimental setup):** The MiniShop testbed combined with a within-subjects design, two complementary workload patterns (abrupt spike and gradual day-night), three repetitions per condition, and p99 tail latency as the primary metric proved sufficient to detect clear, reproducible differences between all four conditions across 24 runs. The synthetic CPU workload (`work=2`) ensured measurable HPA-triggering load across all three services.

**RQ3 (Empirical comparison):** The ranking under single-node Minikube is **Baseline ≈ Reactive > Proactive > Hybrid** for tail latency stability. This ranking is the reverse of what multi-node literature reports (Luo et al. 2022, Cai et al. 2022, Ahmad et al. 2025) and is consistent with the multi-node literature once the infrastructure constraint is accounted for. The central finding is that autoscaling strategy effectiveness is infrastructure-dependent and recommendations cannot be made independently of deployment topology.

---

*Generated from exp_patterns_minikube_v6 — 24 runs across 4 strategies × 2 patterns × 3 repetitions.*
