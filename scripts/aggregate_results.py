import pandas as pd
from pathlib import Path

# Paths
ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "results" / "exp_matrix_minikube_v1" / "summary.csv"
OUTDIR = ROOT / "results" / "exp_matrix_minikube_v1"
OUTDIR.mkdir(exist_ok=True)

print(f"Reading: {INPUT}")

df = pd.read_csv(INPUT)

# Convert seconds -> milliseconds (thesis-friendly)
for col in ["p50_s", "p90_s", "p99_s"]:
    df[col.replace("_s", "_ms")] = df[col] * 1000

# Aggregate
agg = (
    df
    .groupby(["strategy", "qps"])
    .agg(
        runs=("rep", "count"),
        actual_qps_mean=("actual_qps", "mean"),
        p50_mean_ms=("p50_ms", "mean"),
        p50_std_ms=("p50_ms", "std"),
        p90_mean_ms=("p90_ms", "mean"),
        p90_std_ms=("p90_ms", "std"),
        p99_mean_ms=("p99_ms", "mean"),
        p99_std_ms=("p99_ms", "std"),
    )
    .reset_index()
)

OUT = OUTDIR / "aggregated_latency.csv"
agg.to_csv(OUT, index=False)

print("\n=== Aggregated results saved ===")
print(OUT)
print("\nPreview:")
print(agg)
