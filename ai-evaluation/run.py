#!/usr/bin/env python3
"""Compile the current, unchanged production engine and its frozen prior version.

Search diagnostics come from AIEngine.analyzeMove's per-call result. Tournament
moves call computeBestMove directly without instrumentation or search rewrites.
"""
import hashlib
import json
import pathlib
import platform
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
BASELINE_SHA256 = "331303c9ad7e6ffd74cc5d7969ad058d808fc587811550f06b0901c1d8108b42"


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


engine = (ROOT / "gomoku/AIEngine.swift").read_text()
models = (ROOT / "gomoku/Models.swift").read_text().split("enum HapticEvent:")[0]
models = models.replace("import Combine\n", "")
baseline = (HERE / "baseline/AIEngine.swift").read_text()
if sha256(baseline) != BASELINE_SHA256:
    raise RuntimeError("The frozen baseline source no longer matches the evaluated production engine")
if baseline.count("enum AIEngine {") != 1:
    raise RuntimeError("Expected exactly one baseline engine declaration")
# Rename only its namespace so both exact engine implementations can be linked.
baseline_namespace = baseline.replace("enum AIEngine {", "enum BaselineAIEngine {", 1)
harness = (HERE / "Evaluation.swift").read_text()
swift_version = subprocess.check_output(["swiftc", "--version"], text=True).strip()

with tempfile.TemporaryDirectory(prefix="gomoku-ai-evaluation-") as temp:
    temp = pathlib.Path(temp)
    (temp / "Models.swift").write_text(models)
    (temp / "AIEngine.swift").write_text(engine)
    (temp / "BaselineAIEngine.swift").write_text(baseline_namespace)
    binary = temp / "evaluate"
    subprocess.run([
        "swiftc", "-O", "-swift-version", "5",
        str(temp / "Models.swift"), str(temp / "AIEngine.swift"),
        str(temp / "BaselineAIEngine.swift"), str(HERE / "Evaluation.swift"),
        "-o", str(binary),
    ], check=True)
    print(json.dumps({
        "event": "build", "optimization": "-O", "swiftLanguageVersion": "5",
        "swiftCompiler": swift_version, "host": platform.platform(),
        "machine": platform.machine(), "engineSHA256": sha256(engine),
        "baselineEngineSHA256": BASELINE_SHA256, "modelsPrefixSHA256": sha256(models),
        "harnessSHA256": sha256(harness), "driverSHA256": sha256(pathlib.Path(__file__).read_text()),
        "productionSourceChangedForBenchmark": False,
        "args": sys.argv[1:],
    }), flush=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)
