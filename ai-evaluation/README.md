# Gomoku AI evaluation

`run.py` builds the current production `gomoku/AIEngine.swift` without edits, using
`swiftc -O -swift-version 5` and the production model declarations through
`GameSession`. It strips only the unused `Combine` import from that model prefix.
The build record stores source hashes, compiler, host, and command arguments.

Tournament moves call `computeBestMove` directly. Profiling calls the engine's
native `analyzeMove` API, whose diagnostics belong to one search invocation.
Cache comparisons use `SearchOptions.useTranspositionTable`; the benchmark does
not rewrite search logic or add global diagnostic counters to the current AI.

## Commands

Run from the repository root on a Mac with the Swift toolchain:

```sh
python3 ai-evaluation/run.py basics
python3 ai-evaluation/run.py tactical
python3 ai-evaluation/run.py tactical-symmetries
python3 ai-evaluation/run.py correctness
python3 ai-evaluation/run.py difficulty-equivalence
python3 ai-evaluation/run.py profile
python3 ai-evaluation/run.py tournament 15 10 medium
python3 ai-evaluation/run.py tournament 15 10 baseline
python3 ai-evaluation/audit-losses.py
python3 ai-evaluation/summarize.py
```

The last two commands each run 20 games: ten fixed openings, with the current Hard
engine playing each color once per opening. `baseline` uses the exact prior Hard
engine saved in `baseline/AIEngine.swift`; the driver verifies its SHA-256 and
renames only its enum so both versions can be linked. The game rules, openings,
seed formula, and budgets are shared: 750 ms for Hard, 350 ms for Easy/Medium.
Optional arguments are `tournament [odd size 5–25] [pairs] [easy|medium|baseline]
[start opening 0–9]`.

Use separate output files for each run. Runs should be sequential on an otherwise
quiet host when comparing timing, because deadlines can change search depth and
move selection under system load.

## Interpretation

The tactical verifier independently scans every empty square for immediate wins
and a reply creating at least two distinct winning continuations. It excludes a
fork if the defender can immediately win. A move surviving this check avoids that
specific short forced-loss pattern; it is not proof of an eventual win or draw.

The cached/uncached comparison requires both searches to finish at the same depth
before comparing their chosen moves. An expired deadline must still return a
legal fallback, and interrupted work must not count as a completed search depth.

These are small, local engine comparisons with fixed openings. They do not measure
human win rates or Elo. Timings cover optimized search computation on the reported
Mac host, excluding app task scheduling and its minimum thinking-display delay.

## Preserved baseline

`baseline/` preserves the original source, harness, JSON/JSONL outputs, and model
prefix from the initial evaluation. Its source and measurement records are kept
unchanged. The archived `run.py` is historical reference; use the current driver
for comparisons with the frozen prior engine. Original top-level JSON/JSONL files
also remain as baseline evidence; post-fix runs are saved under `post-fix/`.
`post-fix/AIEngine.swift` preserves the exact source measured by those runs.
`results.json` contains the combined index and summaries; `summarize.py` validates
complete paired matchsets and source provenance before regenerating it.
