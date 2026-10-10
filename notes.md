# SWE-bench experiment log: mini-swe-agent + GPT-4o on Azure OpenAI

Machine: Pop!_OS 22.04 laptop. Log started 2026-10-02.

---

## Step 1: Check the system

**What:** Read-only checks of OS, Python, disk, RAM, and Docker.

**Commands:**
```bash
lsb_release -ds; uname -r
python3 --version
df -h .
free -h
nproc
docker --version; docker info; groups
docker info --format '{{.DockerRootDir}}'; df -h /var/lib/docker
```

**Result:**

| Check | Result | Needed | OK? |
|---|---|---|---|
| OS | Pop!_OS 22.04 LTS (kernel 7.0.11) | Ubuntu-based Linux | yes |
| Python | 3.10.12, venv module works | 3.10+ | yes (just barely) |
| Project disk (`/dev/sda1`) | 539 GB free | none | yes |
| Docker image disk (`/`, `/var/lib/docker`) | 54 GB free | ~50 GB | enough, but tight |
| RAM | 14 GB total, ~6 GB available, 18 GB swap | 8 GB+ | yes |
| CPU | 16 cores | none | yes |
| Docker | 29.6.2, daemon running, user already in `docker` group | none | yes |

**Gotcha worth mentioning in the article:** `df -h .` shows the disk your
*project* is on, but Docker stores images in `/var/lib/docker`, which can be a
different disk. Check both. Here the project disk had 539 GB free but the
Docker disk only had 54 GB.

**Errors:** none. **Time:** ~1 min.

---

## Step 2: Docker

**What:** Docker was already installed (v29.6.2) and the user was already in
the `docker` group, so no install, no sudo, and no log-out/log-in were needed.
Just verified it works.

**Command:**
```bash
docker run --rm hello-world
```

**Result:** Printed "Hello from Docker!". Docker works without sudo.

**For a fresh machine (not needed here):** you'd install Docker Engine using
Docker's apt repository, then run `sudo usermod -aG docker $USER` and log out
and back in so the group change takes effect.

**Errors:** none. **Time:** ~7 s.

---

## Step 3: Python virtual environment + packages

**What:** Created a private Python environment (`venv/`) and installed the
agent, the grader, and the .env loader.

**Commands:**
```bash
python3 -m venv venv
./venv/bin/python -m pip install --upgrade pip
./venv/bin/python -m pip install mini-swe-agent swebench python-dotenv
./venv/bin/mini-extra --help     # sanity check
```

**Result:**

| Package | Version |
|---|---|
| mini-swe-agent | 2.4.6 |
| swebench | 5.0.2 |
| python-dotenv | 1.2.4 |
| litellm (pulled in by mini-swe-agent) | 1.103.2 |

venv size: 643 MB. `mini-extra` lists the `swebench` and `swebench-single`
sub-commands.

**Notes:**
- The folder name has a space ("swe testing"). pip handles it with a special
  shebang trick, so the venv commands still work. Always quote the path.
- mini-swe-agent prints `Loading global config from ~/.config/mini-swe-agent/.env`.
  That file did not exist here, so nothing overrides the project's settings.
  If it exists on your machine, check it, because it can set a default model.

**Errors:** none. **Time:** ~1 min 45 s (install).

---

## Step 4: .env secrets file + .gitignore

**What:** Created `.env` with empty placeholders (permissions 600, owner-only)
and a `.gitignore` that excludes `.env`, `venv/`, `results/`, and `logs/`
(the SWE-bench grader writes `logs/`).

**Commands:**
```bash
# .env written with placeholders, then:
chmod 600 .env
```

`.env` variables:
```
AZURE_API_KEY=
AZURE_API_BASE=          # https://<resource>.openai.azure.com/
AZURE_API_VERSION=       # e.g. 2024-10-21
AZURE_DEPLOYMENT_NAME=   # the name you gave the deployment
MSWEA_COST_TRACKING=ignore_errors
```

**Why these names:** LiteLLM (which mini-swe-agent uses to talk to models)
automatically reads `AZURE_API_KEY`, `AZURE_API_BASE`, and `AZURE_API_VERSION`
from the environment. The model name must be `azure/<deployment-name>`, using
your deployment name, not "gpt-4o".

**Where to find each value (Azure AI Foundry, ai.azure.com):**
1. Open your project, then **Models + endpoints** in the left menu.
2. Click your GPT-4o deployment. The details page shows:
   - **Name**: goes in `AZURE_DEPLOYMENT_NAME`
   - **Target URI**, e.g.
     `https://myres.openai.azure.com/openai/deployments/my-gpt4o/chat/completions?api-version=2025-01-01-preview`
     - the part up to and including `.azure.com/` goes in `AZURE_API_BASE`
     - the part after `api-version=` goes in `AZURE_API_VERSION`
   - **Key** (copy icon): goes in `AZURE_API_KEY`
3. Or, in the Azure portal (portal.azure.com): open your Azure OpenAI / AI
   Foundry resource, then **Resource Management > Keys and Endpoint**, which
   shows KEY 1 and the Endpoint.

**Endpoint types:**
- `https://<name>.openai.azure.com/` or `https://<name>.cognitiveservices.azure.com/`: use the `azure/` provider.
- `https://<name>.services.ai.azure.com/models`: this is the Azure AI model
  inference endpoint, which needs the `azure_ai/` provider instead.

**Errors:** none. **Time:** ~1 min (plus however long the portal takes).

---

## Step 5: Test the Azure connection

**What:** Before involving the agent, `test_azure.py` loads `.env` and sends
"Say hello" to the deployment through LiteLLM (the same library
mini-swe-agent uses). It never prints the key and scrubs it from any error
message.

**Command:**
```bash
./venv/bin/python test_azure.py
```

**Result:** Worked on the first try.
```
Provider:    azure
Model:       azure/gpt-4o
Endpoint:    https://<resource>.cognitiveservices.azure.com/
API version: 2024-12-01-preview
Reply:       'Hello! 😊 How can I assist you today?'
Model used:  gpt-4o-2024-11-20
Tokens:      9 in / 10 out
Time:        3.0s
```

**Notes:**
- The endpoint is `*.cognitiveservices.azure.com` (the newer AI Foundry
  resource style), not `*.openai.azure.com`. Both use LiteLLM's `azure/`
  provider. Only `*.services.ai.azure.com/models` would need `azure_ai/`.
- The deployment happens to be named `gpt-4o`, so the model string is
  `azure/gpt-4o`. Azure reports the actual model version, `gpt-4o-2024-11-20`,
  which is worth stating in the article for reproducibility.

**Errors:** none. **Time:** ~3 s.

---

## Step 6: Agent config `azure_gpt4o.yaml`

**What:** Copied mini-swe-agent's default SWE-bench config and changed only
the model settings and the step limit.

**Finding the default:** `swebench-single` uses
`venv/lib/python3.10/site-packages/minisweagent/config/benchmarks/swebench.yaml`
(set as `DEFAULT_CONFIG_FILE` in `minisweagent/run/benchmarks/swebench_single.py`).

**Commands:**
```bash
cp venv/lib/python3.10/site-packages/minisweagent/config/benchmarks/swebench.yaml azure_gpt4o.yaml
# then edited it (diff below)
```

**Diff vs. the default:**
```diff
-  step_limit: 250
+  step_limit: 50
   cost_limit: 3.
 ...
-  model_name: "anthropic/claude-sonnet-4-5-20250929"
+  model_name: "azure/gpt-4o"
+  cost_tracking: "ignore_errors"
   model_kwargs:
     drop_params: true
     parallel_tool_calls: true
+    temperature: 0.0
```
`drop_params` and `parallel_tool_calls` were kept from the default.

**Verified:** Loaded the file with mini-swe-agent's own config loader. It
reported step_limit 50, model azure/gpt-4o, temperature 0.0, docker environment.

**Things learned from reading the source (useful for the article):**
- `swebench-single` starts an **interactive** agent by default, which asks you
  to approve every command. For unattended runs, pass `--yolo` (no approval)
  and `--exit-immediately` (don't ask "add another task?" at the end).
- With no terminal attached (stdin from `/dev/null`), hitting the step limit
  stops cleanly with exit status `LimitsExceeded` instead of prompting for a
  new limit.
- `cost_tracking: ignore_errors` does **not** turn cost tracking off. It only
  stops the run from crashing when LiteLLM doesn't know a model's price.
  LiteLLM *does* know `azure/gpt-4o` ($2.50 per 1M input tokens, $10 per 1M
  output), so mini-swe-agent shows a local **estimate**. The real bill is in
  Azure Cost Management.
- `cost_limit: 3.` (USD) stays as a safety net: the agent stops if the
  estimated cost of one task passes $3.
- mini-swe-agent does **not** read the project's `.env` by itself (only
  `~/.config/mini-swe-agent/.env`), so `run_task.sh` must load it.

**Errors:** none. **Time:** ~5 min (mostly reading the source).

---

## Step 7: Task list `tasks.txt`

**What:** A plain list of SWE-bench Verified instance IDs, one per line, with
`#` comments allowed.

**Result:** Active task: `sympy__sympy-15599`.

Checked against the dataset (`princeton-nlp/SWE-Bench_Verified`, split
`test`, 500 tasks):
- repo `sympy/sympy`, version 1.4, difficulty "15 min - 1 hour"
- Problem: `Mod(3*i, 2)` should reduce to `Mod(i, 2)` but stays unchanged.
- Graded by one FAIL_TO_PASS test: `test_Mod`

Verified difficulty mix: 194 "<15 min fix", 261 "15 min - 1 hour",
42 "1-4 hours", 3 ">4 hours". Some easy candidates from other repos are listed
as comments in `tasks.txt`.

**Errors:** none (the Hugging Face "unauthenticated requests" warning is
harmless; it just means slower downloads). **Time:** ~1 min.

---

## Step 8: Runner script `run_task.sh`

**What:** One script that runs the agent on one task and saves everything to
`results/<id>/`. It runs a single task, so there are no parallel workers.

**What it does, in order:**
1. Loads `.env` with `set -a; source .env; set +a` (nothing printed) and
   checks that the four Azure values aren't empty.
2. Refuses to overwrite an existing `results/<id>/<id>.traj.json`.
3. Runs `docker pull` for the task image if it isn't already on the machine.
   (Image name: `swebench/sweb.eval.x86_64.<id with __ replaced by _1776_>:latest`.)
   This step exists because mini-swe-agent's own pull **times out after
   120 s**, and these images are ~1 GB.
4. Runs:
   ```bash
   ./venv/bin/mini-extra swebench-single --subset verified --split test \
       -c azure_gpt4o.yaml -i <id> -o results/<id>/<id>.traj.json \
       --yolo --exit-immediately < /dev/null 2>&1 | tee results/<id>/run.log
   ```
5. Reads the trajectory and writes `patch.diff` and `summary.txt` (exit status,
   steps, wall time, estimated cost).

**Run all tasks one at a time:**
```bash
for id in $(grep -vE '^\s*(#|$)' tasks.txt); do ./run_task.sh "$id"; done
```

**Verified:** `bash -n` syntax check passed; running it with no ID prints the
usage message; the image name for sympy__sympy-15599 comes out as
`swebench/sweb.eval.x86_64.sympy_1776_sympy-15599:latest`. Docker Hub lists
that image at **1.07 GB** compressed.

### Rate limits (HTTP 429)

Azure's response headers on a test call showed this deployment's limits:
```
x-ratelimit-limit-tokens: 100000     (per 60 s, i.e. 100K tokens per minute)
x-ratelimit-limit-requests: 600
```
- An agent step resends the whole conversation, so late steps can be 30-50K
  tokens each. A few fast steps in a row can hit 100K TPM and get a 429.
- mini-swe-agent retries failed model calls automatically: up to 10 attempts,
  waiting 4 to 60 s with exponential backoff (`minisweagent/models/utils/retry.py`,
  configurable with `MSWEA_MODEL_RETRY_STOP_AFTER_ATTEMPT`). Short 429 bursts
  just slow the run down.

**How to raise the tokens-per-minute (TPM) limit in Azure AI Foundry:**
1. ai.azure.com, open the project, then **Models + endpoints**.
2. Select the GPT-4o deployment, click **Edit**, and move the
   **Tokens per Minute Rate Limit** slider up (as far as your remaining quota
   allows). Save. Requests-per-minute scales with it automatically.
3. If the slider is already at the maximum, open **Management center > Quota**
   to see how much quota is used in that region and subscription, and use
   **Request quota increase**. A **Global Standard** deployment usually has
   much more quota than a regional **Standard** one.

**Errors:** none. **Time:** ~10 min (mostly reading mini-swe-agent's source).

---

## Pre-flight finding (before Step 9): grader dataset name

**Problem found before running anything:** swebench **5.0.2** needs four
extra fields on each task: `image`, `log_parser`, `eval_type`, `eval_script`
(see `swebench/harness/utils.py`, `make_test_spec`). Checked both dataset names:

| Dataset | Rows | Has the 4 fields? |
|---|---|---|
| `princeton-nlp/SWE-bench_Verified` (old name, used in many tutorials) | 500 | **no**, so grading would crash with `KeyError: 'image'` |
| `SWE-bench/SWE-bench_Verified` (official org) | 500 | **yes** |

**Decision:** `grade.sh` uses `--dataset_name SWE-bench/SWE-bench_Verified`.
Same 500 tasks; just the maintained copy.

**Good news:** for sympy__sympy-15599 that dataset's `image` field is
`swebench/sweb.eval.x86_64.sympy_1776_sympy-15599:latest`, the same image the
agent uses. The grader reuses it, so there's one ~1 GB download per task, not
two. The grader removes only its containers afterwards, not the image.

**Also noted:** in swebench 5 the old `--namespace`, `--cache_level`, and
`--clean` flags are gone. Images are pulled from Docker Hub by default.

---

## Step 9: First real run, one task (sympy__sympy-15599)

**What:** Ran the agent on one task, end to end.

**Command:**
```bash
./run_task.sh sympy__sympy-15599
```

**Where things were saved:** `results/sympy__sympy-15599/`

| File | What it is |
|---|---|
| `sympy__sympy-15599.traj.json` (348 KB) | full trajectory: every message, command, and output |
| `patch.diff` | the submitted patch (**empty**, see below) |
| `run.log` (69 KB) | console output of the run |
| `summary.txt` | the summary below |

**Result:**
```
exit_status:        LimitsExceeded
steps (API calls):  50
wall time:          4m 32s (agent only)
est. cost (USD):    0.6703
patch:              0 lines
```

**Pipeline worked, but the agent did not solve the task.** It hit the 50-step
limit without submitting a patch, which counts as a failure.

**Timing:**
- Docker image pull (1.07 GB download, 2.76 GB on disk): **~15 min**
  (one-time per task; most of the total)
- Agent: **4 min 32 s** for 50 steps (~5 s per step)
- Total: **19 min 34 s**

**Tokens (from the trajectory):**
- prompt: 460,469 tokens, of which **450,688 (98%) were cached** by Azure
- completion: 8,251 tokens
- largest single prompt: 14,997 tokens (well under the 100K TPM limit)
- **No 429 rate-limit errors.**
- Cost: 9,781 uncached input tokens at $2.50/M, plus 450,688 cached at $1.25/M,
  plus 8,251 output at $10/M, which comes to **$0.67** (matches mini-swe-agent's estimate). Without
  caching it would have been about $1.23. Prompt caching halves the cost because
  every step resends the same conversation with one more message on the end.

**What the agent did (from the trajectory):**
- Steps 1-3: found `sympy/core/mod.py`, read it, and tried to paste the fix
  suggested in the issue using a one-line `sed -i '/pattern/i \ ...'` insert.
- Steps 4-9: its test still showed `Mod(3*i, 2)`. It **never re-read the file**
  to check what `sed` had actually written.
- Steps 10-27: added debug `print` lines with more `sed` one-liners, which
  broke Python indentation. It spent ~18 steps fixing `IndentationError`s it
  had caused itself.
- Steps 28-50: more debug prints and a second fix attempt, then ran out of steps.

**Takeaway for the article:** the failure was in *editing*, not *understanding*.
The issue text even contains the fix. GPT-4o struggled to make a multi-line
Python edit with `sed` and didn't verify its edits. A 50-step limit leaves no
room to recover from that.

**Security check:** searched every output file for the API key: 0 matches.
The Docker container was removed after the run (the image is kept for grading).
Disk left on `/`: 51 GB.

**How to check the real cost in Azure:**
- Near-real-time token counts: Azure portal, your Azure OpenAI / Foundry
  resource, **Monitoring > Metrics**, metric "Processed Prompt Tokens" /
  "Generated Completion Tokens" (or the deployment's **Metrics** tab in
  ai.azure.com).
- Money: Azure portal, **Cost Management + Billing > Cost Management > Cost
  analysis**. Scope: your subscription; filter **Resource** to your
  Azure OpenAI resource; group by **Meter** to see input / cached input /
  output tokens separately. Cost data usually lags **8-24 hours**.

**Errors:** none from the pipeline. **Time:** ~20 min.

---

## Step 10: Grading with the official SWE-bench harness (`grade.sh`)

**What:** `grade.sh` collects the patch from every
`results/<id>/<id>.traj.json` into `preds.json`, runs the official harness
with one worker, and prints PASS/FAIL per task.

**Command inside grade.sh:**
```bash
./venv/bin/python -m swebench.harness.run_evaluation \
    --dataset_name SWE-bench/SWE-bench_Verified \
    --predictions_path preds.json --max_workers 1 --run_id azure-gpt4o \
    --report_dir results
```
Differences from the original plan:
- `SWE-bench/SWE-bench_Verified` instead of `princeton-nlp/SWE-bench_Verified`
  (swebench 5 needs fields only the official copy has; see the pre-flight note).
- `--report_dir results` so the summary JSON lands in `results/` (gitignored)
  instead of the project root.

**Result for the GPT-4o run:**
```
Wrote preds.json with 1 prediction(s): sympy__sympy-15599
No instances to run.
Instances with empty patches: 1
=== Results ===
sympy__sympy-15599                       FAIL (no patch submitted)
Resolved 0 of 1 submitted.
```
With an empty patch the harness doesn't start a container at all ("No
instances to run"). It just counts it as unresolved. Took 12 s.

### Sanity check: grade the official ("gold") fix

Because the agent's patch was empty, the grader never actually ran tests. To
prove the grading setup works, graded the human-written fix for the same task:
```bash
./venv/bin/python -m swebench.harness.run_evaluation \
    --dataset_name SWE-bench/SWE-bench_Verified --predictions_path gold \
    -i sympy__sympy-15599 --max_workers 1 --run_id gold-check --report_dir results
```
**Always pass `-i`** with `gold`, or it grades all 500 tasks (and downloads
hundreds of GB of images).

Result: **resolved: True**. FAIL_TO_PASS 1/1 passed (`test_Mod`),
PASS_TO_PASS 80/80 passed. Took 27 s. No extra download (reused the image),
no API cost.

So the grader works on this machine, and the FAIL above is the agent's, not the
setup's.

**Where grading output goes:**
- `results/mini-swe-agent__azure-gpt-4o.azure-gpt4o.json`: run summary
- `logs/run_evaluation/azure-gpt4o/<model>/<id>/`: per-task test logs and `report.json`
- "Unremoved images: 1" in the output is expected. The image is kept on purpose.

**Gotcha:** the harness **skips tasks it has already graded** under the same
`--run_id`. After re-running a task, delete
`logs/run_evaluation/azure-gpt4o/*/<id>/` before grading again (or use a new
run ID).

**Errors:** none. **Time:** ~1 min total.

---

## Step 11: Results table `results.md`

**What:** Created `results.md` with columns task ID | passed? | steps | time |
notes, filled in for sympy__sympy-15599 (FAIL, 50 steps, 4m 32s).
Add one row per task after running `./grade.sh`.

**Errors:** none. **Time:** ~2 min.

---

## Final project layout

```
.env                 secrets (gitignored, chmod 600)
.gitignore           .env, venv/, results/, logs/
venv/                Python environment (643 MB)
test_azure.py        Azure connection smoke test
azure_gpt4o.yaml     agent config (model + 50-step limit)
tasks.txt            task IDs to run
run_task.sh          run the agent on one task
grade.sh             build preds.json + grade + print PASS/FAIL
preds.json           predictions written by grade.sh
results/             trajectories, patches, logs, grading reports
logs/                SWE-bench harness logs
results.md           results table for the article
notes.md             this log
```
