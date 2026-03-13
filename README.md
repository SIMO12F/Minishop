# MiniShop

MiniShop is a compact Java microservice testbed for controlled autoscaling experiments on Kubernetes. This project was developed as part of my Master’s thesis on evaluating autoscaling strategies for Java microservices on Kubernetes, with a comparative focus on **reactive**, **proactive**, and **hybrid** scaling under identical workload and deployment conditions.

The repository is intentionally small enough to remain reproducible on a local **Minikube** cluster while still exposing the behaviors that matter for autoscaling research: service-to-service calls, readiness and startup delays, JVM warm-up effects, scaling lag, and end-to-end tail latency at a gateway boundary.

## Table of Contents

- [Project Overview](#project-overview)
- [Research Context](#research-context)
- [System Architecture](#system-architecture)
- [Services and Endpoints](#services-and-endpoints)
- [Autoscaling Strategies](#autoscaling-strategies)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Running the System Locally](#running-the-system-locally)
- [Running with Docker Compose](#running-with-docker-compose)
- [Running on Kubernetes (Minikube)](#running-on-kubernetes-minikube)
- [Experiment Workflow](#experiment-workflow)
- [Results and Evaluation Scope](#results-and-evaluation-scope)
- [Reproducibility Notes](#reproducibility-notes)
- [Limitations](#limitations)
- [Author / Thesis Note](#author--thesis-note)

---

## Project Overview

MiniShop consists of three Spring Boot microservices:

- `gateway-service`
- `product-service`
- `order-service`

The gateway acts as the single entry point and aggregates responses from the two backend services. This creates a short but meaningful service chain for measuring **end-to-end latency** rather than isolated single-service behavior.

The repository supports three main use cases:

- **Academic documentation** for the thesis testbed and experiment logic
- **Recruiter / portfolio presentation** of a practical microservices + Kubernetes project
- **Developer reproducibility**, including local execution, Docker Compose, and Minikube-based experiment workflows

---

## Research Context

This project was developed as part of my Master’s thesis on evaluating autoscaling strategies for Java microservices on Kubernetes.

The core idea of the study is to compare different autoscaling strategy classes under the same controlled conditions:

- identical application version
- identical Kubernetes manifests
- identical resource requests and limits
- identical workload patterns
- identical measurement point
- only the autoscaling strategy changes

The primary performance outcome is **end-to-end tail latency** measured at the gateway endpoint `/api/summary`, with special attention to **p95** and **p99** behavior. Throughput is treated mainly as a validity check, and resource-based cost is interpreted as a transparent comparative proxy rather than provider billing.

---

## System Architecture

### High-level request flow

```text
Client / Load Generator
        |
        v
gateway-service :8081
   |            |
   v            v
product-service :8080
order-service   :8082
```

### Architectural idea

- `gateway-service` is the client-facing entry point
- `product-service` provides product data
- `order-service` provides order data
- `/api/summary` in the gateway calls both backend services and returns one combined response

This makes MiniShop suitable for studying autoscaling effects in a **microservice request chain**, where latency depends not only on one service but also on downstream dependencies.

---

## Services and Endpoints

### `product-service`
Runs on port `8080`

Endpoints:

- `GET /products`
- `GET /products/{id}`
- `POST /products`

Health-related endpoints:

- `GET /actuator/health`
- `GET /actuator/health/readiness`
- `GET /actuator/health/liveness`

### `order-service`
Runs on port `8082`

Endpoints:

- `GET /orders`
- `GET /orders/{id}`

Health-related endpoints:

- `GET /actuator/health`
- `GET /actuator/health/readiness`
- `GET /actuator/health/liveness`

### `gateway-service`
Runs on port `8081`

Endpoints:

- `GET /api/products`
- `GET /api/orders`
- `GET /api/summary`

Health-related endpoints:

- `GET /actuator/health`
- `GET /actuator/health/readiness`
- `GET /actuator/health/liveness`

### Notes on workload parameters

The service endpoints support query parameters that help generate controlled behavior during tests:

- `work`
- `tailEvery`
- `tailExtra`

These parameters are used to simulate CPU work and occasional tail-latency effects in a controlled way.

---

## Autoscaling Strategies

MiniShop compares four deployment conditions:

### 1. Baseline
No autoscaling. All services run with fixed replica counts.

### 2. Reactive
Kubernetes **Horizontal Pod Autoscaler (HPA)** based on CPU utilization.

Current HPA setup in the repository:

- CPU target: `60%`
- `gateway-service`: `1..6` replicas
- `order-service`: `1..4` replicas
- `product-service`: `1..4` replicas

### 3. Proactive
Schedule-driven scaling using **Kubernetes CronJobs**.

Current schedule in the repository:

- scale up at minute `0` of every hour
- scale down at minute `30` of every hour

Current proactive target sizes:

- `gateway-service` → `4` replicas
- `order-service` → `3` replicas
- `product-service` → `3` replicas

### 4. Hybrid
Combination of **Cron-based planning** and **HPA-based correction**.

In this implementation, CronJobs do **not** directly fight the Deployment replica count. Instead, they patch the HPA `minReplicas`, which creates a cleaner hybrid control design.

Current hybrid floor values:

- high-capacity phase:
    - `gateway-service` minReplicas = `3`
    - `order-service` minReplicas = `2`
    - `product-service` minReplicas = `2`
- low-capacity phase:
    - all minReplicas reset to `1`

---

## Technology Stack

- **Java 21**
- **Spring Boot 4**
- **Spring Boot Actuator**
- **Maven / Maven Wrapper**
- **Docker**
- **Docker Compose**
- **Kubernetes**
- **Minikube**
- **Fortio** for load generation
- **PowerShell** for experiment automation
- **Python / pandas / matplotlib** for aggregation and plotting

---

## Repository Structure

```text
minishop/
├── gateway-service/                 # Gateway / aggregator service
├── product-service/                 # Product backend service
├── order-service/                   # Order backend service
├── k8s/
│   ├── minishop.yaml                # Base Kubernetes manifests
│   └── autoscaling/
│       ├── reactive-hpa.yaml        # Reactive HPA configuration
│       ├── proactive-cron.yaml      # Proactive scheduled scaling
│       ├── hybrid-cron.yaml         # Hybrid Cron + HPA floor patching
│       └── autoscaler-rbac-hpa.yaml # RBAC for autoscaling jobs / HPA support
├── scripts/
│   ├── run_patterns.ps1             # Main experiment runner
│   ├── extract_fortio_results.ps1   # Extract Fortio JSON into CSV
│   ├── aggregate_fortio_patterns.py # Aggregate repeated runs
│   ├── aggregate_results.py         # Older aggregation script
│   ├── clean_summary_csvs.py        # CSV cleaning utility
│   └── plot_results.py              # Plotting utility
├── plots/
│   └── make_plots.py                # Main plot generation script
├── results/                         # Result artifacts and exported summaries
├── docker-compose.yml               # Local multi-container setup
└── README.md
```

---

## Running the System Locally

### Requirements

- Java `21+`
- Maven or Maven Wrapper
- 3 terminals
- Optional: IntelliJ IDEA

### 1) Start `product-service`

```bash
cd product-service
./mvnw spring-boot:run
```

Test:

```text
http://localhost:8080/products
```

### 2) Start `order-service`

```bash
cd order-service
./mvnw spring-boot:run
```

Test:

```text
http://localhost:8082/orders
```

### 3) Start `gateway-service`

```bash
cd gateway-service
./mvnw spring-boot:run
```

Test:

```text
http://localhost:8081/api/products
http://localhost:8081/api/orders
http://localhost:8081/api/summary
```

### Important note

When running locally, the gateway uses local service URLs from `application.properties`:

- `services.product.url=http://localhost:8080`
- `services.order.url=http://localhost:8082`

---

## Running with Docker Compose

### Requirements

- Docker Desktop
- Docker Compose v2

### Build the JARs

```bash
cd product-service && ./mvnw clean package -DskipTests
cd ../order-service && ./mvnw clean package -DskipTests
cd ../gateway-service && ./mvnw clean package -DskipTests
cd ..
```

### Start the system

```bash
docker compose up --build
```

### Test endpoints

```text
http://localhost:8080/products
http://localhost:8082/orders
http://localhost:8081/api/products
http://localhost:8081/api/orders
http://localhost:8081/api/summary
```

### Stop the system

```bash
docker compose down
```

### Docker networking note

Inside Docker, the gateway resolves backend services via container DNS names:

- `http://product-service:8080`
- `http://order-service:8082`

---

## Running on Kubernetes (Minikube)

### Requirements

- Minikube
- `kubectl`
- PowerShell
- Python
- metrics-server available in Minikube

### Base manifest

```text
k8s/minishop.yaml
```

This manifest defines:

- namespace `minishop`
- gateway ConfigMap
- Deployments for all three services
- Services for all three services
- resource requests and limits
- startup, readiness, and liveness probes

### Autoscaling manifests

```text
k8s/autoscaling/reactive-hpa.yaml
k8s/autoscaling/proactive-cron.yaml
k8s/autoscaling/hybrid-cron.yaml
k8s/autoscaling/autoscaler-rbac-hpa.yaml
```

### Important note about Kubernetes images

The Kubernetes manifests reference these local images:

- `minishop/product-service:0.1`
- `minishop/order-service:0.1`
- `minishop/gateway-service:0.1`
- `minishop/kubectl:1.34`

So before applying the manifests manually, make sure those images exist in the container runtime used by your Minikube setup.

### NodePort

The gateway is exposed as a NodePort service on:

```text
30081
```

Internally, the experiment workflow targets the in-cluster service URL:

```text
http://gateway-service:8081/api/summary
```

---

## Experiment Workflow

The repository contains a scripted workflow for running autoscaling experiments on Minikube, extracting Fortio outputs, aggregating repeated runs, and generating plots.

### 1) Run the pattern experiments

Run from the repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\run_patterns.ps1
```

### Current active script configuration

At the time of writing, the main runner is configured as:

```powershell
$Reps = 5
$PatternsToRun = @("daynight")
$StrategiesToRun = @("baseline", "reactive", "proactive", "hybrid")
```

The script automatically:

- checks Minikube
- enables `metrics-server`
- applies the base manifest
- applies the autoscaling condition
- runs Fortio from inside the cluster
- stores metadata and snapshots for each segment

### Workload patterns supported by the runner

#### Spike pattern
- `low_1` → `QPS=10`, `60s`
- `spike` → `QPS=60`, `30s`
- `low_2` → `QPS=10`, `60s`

#### Day-night pattern
- `night_1` → `QPS=10`, `60s`
- `day` → `QPS=30`, `90s`
- `night_2` → `QPS=10`, `60s`

Warm-up is performed before measurement.

### Output location

Results are written under:

```text
results/exp_patterns_minikube_v1/<pattern>/<strategy>/repX/
```

Each repetition directory contains artifacts such as:

- `run_metadata.txt`
- `fortio_<segment>.json`
- `fortio_<segment>.describe.txt`
- `metrics/` snapshots
- live deployment / HPA / CronJob state captures

### 2) Extract Fortio summaries

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\extract_fortio_results.ps1
```

This produces:

```text
results/exp_patterns_minikube_v1/summary_fortio.csv
```

### 3) Aggregate repeated runs

```bash
python .\scripts\aggregate_fortio_patterns.py
```

This produces:

```text
results/exp_patterns_minikube_v1/summary_fortio_agg.csv
```

The aggregation excludes warm-up rows and computes mean / standard deviation per:

- pattern
- strategy
- segment

### 4) Generate plots

```bash
python .\plots\make_plots.py
```

This writes plot files to:

```text
results/plots_agg/
```

Typical outputs include:

- `p99_daynight_day.png`
- `p99_spike_spike.png`
- `avg_daynight_night_2.png`
- `qps_spike_low_1.png`

---

## Results and Evaluation Scope

MiniShop was built to support a controlled comparative evaluation of autoscaling strategies rather than a production benchmark.

The evaluation focuses primarily on:

- **tail latency** (`p95`, `p99`)
- **throughput** (`QPS`) as a validity check
- **resource-based cost proxy** expressed as resource-seconds

### Main interpretation goal

The key question is not which autoscaler is universally best, but:

> Under the same application, the same manifests, the same workload patterns, and the same measurement point, how do reactive, proactive, and hybrid autoscaling differ in latency behavior and capacity trade-offs?

### Summary of the thesis findings

At a high level, the thesis evaluation showed that strategy choice materially changes tail-latency stability:

- **Hybrid** performed especially well under predictable day-night style variation
- **Proactive** performed strongly when capacity was already prepared ahead of bursts
- **Reactive** remained important as an adaptive correction mechanism, but naturally suffers from scale-up delay compared with pre-provisioned capacity

### Important interpretation note

The strongest evidence in the study concerns **latency behavior**. The resource-based cost metric is intentionally transparent and useful for comparison, but it should not be interpreted as a direct cloud billing estimate.

---

## Reproducibility Notes

MiniShop was designed with reproducibility in mind:

- fixed microservice topology
- fixed measurement endpoint
- fixed resource requests and limits
- scripted workload execution
- stored run metadata
- saved manifests and cluster-state snapshots
- repeat-based aggregation

This makes the project suitable for:

- thesis verification
- educational demonstrations
- autoscaling lab work
- portfolio presentation of Kubernetes experimentation

---

## Limitations

MiniShop is intentionally minimal and therefore has clear boundaries.

### Included

- microservice-to-microservice communication
- gateway-based request chaining
- health, readiness, and startup probes
- Docker Compose packaging
- Kubernetes deployment manifests
- HPA / Cron / hybrid autoscaling logic
- scripted Fortio-based experiment workflow

### Not included

- persistent database layer
- service mesh
- production observability stack
- distributed tracing
- cloud-provider billing integration
- multi-node production calibration

### Experimental limitations

- Minikube is a **single-node** environment
- Fortio and the application share local hardware resources
- results support **relative comparison inside the testbed**
- absolute production latency conclusions should not be drawn from this setup alone

---

## Author / Thesis Note

This repository documents the implementation and experiment testbed used in my Master’s thesis on autoscaling strategies for Java microservices on Kubernetes.

It is published both as:

- a reproducible academic project
- a practical Kubernetes / microservices portfolio project
- a reference implementation for controlled autoscaling experiments
