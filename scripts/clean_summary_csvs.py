from pathlib import Path
import pandas as pd

root = Path(__file__).resolve().parents[1]
raw_path = root / "results" / "exp_patterns_minikube_v1" / "summary_fortio.csv"
agg_path = root / "results" / "exp_patterns_minikube_v1" / "summary_fortio_agg.csv"

valid_strategies = {"baseline", "reactive", "proactive", "hybrid"}

raw = pd.read_csv(raw_path)
raw = raw[raw["strategy"].isin(valid_strategies)].copy()
raw.to_csv(raw_path, index=False)

agg = pd.read_csv(agg_path)
agg = agg[agg["strategy"].isin(valid_strategies)].copy()
agg.to_csv(agg_path, index=False)

print("Cleaned raw rows:", len(raw))
print("Cleaned agg rows:", len(agg))
print("Strategies in raw:", sorted(raw["strategy"].unique()))
print("Strategies in agg:", sorted(agg["strategy"].unique()))