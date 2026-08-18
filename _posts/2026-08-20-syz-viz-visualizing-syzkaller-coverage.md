---
title: "syz-viz: Visualizing Syzkaller Coverage in 3D to Find Unfuzzed Code"
date: 2026-08-20
categories: [Fuzzing, Tools]
tags: [syzkaller, fuzzing, coverage, visualization, codecharta, python]
---

<!--
TODO (write this section): the problem with reading syzkaller's own coverage
dashboard for a driver this size (mali_kbase.ko) — a flat per-file percentage
table doesn't tell you where to point the fuzzer next. Motivate the "code city"
idea: turn the driver source tree into a 3D city where geometry encodes signal.
-->

## Three Dimensions, Three Signals

| Visual dimension | Metric | Reading |
|---|---|---|
| Floor area | `lines_total` | Bigger block = bigger file |
| Color | `coverage_pct` | Green = well-fuzzed (safer), Red = unexplored (danger) |
| Height | `syz_heuristic` | Taller = higher fuzzing priority |

**Primary targets**: tall + red blocks — high attack-surface score, near-zero coverage.

<!-- TODO: walk through an actual tall-red block you found this way and what
you did about it. -->

## Where the Height Comes From

Height isn't just inverse coverage — it's a compound score built from static
analysis and diff signal, computed per file:

```
syz_heuristic = syz_mem(25) + syz_race(25) + syz_input(25)
              + syz_interest(15) + syz_static(20)
              + known_bug(+10) + diff_target(+10)
              [capped at 100]
```

<!-- TODO: brief pointer to the syz-heuristic post for the full breakdown of
each sub-score, since this post is about the visualization, not the scoring
pipeline itself. -->

## The Pipeline

```bash
cd ~/Desktop/Projects/syz-viz
source .env

# 1. Fetch live coverage from the fuzzing target over SSH
./fetch_coverage.sh
# -> mali_coverage_raw.json

# 2. Generate the cc.json visualization
python3 gen_codecharta.py mali_coverage_raw.json
# -> mali_kbase_coverage_YYYY-MM-DD.cc.json

# 3. Serve it
./serve.sh
# -> http://localhost:9300/?file=mali_kbase_coverage_YYYY-MM-DD.cc.json
```

<!-- TODO: explain fetch_coverage.sh briefly — it's pulling raw coverage off the
device over SSH and symbolizing addresses with addr2line against a specific
module .text base, which has to be reconfirmed after every kernel rebuild or
KASLR gets involved. Worth a short technical note on why MODULE_BASE drifts. -->

## Tracking Coverage Over Time

```bash
ccsh merge \
  mali_kbase_coverage_2026-06-06.cc.json \
  mali_kbase_coverage_2026-08-20.cc.json \
  --output-file mali_kbase_merged.cc.json
```

<!-- TODO: show/describe an actual before/after — did coverage visibly creep
into previously-red blocks after a fuzzing run, or after adding AI-generated
seeds from syz-heuristic? -->

## Keeping the Annotations Honest

<!-- TODO: the three static annotation dictionaries (INTEREST, STATIC_ANALYSIS,
KNOWN_BUG/DIFF_TARGET) in gen_codecharta.py are hand-maintained, not automated.
Talk about the tradeoff — why not fully automate this, what breaks if you do,
what the update workflow actually looks like after a new finding lands. -->

## What's Next
