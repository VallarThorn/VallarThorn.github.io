---
title: "Teaching an LLM to Prioritize Kernel Bugs: AI-Guided Fuzzing with syz-heuristic"
date: 2026-08-21
categories: [AI, Fuzzing]
tags: [ai, llm, claude, syzkaller, fuzzing, static-analysis, codeql, semgrep, vulnerability-research]
---

<!--
TODO (write this section): the motivating problem — 3,130 functions in the Mali
GPU driver, way too many to manually triage. Frame syz-heuristic as: rank every
function by attack-surface density and vulnerability likelihood, then use the
top candidates to steer both manual review and syzkaller's seed corpus.
-->

## Six Layers of Static Signal Before AI Ever Sees the Code

```
Driver source
      |
      v
 extract.py          <- ctags function extraction (3,130 functions)
      |
      +-- L1 grep density (heap/alloc, locking, user input, freed-var reuse)
      +-- L2 Semgrep structural patterns
      +-- L3 Clang Static Analyzer findings
      +-- L4 CodeQL interprocedural taint + UAF/locking hints
      +-- L5 EL0 reachability (call-graph BFS from entry points)
      +-- L6 version-chain diff signal (r49p1 -> r54p3)
      |
      v
  rank.py (pass 1)   <- reachability gate -> weighted sum -> sort
      |
      v
  ai_weight.py        <- LLM confidence pass, top K_TOP=50 only
      |
      v
  rank.py (pass 2)    <- re-score with ai_weight populated
```

<!-- TODO: explain why AI only ever sees the top 50 rather than all 3,130 —
cost, and the two-pass design (rank blind, then re-rank with AI confidence)
so the LLM isn't the thing doing the initial triage from scratch. -->

## Where the Model Fits

```
| Signal              | Weight | Status                                    |
|----------------------|--------|-------------------------------------------|
| L2 Semgrep            | 0.19   | done                                       |
| L4 CodeQL taint        | 0.18   | done                                       |
| AI confidence          | 0.20   | code complete -- needs ANTHROPIC_API_KEY   |
```

The AI step sends each candidate's function body plus every static signal that
fired on it, and asks for a structured `ai_weight` (0.0-1.0) with reasoning.
It fails soft — no API key, `ai_weight` just stays 0 for everyone, pipeline
still runs to completion.

<!-- TODO: explain the fail-soft design choice — why a research pipeline like
this shouldn't hard-fail on a missing API key, and what "structured output"
actually bought you here (vs. parsing free-form text back out of the model). -->

## Don't Trust the Model's Ioctl Numbers

<!-- TODO: this is the best story in the project — tell it directly. The first
seed-generation run produced trigger sequences with plausible-looking ioctl hex
codes. Cross-checking against the real UAPI headers found 0 out of 11 matched —
including in the CVE-2025-0072 reference seed, where the codes turned out to be
illustrative, not real. -->

The fix was `mali_ioctl.py`: instead of letting the model guess ioctl command
numbers, it parses the real UAPI header and computes the actual `_IOWR`/`_IOW`/
`_IOR` encoding from each struct's real C layout — then force-corrects the
model's output against that table afterward.

```
manifest.json reports, per generated seed:
  ioctl_calls_total / grounded / corrected, ungrounded_names
```

<!-- TODO: the broader point here generalizes well for a blog post — "grounding"
an LLM's structured output against a verified source of truth, and measuring how
much of its output actually needed correcting. Worth stating plainly as the
lesson. -->

## Validating Against a Real CVE

CVE-2025-0072 (Mali CSF queue UAF) was used as ground truth, checked *before*
the fix was public knowledge:

- `kbase_csf_user_io_pages_vm_fault` was the top function by L6 diff-touch
  count even without any AI signal.
- Adding a "hotfix" sub-signal (functions touched in a small, focused patch)
  pushed `unbind_stopped_queue` — the actual root cause — to the top of its
  recency score.

<!-- TODO: be honest about the current limitation here too — as more real
signals got added, both ground-truth functions actually drifted below the K=50
cutoff, so the AI step in its current form has never scored either of them.
This is a good place to talk candidly about weighted-sum recalibration as
future work rather than overselling the result. -->

## What the Model Gets Wrong

<!-- TODO: the first live AI run came back with uniformly low ai_weight scores
(0.02-0.1) for every K_TOP candidate — in each case reasoning that the flagged
concern was "locally balanced" (matched alloc/free, symmetric lock/unlock)
within that one function. Explain why that's a real blind spot: the model only
sees one function body at a time, so it structurally can't catch a bug whose
correctness depends on what the caller guarantees. -->

## What's Next

<!-- TODO: broader caller/callee context for the AI step (via the L5 call
graph), scoring the 255 candidate race pairs the same way, dedup.py. -->
