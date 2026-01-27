import os
import pandas as pd
import matplotlib.pyplot as plt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RESULTS_DIR = os.path.join(ROOT, "results", "exp_matrix_minikube_v1")
AGG = os.path.join(RESULTS_DIR, "aggregated_latency.csv")

OUT_DIR = os.path.join(RESULTS_DIR, "plots")
os.makedirs(OUT_DIR, exist_ok=True)

print(f"Reading: {AGG}")
df = pd.read_csv(AGG)

# Expected columns (from your preview):
# strategy,qps,runs,actual_qps_mean,actual_qps_std,p50_mean_ms,p50_std_ms,p90_mean_ms,p90_std_ms,p99_mean_ms,p99_std_ms
required = [
    "strategy","qps","runs",
    "p50_mean_ms","p50_std_ms",
    "p90_mean_ms","p90_std_ms",
    "p99_mean_ms","p99_std_ms",
]
missing = [c for c in required if c not in df.columns]
if missing:
    raise SystemExit(f"Missing columns in aggregated_latency.csv: {missing}\nColumns found: {list(df.columns)}")

# Make sure qps is numeric + sorted
df["qps"] = pd.to_numeric(df["qps"])
df = df.sort_values(["strategy", "qps"]).reset_index(drop=True)

# ---------- Plot helper ----------
def plot_metric(metric_mean: str, metric_std: str, title: str, out_name: str):
    plt.figure()
    for strategy in sorted(df["strategy"].unique()):
        sub = df[df["strategy"] == strategy].sort_values("qps")
        x = sub["qps"].tolist()
        y = sub[metric_mean].tolist()
        yerr = sub[metric_std].tolist()
        plt.errorbar(x, y, yerr=yerr, marker="o", capsize=3, label=strategy)

    plt.xlabel("Load (QPS)")
    plt.ylabel("Latency (ms)")
    plt.title(title)
    plt.xticks(sorted(df["qps"].unique()))
    plt.grid(True, which="both", linestyle="--", linewidth=0.5)
    plt.legend()
    out_path = os.path.join(OUT_DIR, out_name)
    plt.tight_layout()
    plt.savefig(out_path, dpi=180)
    plt.close()
    print(f"Saved: {out_path}")

plot_metric("p50_mean_ms", "p50_std_ms", "p50 latency vs QPS (mean ± std)", "p50_vs_qps.png")
plot_metric("p90_mean_ms", "p90_std_ms", "p90 latency vs QPS (mean ± std)", "p90_vs_qps.png")
plot_metric("p99_mean_ms", "p99_std_ms", "p99 latency vs QPS (mean ± std)", "p99_vs_qps.png")

# ---------- Percent delta vs baseline ----------
# delta% = (strategy - baseline) / baseline * 100  (positive = worse, negative = better)
base = df[df["strategy"] == "baseline"][["qps", "p50_mean_ms", "p90_mean_ms", "p99_mean_ms"]].copy()
base = base.rename(columns={
    "p50_mean_ms": "baseline_p50_ms",
    "p90_mean_ms": "baseline_p90_ms",
    "p99_mean_ms": "baseline_p99_ms",
})

merged = df.merge(base, on="qps", how="left")

for p in ["p50", "p90", "p99"]:
    merged[f"{p}_delta_pct_vs_baseline"] = (
            (merged[f"{p}_mean_ms"] - merged[f"baseline_{p}_ms"]) / merged[f"baseline_{p}_ms"] * 100.0
    )

out_cmp = os.path.join(RESULTS_DIR, "comparison_vs_baseline.csv")
merged.to_csv(out_cmp, index=False)
print(f"Saved: {out_cmp}")

# ---------- Simple ranking by p99 ----------
rank_rows = []
for qps in sorted(df["qps"].unique()):
    sub = df[df["qps"] == qps].copy()
    sub = sub.sort_values("p99_mean_ms", ascending=True)
    sub["rank_p99"] = range(1, len(sub) + 1)
    rank_rows.append(sub[["strategy", "qps", "p99_mean_ms", "p99_std_ms", "rank_p99"]])

rank = pd.concat(rank_rows, ignore_index=True)
out_rank = os.path.join(RESULTS_DIR, "ranking_by_p99.csv")
rank.to_csv(out_rank, index=False)
print(f"Saved: {out_rank}")

print("\nDone. Check:")
print(f"- {OUT_DIR}\\p50_vs_qps.png")
print(f"- {OUT_DIR}\\p90_vs_qps.png")
print(f"- {OUT_DIR}\\p99_vs_qps.png")
print(f"- {out_cmp}")
print(f"- {out_rank}")
