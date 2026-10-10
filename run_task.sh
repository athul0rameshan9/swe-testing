#!/usr/bin/env bash
# Run mini-swe-agent (GPT-4o on Azure) on ONE SWE-bench Verified task.
#
# Usage:   ./run_task.sh <instance_id>
# Example: ./run_task.sh sympy__sympy-15599
#
# Output goes to results/<instance_id>/:
#   <instance_id>.traj.json   full trajectory (every step the agent took)
#   patch.diff                the final patch the agent submitted
#   run.log                   everything printed during the run
#   summary.txt               exit status, steps, time, estimated cost
#
# Runs a single task, so nothing happens in parallel. To run every task in
# tasks.txt one after another, see the loop at the bottom of this file.

set -euo pipefail
cd "$(dirname "$0")"

ID="${1:-}"
if [[ -z "$ID" ]]; then
    echo "Usage: $0 <instance_id>   e.g. $0 sympy__sympy-15599" >&2
    exit 1
fi

# Load .env into the environment without printing anything.
if [[ ! -f .env ]]; then
    echo "No .env file found next to this script." >&2
    exit 1
fi
set -a
source .env
set +a
for var in AZURE_API_KEY AZURE_API_BASE AZURE_API_VERSION AZURE_DEPLOYMENT_NAME; do
    if [[ -z "${!var:-}" ]]; then
        echo "$var is empty in .env" >&2
        exit 1
    fi
done

OUT="results/$ID"
TRAJ="$OUT/$ID.traj.json"
if [[ -e "$TRAJ" ]]; then
    echo "$TRAJ already exists. Move or delete $OUT first if you want to re-run." >&2
    exit 1
fi
mkdir -p "$OUT"

# Pull the task's Docker image first. mini-swe-agent gives up on pulls after
# 120 s, and these images are ~1 GB, so do it here without a time limit.
# Same naming rule as mini-swe-agent: "__" becomes "_1776_", all lowercase.
IMAGE="swebench/sweb.eval.x86_64.${ID//__/_1776_}:latest"
IMAGE="${IMAGE,,}"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Pulling $IMAGE (about 1 GB download) ..."
    docker pull "$IMAGE"
fi

echo "Running mini-swe-agent on $ID (started $(date '+%Y-%m-%d %H:%M:%S'))"
START=$(date +%s)

# --yolo             run the agent's commands without asking for approval
# --exit-immediately don't ask "add another task?" when the agent finishes
# < /dev/null        no keyboard input, so limits stop the run instead of prompting
set +e
./venv/bin/mini-extra swebench-single \
    --subset verified --split test \
    -c azure_gpt4o.yaml \
    -i "$ID" \
    -o "$TRAJ" \
    --yolo --exit-immediately \
    < /dev/null 2>&1 | tee "$OUT/run.log"
STATUS=${PIPESTATUS[0]}
set -e

SECONDS_TAKEN=$(( $(date +%s) - START ))

# Pull the patch and stats out of the trajectory.
./venv/bin/python - "$ID" "$TRAJ" "$OUT" "$SECONDS_TAKEN" "$STATUS" <<'EOF'
import json
import sys
from pathlib import Path

instance_id, traj_path, out, seconds, status = sys.argv[1:]
traj_path, out, seconds = Path(traj_path), Path(out), int(seconds)

if not traj_path.exists():
    print(f"\nNo trajectory was written (mini-extra exit code {status}). See {out}/run.log")
    sys.exit(1)

info = json.loads(traj_path.read_text())["info"]
patch = info.get("submission") or ""
(out / "patch.diff").write_text(patch)

summary = "\n".join([
    f"instance_id:        {instance_id}",
    f"exit_status:        {info.get('exit_status') or 'unknown'}",
    f"steps (API calls):  {info['model_stats']['api_calls']}",
    f"wall time:          {seconds // 60}m {seconds % 60}s ({seconds}s)",
    f"est. cost (USD):    {info['model_stats']['instance_cost']:.4f}  (LiteLLM list-price estimate)",
    f"patch:              {len(patch.splitlines())} lines -> {out}/patch.diff",
    f"mini-extra exit:    {status}",
])
(out / "summary.txt").write_text(summary + "\n")
print("\n=== Summary ===\n" + summary)
EOF

# To run every task in tasks.txt, one at a time:
#   for id in $(grep -vE '^\s*(#|$)' tasks.txt); do ./run_task.sh "$id"; done
