from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "results" / "exp_patterns_minikube_v1" / "summary_fortio.csv"
OUT = ROOT / "results" / "exp_patterns_minikube_v1" / "summary_fortio_agg.csv"

print(f"Reading: {INPUT}")
df = pd.read_csv(INPUT)

# exclude warmup from evaluation aggregation
df = df[df["segment"] != "warmup"].copy()

agg = (
    df.groupby(["pattern", "strategy", "segment"])
    .agg(
        reps=("rep", "count"),
        avg_mean=("avg_ms", "mean"),
        avg_std=("avg_ms", "std"),
        p50_mean=("p50_ms", "mean"),
        p50_std=("p50_ms", "std"),
        p90_mean=("p90_ms", "mean"),
        p90_std=("p90_ms", "std"),
        p99_mean=("p99_ms", "mean"),
        p99_std=("p99_ms", "std"),
        qps_mean=("qps_act", "mean"),
        qps_std=("qps_act", "std"),
        errors_sum=("errors", "sum"),
    )
    .reset_index()
)

agg.to_csv(OUT, index=False)
print(f"Written: {OUT}")
print(agg)