#!/usr/bin/env python3
"""Compile the current production engine with a standalone evaluation harness."""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
engine = (ROOT / "gomoku/AIEngine.swift").read_text()
models = (ROOT / "gomoku/Models.swift").read_text().split("enum HapticEvent:")[0]
models = models.replace("import Combine\n", "")
instrumented = engine.replace("enum AIEngine {", """enum InstrumentedAIEngine {
    static var nodes = 0
    static var cacheHits = 0
    static var completedDepth = 0
    static var verifiedCompletedDepth = 0
    static var committedAfterTimeout = false
    static var rootMovesCompleted = 0
    static var timedOut = false
    static func reset() {
        nodes = 0; cacheHits = 0; completedDepth = 0
        verifiedCompletedDepth = 0
        committedAfterTimeout = false; rootMovesCompleted = 0; timedOut = false
    }
    static func timeoutProbe(board: [CellState], size: Int, root: Player) -> [String: Double] {
        var liveTable: [SearchKey: Double] = [:]
        var expiredTable: [SearchKey: Double] = [:]
        let live = negamax(board: board, size: size, player: root.next, root: root,
            depth: 0, alpha: -.infinity, beta: .infinity,
            deadline: .now.advanced(by: .seconds(30)), table: &liveTable)
        let expired = negamax(board: board, size: size, player: root.next, root: root,
            depth: 0, alpha: -.infinity, beta: .infinity,
            deadline: .now.advanced(by: .seconds(-1)), table: &expiredTable)
        return ["live": live, "expired": expired]
    }
""")
instrumented = instrumented.replace(
    "if completedDepth { best = depthBest }",
    "if completedDepth { best = depthBest; Self.completedDepth = depth; committedAfterTimeout = timedOut || .now >= deadline; if !committedAfterTimeout { verifiedCompletedDepth = depth } }",
)
instrumented = instrumented.replace(
    "for item in ordered {",
    "rootMovesCompleted = 0\n            for item in ordered {",
)
no_cache = engine.replace("enum AIEngine {", "enum NoCacheAIEngine {")
no_cache = no_cache.replace("if let cached = table[key] { return cached }", "// Evaluation control: no cache lookup.")
no_cache = no_cache.replace("table[key] = value", "// Evaluation control: no cache write.")
no_cache = no_cache.replace("let key = SearchKey(hash: boardHash(board), player: player, depth: depth)", "let key = SearchKey(hash: boardHash(board), player: player, depth: depth)\n        _ = key")
instrumented = instrumented.replace(
    "if score > depthScore {",
    "rootMovesCompleted += 1\n                if score > depthScore {",
)
instrumented = instrumented.replace(
    "if Task.isCancelled || .now >= deadline { return evaluateBoard(board, size, root) }",
    "nodes += 1\n        if Task.isCancelled || .now >= deadline { timedOut = true; return evaluateBoard(board, size, root) }",
)
instrumented = instrumented.replace(
    "if let cached = table[key] { return cached }",
    "if let cached = table[key] { cacheHits += 1; return cached }",
)
instrumented = instrumented.replace(
    "if Task.isCancelled || .now >= deadline { break }",
    "if Task.isCancelled || .now >= deadline { timedOut = true; break }",
)

with tempfile.TemporaryDirectory(prefix="gomoku-ai-evaluation-") as temp:
    temp = pathlib.Path(temp)
    (temp / "Models.swift").write_text(models)
    (temp / "AIEngine.swift").write_text(engine)
    (temp / "InstrumentedAIEngine.swift").write_text(instrumented)
    (temp / "NoCacheAIEngine.swift").write_text(no_cache)
    binary = temp / "evaluate"
    subprocess.run([
        "swiftc", "-O", "-swift-version", "5",
        str(temp / "Models.swift"), str(temp / "AIEngine.swift"),
        str(temp / "InstrumentedAIEngine.swift"), str(temp / "NoCacheAIEngine.swift"), str(HERE / "Evaluation.swift"),
        "-o", str(binary),
    ], check=True)
    print(json.dumps({"event": "build", "optimization": "-O", "engineSHA256": hashlib.sha256(engine.encode()).hexdigest(), "args": sys.argv[1:]}), flush=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)
