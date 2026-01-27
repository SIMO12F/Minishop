import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

# INPUT: aggregated file with mean/std per (pattern, strategy, segment)
IN = Path("results/exp_patterns_minikube_v1/summary_fortio_agg.csv")

# OUTPUT: where PNGs go
OUTDIR = Path("results/plots_agg")
OUTDIR.mkdir(parents=True, exist_ok=True)

print("Reading:", IN.resolve())
df = pd.read_csv(IN)
print("Rows:", len(df), "Cols:", len(df.columns))
print("Columns:", df.columns.tolist())

# keep only segments that matter for evaluation
# spike pattern: low_1, low_2, spike
# daynight pattern: night_1, night_2, day
# (warmup usually excluded)
keep = df["segment"].isin(["spike", "day", "night_1", "night_2", "low_1", "low_2"])
df = df[keep].copy()

def plot_metric(segment: str, metric_mean: str, metric_std: str, title: str, ylabel: str, fname: str):
    d = df[df["segment"] == segment].copy()
    if d.empty:
        print(f"skip {segment} (no data)")
        return

    # order strategies (consistent x-axis)
    order = ["baseline", "reactive", "proactive", "hybrid"]
    d["strategy"] = pd.Categorical(d["strategy"], categories=order, ordered=True)
    d = d.sort_values(["pattern", "strategy"])

    # one plot per pattern
    for pattern in sorted(d["pattern"].unique()):
        p = d[d["pattern"] == pattern].copy()
        if p.empty:
            continue

        x = list(p["strategy"].astype(str))
        y = p[metric_mean].astype(float).tolist()
        e = p[metric_std].astype(float).tolist()

        plt.figure()
        plt.errorbar(x, y, yerr=e, fmt="o-", capsize=4)
        plt.title(f"{title} | pattern={pattern} | segment={segment}")
        plt.ylabel(ylabel)
        plt.xlabel("strategy")
        plt.grid(True, axis="y", linestyle="--", alpha=0.4)

        out = OUTDIR / f"{fname}_{pattern}_{segment}.png"
        plt.tight_layout()
        plt.savefig(out, dpi=200)
        plt.close()
        print("wrote", out)

# ---- PLOTS ----

# Tail latency p99 (ms)
for seg in ["spike", "day", "night_1", "night_2", "low_1", "low_2"]:
    plot_metric(
        segment=seg,
        metric_mean="p99_mean",
        metric_std="p99_std",
        title="Tail latency (p99)",
        ylabel="p99 latency (ms)",
        fname="p99"
    )

# Mean latency avg (ms)
for seg in ["spike", "day", "night_1", "night_2", "low_1", "low_2"]:
    plot_metric(
        segment=seg,
        metric_mean="avg_mean",
        metric_std="avg_std",
        title="Mean latency (avg)",
        ylabel="avg latency (ms)",
        fname="avg"
    )

# Throughput (QPS)
for seg in ["spike", "day", "night_1", "night_2", "low_1", "low_2"]:
    plot_metric(
        segment=seg,
        metric_mean="qps_mean",
        metric_std="qps_std",
        title="Achieved throughput",
        ylabel="QPS",
        fname="qps"
    )
