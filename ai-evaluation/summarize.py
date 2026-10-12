#!/usr/bin/env python3
"""Validate completed evaluation logs and write baseline/post-fix summaries."""
import collections
import hashlib
import json
import math
import pathlib
import statistics

HERE = pathlib.Path(__file__).resolve().parent
POST = HERE / "post-fix"


def read_rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def event(path, name):
    rows = [row for row in read_rows(path) if row["event"] == name]
    assert len(rows) == 1, (path, name, len(rows))
    return rows[0]


def latency(values):
    values = sorted(values)
    return {"decisions": len(values), "medianMS": statistics.median(values),
            "p95MS": values[math.ceil(len(values) * .95) - 1], "maxMS": max(values)}


def tournament(path):
    rows = read_rows(path)
    build = next(row for row in rows if row["event"] == "build")
    summary = event(path, "tournament")
    games = [row for row in rows if row["event"] == "game"]
    assert len(games) == summary["games"] == 20
    pairs = collections.defaultdict(set)
    wins = collections.Counter()
    times = collections.defaultdict(list)
    for game in games:
        assert game["hardSide"] not in pairs[game["opening"]]
        pairs[game["opening"]].add(game["hardSide"])
        wins[game["winner"]] += 1
        for decision in game["decisions"]:
            player = "currentHard" if decision["side"] == game["hardSide"] else summary["opponent"]
            times[player].append(decision["ms"])
    assert len(pairs) == 10 and all(sides == {"Black", "White"} for sides in pairs.values())
    assert all(wins[key] == count for key, count in summary["wins"].items())
    draws = wins["draw"]
    result = {"games": len(games), "hardWins": wins["hard"],
              "hardLosses": wins[summary["opponent"]], "draws": draws,
              "drawRate": draws / len(games),
              "hardScoreFraction": (wins["hard"] + draws * .5) / len(games),
              "opponent": summary["opponent"], "pairedOpenings": len(pairs),
              "latency": {key: latency(value) for key, value in times.items()},
              "sourceLog": str(path.relative_to(HERE))}
    return result, build


baseline = json.loads((HERE / "baseline/results.json").read_text())
medium, build = tournament(POST / "hard-vs-medium-15.jsonl")
frozen, frozen_build = tournament(POST / "hard-vs-baseline-15.jsonl")
assert build["engineSHA256"] == frozen_build["engineSHA256"]
assert build["engineSHA256"] == hashlib.sha256((HERE.parent / "gomoku/AIEngine.swift").read_bytes()).hexdigest()
assert build["baselineEngineSHA256"] == baseline["productionEngineSHA256"]
for path in POST.glob("*.jsonl"):
    records = read_rows(path)
    builds = [row for row in records if row["event"] == "build"]
    if builds:
        assert len(builds) == 1 and builds[0]["engineSHA256"] == build["engineSHA256"], path

profiles = [row for row in read_rows(POST / "profile.jsonl") if row["event"] == "profile"]
tactics = [row for row in read_rows(POST / "tactical.jsonl") if row["event"] == "tacticalResult" and row["difficulty"] == "hard"]
cache = [row for row in read_rows(POST / "correctness.jsonl") if row["event"] == "cacheEquivalence"]
assert all(row["agrees"] and row["completedComparableSearches"] for row in cache)
assert all(not row["provenImmediateOrForkLoss"] and row["move"] == "H8" for row in tactics)

summary = {
    "evaluationDate": "2026-10-11", "productionEngineSHA256": build["engineSHA256"],
    "baselineEngineSHA256": build["baselineEngineSHA256"],
    "compiler": build["swiftCompiler"], "host": build["host"], "machine": build["machine"],
    "buildFlags": ["-O", "-swift-version", "5"],
    "methodology": {"productionEngine": "Exact unchanged source; tournaments call computeBestMove directly.",
                    "diagnostics": "Native per-call analyzeMove result; cache controls use SearchOptions.",
                    "gameRules": "Production GameSession; freestyle five or more wins.",
                    "hardBudgetMS": 750, "mediumBudgetMS": 350,
                    "comparisons": "20 games per opponent; ten fixed openings; each color once per opening.",
                    "timingContext": json.loads((POST / "run-context.json").read_text()),
                    "limits": "Small local engine comparison with fixed openings. No human win-rate or Elo claim. Deadline-dependent decisions can vary with host load."},
    "vsCurrentMedium": medium, "vsFrozenPriorHard": frozen,
    "baselineLossAudit": json.loads((POST / "baseline-loss-audit.json").read_text()),
    "basicChecks": event(POST / "basics.jsonl", "basics"),
    "priorHardVsMedium": baseline["selfPlay"],
    "easyMediumEquivalence": event(POST / "difficulty-equivalence.jsonl", "difficultyEquivalence"),
    "tacticalRegression": {"safeMove": "H8", "hard750msFailures": sum(row["provenImmediateOrForkLoss"] for row in tactics if row["budgetMS"] == 750),
                           "hard750msRepetitions": sum(row["budgetMS"] == 750 for row in tactics),
                           "hard750msLatency": latency([row["ms"] for row in tactics if row["budgetMS"] == 750]),
                           "symmetries": event(POST / "tactical-symmetries.jsonl", "tacticalSymmetries"),
                           "proof": "After prior E8, White H8 creates winning cells J8 and H10; all 205 Black replies leave a White win. Current Hard prevents this fork at H8."},
    "cacheEquivalence": {"completedComparisons": len(cache), "allMovesAndScoresAgree": True,
                         "requestedDepths": [row["requestedDepth"] for row in cache]},
    "expiredDeadline": event(POST / "correctness.jsonl", "expiredDeadlineFallback"),
    "searchProfiles": {"positions": len(profiles),
                       "completedDepthCounts": dict(collections.Counter(row["completedDepth"] for row in profiles)),
                       "interruptedSearches": sum(row["interrupted"] for row in profiles),
                       "completedDepths": [row["completedDepth"] for row in profiles],
                       "latency": latency([row["hardMS"] for row in profiles])},
    "verification": json.loads((POST / "verification.json").read_text()),
    "reproductionCommands": ["python3 ai-evaluation/run.py difficulty-equivalence", "python3 ai-evaluation/run.py correctness",
                             "python3 ai-evaluation/run.py tactical", "python3 ai-evaluation/run.py tactical-symmetries",
                             "python3 ai-evaluation/run.py profile", "python3 ai-evaluation/run.py tournament 15 10 medium",
                             "python3 ai-evaluation/run.py tournament 15 10 baseline", "python3 ai-evaluation/audit-losses.py", "python3 ai-evaluation/summarize.py"]
}
(POST / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
index = {"evaluationDate": summary["evaluationDate"], "status": "post-fix evaluation complete",
         "baselineResults": "baseline/results.json", "postFixResults": "post-fix/results.json",
         "baseline": baseline, "postFix": summary}
(HERE / "results.json").write_text(json.dumps(index, indent=2) + "\n")
print(json.dumps({"vsMedium": medium, "vsPriorHard": frozen}, indent=2))
