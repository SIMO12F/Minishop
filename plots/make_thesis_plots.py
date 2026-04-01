"""
Thesis Plot Generator — v6 Experiment Data
Mohammed Mbida, HAWK Göttingen, 2026

Generates all figures for Chapter 4 from summary_fortio_agg.csv and summary_fortio.csv.
Run from the project root: python plots/make_thesis_plots.py

Input:  results/exp_patterns_minikube_v6/summary_fortio_agg.csv
        results/exp_patterns_minikube_v6/summary_fortio.csv
Output: results/thesis_plots/fig4_*.png
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
import os

# ── Paths (relative to project root) ─────────────────────────────────
DATA_DIR = os.path.join('results', 'exp_patterns_minikube_v6')
AGG_CSV  = os.path.join(DATA_DIR, 'summary_fortio_agg.csv')
RAW_CSV  = os.path.join(DATA_DIR, 'summary_fortio.csv')
OUT_DIR  = os.path.join('results', 'thesis_plots')
os.makedirs(OUT_DIR, exist_ok=True)

# ── Load data ─────────────────────────────────────────────────────────
df  = pd.read_csv(AGG_CSV)
raw = pd.read_csv(RAW_CSV)

# ── Style ─────────────────────────────────────────────────────────────
plt.rcParams.update({
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'font.size': 11,
    'axes.titlesize': 13,
    'axes.labelsize': 12,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 10,
    'figure.figsize': (7, 4.2),
    'axes.facecolor': 'white',
    'figure.facecolor': 'white',
    'axes.grid': True,
    'grid.alpha': 0.3,
    'grid.linestyle': '--',
    'axes.spines.top': False,
    'axes.spines.right': False,
})

COLORS  = {'baseline': '#2176AE', 'reactive': '#3EA34D', 'proactive': '#E8913A', 'hybrid': '#9B59B6'}
MARKERS = {'baseline': 'o', 'reactive': 's', 'proactive': '^', 'hybrid': 'D'}
LABELS  = {'baseline': 'Baseline (3 pods)', 'reactive': 'Reactive (HPA)',
           'proactive': 'Proactive (10 pods)', 'hybrid': 'Hybrid (7+ pods)'}
STRATEGIES = ['baseline', 'reactive', 'proactive', 'hybrid']
SPIKE_SEGS    = ['low_1', 'spike', 'low_2']
DAYNIGHT_SEGS = ['night_1', 'day', 'night_2']


def val(pattern, strategy, segment, col):
    row = df[(df['pattern'] == pattern) & (df['strategy'] == strategy) & (df['segment'] == segment)]
    return row[col].values[0] if len(row) > 0 else np.nan


# ══════════════════════════════════════════════════════════════════════
# Fig 4.1 — Timeline P99, Spike Pattern
# ══════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots()
for s in STRATEGIES:
    means = [val('spike', s, seg, 'p99_mean') for seg in SPIKE_SEGS]
    stds  = [val('spike', s, seg, 'p99_std')  for seg in SPIKE_SEGS]
    ax.errorbar(SPIKE_SEGS, means, yerr=stds, label=LABELS[s],
                color=COLORS[s], marker=MARKERS[s], markersize=7,
                linewidth=1.8, capsize=4, capthick=1.2)
ax.set_xlabel('Segment (time →)')
ax.set_ylabel('P99 Latency (ms)')
ax.set_title('P99 Tail Latency Across Segments — Spike Pattern')
ax.legend(loc='upper left', framealpha=0.9)
ax.set_ylim(bottom=0)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_1_timeline_p99_spike.png'))
plt.close()
print('  ✓ fig4_1_timeline_p99_spike.png')


# ══════════════════════════════════════════════════════════════════════
# Fig 4.2 — Scatter P99, Spike Recovery (low_2)
# ══════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(7, 3.8))
seg_data = raw[(raw['pattern'] == 'spike') & (raw['segment'] == 'low_2')]
for i, s in enumerate(STRATEGIES):
    pts = seg_data[seg_data['strategy'] == s]['p99_ms'].dropna()
    x = np.full(len(pts), i) + np.random.uniform(-0.08, 0.08, len(pts))
    ax.scatter(x, pts, color=COLORS[s], marker=MARKERS[s], s=60, zorder=5,
               edgecolors='white', linewidth=0.5)
    m = val('spike', s, 'low_2', 'p99_mean')
    ax.plot([i - 0.2, i + 0.2], [m, m], color=COLORS[s], linewidth=2.5, zorder=4)
ax.set_xticks(range(4))
ax.set_xticklabels([LABELS[s] for s in STRATEGIES], fontsize=9)
ax.set_ylabel('P99 Latency (ms)')
ax.set_title('P99 Latency per Repetition — Spike Recovery (low_2)')
ax.set_ylim(bottom=0)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_2_scatter_p99_spike_low2.png'))
plt.close()
print('  ✓ fig4_2_scatter_p99_spike_low2.png')


# ══════════════════════════════════════════════════════════════════════
# Fig 4.3 — Timeline P99, Day-Night Pattern
# ══════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots()
for s in STRATEGIES:
    means = [val('daynight', s, seg, 'p99_mean') for seg in DAYNIGHT_SEGS]
    stds  = [val('daynight', s, seg, 'p99_std')  for seg in DAYNIGHT_SEGS]
    ax.errorbar(DAYNIGHT_SEGS, means, yerr=stds, label=LABELS[s],
                color=COLORS[s], marker=MARKERS[s], markersize=7,
                linewidth=1.8, capsize=4, capthick=1.2)
ax.set_xlabel('Segment (time →)')
ax.set_ylabel('P99 Latency (ms)')
ax.set_title('P99 Tail Latency Across Segments — Day-Night Pattern')
ax.legend(loc='upper left', framealpha=0.9)
ax.set_ylim(bottom=0)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_3_timeline_p99_daynight.png'))
plt.close()
print('  ✓ fig4_3_timeline_p99_daynight.png')


# ══════════════════════════════════════════════════════════════════════
# Fig 4.4 — Scatter P99, Day-Night Day Segment
# ══════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(7, 3.8))
seg_data = raw[(raw['pattern'] == 'daynight') & (raw['segment'] == 'day')]
for i, s in enumerate(STRATEGIES):
    pts = seg_data[seg_data['strategy'] == s]['p99_ms'].dropna()
    x = np.full(len(pts), i) + np.random.uniform(-0.08, 0.08, len(pts))
    ax.scatter(x, pts, color=COLORS[s], marker=MARKERS[s], s=60, zorder=5,
               edgecolors='white', linewidth=0.5)
    m = val('daynight', s, 'day', 'p99_mean')
    ax.plot([i - 0.2, i + 0.2], [m, m], color=COLORS[s], linewidth=2.5, zorder=4)
ax.set_xticks(range(4))
ax.set_xticklabels([LABELS[s] for s in STRATEGIES], fontsize=9)
ax.set_ylabel('P99 Latency (ms)')
ax.set_title('P99 Latency per Repetition — Day Segment (30 QPS)')
ax.set_ylim(bottom=0)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_4_scatter_p99_daynight_day.png'))
plt.close()
print('  ✓ fig4_4_scatter_p99_daynight_day.png')


# ══════════════════════════════════════════════════════════════════════
# Fig 4.5 — Timeline QPS, Spike Pattern
# ══════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots()
for s in STRATEGIES:
    means = [val('spike', s, seg, 'qps_mean') for seg in SPIKE_SEGS]
    stds  = [val('spike', s, seg, 'qps_std')  for seg in SPIKE_SEGS]
    ax.errorbar(SPIKE_SEGS, means, yerr=stds, label=LABELS[s],
                color=COLORS[s], marker=MARKERS[s], markersize=7,
                linewidth=1.8, capsize=4, capthick=1.2)
ax.axhline(y=60, color='gray', linestyle=':', linewidth=1, alpha=0.6)
ax.text(1.05, 61, 'Target: 60 QPS', fontsize=8, color='gray')
ax.set_xlabel('Segment (time →)')
ax.set_ylabel('Achieved QPS')
ax.set_title('Achieved Throughput Across Segments — Spike Pattern')
ax.legend(loc='upper left', framealpha=0.9)
ax.set_ylim(bottom=0)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_5_timeline_qps_spike.png'))
plt.close()
print('  ✓ fig4_5_timeline_qps_spike.png')


# ══════════════════════════════════════════════════════════════════════
# Fig 4.6 — Bar Chart P99, Spike Pattern
# ══════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(7, 4.5))
x = np.arange(len(SPIKE_SEGS))
width = 0.18
for i, s in enumerate(STRATEGIES):
    means = [val('spike', s, seg, 'p99_mean') for seg in SPIKE_SEGS]
    stds  = [val('spike', s, seg, 'p99_std')  for seg in SPIKE_SEGS]
    ax.bar(x + (i - 1.5) * width, means, width, yerr=stds, label=LABELS[s],
           color=COLORS[s], capsize=3, edgecolor='white', linewidth=0.5)
ax.set_xticks(x)
ax.set_xticklabels(SPIKE_SEGS)
ax.set_xlabel('Segment')
ax.set_ylabel('P99 Latency (ms)')
ax.set_title('P99 Tail Latency by Strategy and Segment — Spike Pattern')
ax.legend(loc='upper left', framealpha=0.9)
ax.set_ylim(bottom=0)
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_6_bar_p99_spike.png'))
plt.close()
print('  ✓ fig4_6_bar_p99_spike.png')


# ══════════════════════════════════════════════════════════════════════
# Fig 4.7 — Combined Timeline P99, Both Patterns Side by Side
# ══════════════════════════════════════════════════════════════════════
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4.5))
for s in STRATEGIES:
    means = [val('spike', s, seg, 'p99_mean') for seg in SPIKE_SEGS]
    stds  = [val('spike', s, seg, 'p99_std')  for seg in SPIKE_SEGS]
    ax1.errorbar(range(3), means, yerr=stds, label=LABELS[s],
                 color=COLORS[s], marker=MARKERS[s], markersize=6,
                 linewidth=1.6, capsize=3, capthick=1)
ax1.set_xticks(range(3))
ax1.set_xticklabels(SPIKE_SEGS)
ax1.set_xlabel('Segment (time →)')
ax1.set_ylabel('P99 Latency (ms)')
ax1.set_title('(a) Spike Pattern')
ax1.set_ylim(bottom=0)
ax1.legend(fontsize=8, loc='upper left', framealpha=0.9)

for s in STRATEGIES:
    means = [val('daynight', s, seg, 'p99_mean') for seg in DAYNIGHT_SEGS]
    stds  = [val('daynight', s, seg, 'p99_std')  for seg in DAYNIGHT_SEGS]
    ax2.errorbar(range(3), means, yerr=stds, label=LABELS[s],
                 color=COLORS[s], marker=MARKERS[s], markersize=6,
                 linewidth=1.6, capsize=3, capthick=1)
ax2.set_xticks(range(3))
ax2.set_xticklabels(DAYNIGHT_SEGS)
ax2.set_xlabel('Segment (time →)')
ax2.set_ylabel('P99 Latency (ms)')
ax2.set_title('(b) Day-Night Pattern')
ax2.set_ylim(bottom=0)

plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'fig4_7_combined_p99_both.png'))
plt.close()
print('  ✓ fig4_7_combined_p99_both.png')


print(f'\nDone! All 7 figures saved to {OUT_DIR}/')
print('Copy these into your thesis images/ folder.')