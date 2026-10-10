#!/usr/bin/env bash
# Grade the agent's patches with the official SWE-bench harness.
#
# Usage: ./grade.sh
#
# 1. Collects the patch from every results/<id>/<id>.traj.json into preds.json
# 2. Runs the SWE-bench harness with one worker (one test container at a time)
# 3. Prints PASS / FAIL for each task
#
# Uses the SWE-bench/SWE-bench_Verified dataset: swebench 5.x needs the image and
# eval-script fields that only that copy has (princeton-nlp/SWE-bench_Verified
# lacks them and crashes with KeyError: 'image').
#
# The harness skips tasks it has already graded under this run ID. To re-grade a
# task after re-running it, delete logs/run_evaluation/azure-gpt4o/*/<id>/ first.

set -euo pipefail
cd "$(dirname "$0")"

RUN_ID="azure-gpt4o"
MODEL_NAME="mini-swe-agent__azure-gpt-4o"

# 1. Build preds.json from the trajectories.
./venv/bin/python - "$MODEL_NAME" <<'EOF'
import json
import sys
from pathlib import Path

model_name = sys.argv[1]
preds = {}
for traj in sorted(Path("results").glob("*/*.traj.json")):
    instance_id = traj.parent.name
    info = json.loads(traj.read_text())["info"]
    preds[instance_id] = {
        "instance_id": instance_id,
        "model_name_or_path": model_name,
        "model_patch": info.get("submission") or "",
    }
if not preds:
    sys.exit("No trajectories found in results/. Run ./run_task.sh <id> first.")
Path("preds.json").write_text(json.dumps(preds, indent=2))
print(f"Wrote preds.json with {len(preds)} prediction(s): {', '.join(preds)}")
EOF

# 2. Run the official harness.
./venv/bin/python -m swebench.harness.run_evaluation \
    --dataset_name SWE-bench/SWE-bench_Verified \
    --predictions_path preds.json \
    --max_workers 1 \
    --run_id "$RUN_ID" \
    --report_dir results

# 3. Print a pass/fail line per task.
./venv/bin/python - "$MODEL_NAME" "$RUN_ID" <<'EOF'
import json
import sys
from pathlib import Path

model_name, run_id = sys.argv[1:]
report = json.loads(Path(f"results/{model_name}.{run_id}.json").read_text())

def status(instance_id):
    if instance_id in report["resolved_ids"]:
        return "PASS"
    if instance_id in report["empty_patch_ids"]:
        return "FAIL (no patch submitted)"
    if instance_id in report["error_ids"]:
        return "ERROR (grading crashed, see logs)"
    if instance_id in report["unresolved_ids"]:
        return "FAIL"
    return "NOT GRADED"

def test_counts(instance_id):
    path = Path("logs/run_evaluation") / run_id / model_name / instance_id / "report.json"
    if not path.exists():
        return ""
    tests = json.loads(path.read_text())[instance_id].get("tests_status", {})
    parts = []
    for kind in ("FAIL_TO_PASS", "PASS_TO_PASS"):
        t = tests.get(kind, {})
        ok, bad = len(t.get("success", [])), len(t.get("failure", []))
        parts.append(f"{kind} {ok}/{ok + bad}")
    return "  [" + ", ".join(parts) + "]"

print("\n=== Results ===")
for instance_id in report["submitted_ids"]:
    print(f"{instance_id:40s} {status(instance_id)}{test_counts(instance_id)}")
print(f"\nResolved {report['resolved_instances']} of {report['submitted_instances']} submitted.")
EOF
