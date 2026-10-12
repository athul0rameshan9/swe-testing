# SWE-bench with mini-swe-agent + GPT-4o (Azure OpenAI)

A small, reproducible harness for running [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent) on [SWE-bench Verified](https://www.swebench.com/) tasks, using a GPT-4o deployment on Azure OpenAI, and grading the results with the official SWE-bench harness.

The workflow has two steps:

1. **Run** the agent on a task. It works inside the task's Docker container and produces a patch.
2. **Grade** the patch by running the task's tests in a fresh container.

## Results so far

Setup: mini-swe-agent 2.4.6, `gpt-4o-2024-11-20`, temperature 0.0, step limit 50, graded with swebench 5.0.2.

| Task | Resolved | Steps | Notes |
|---|---|---|---|
| `sympy__sympy-15599` | No | 50 (limit hit) | No patch submitted. Est. cost about $0.67. |
| `pallets__flask-5014` | **Yes** | 11 | Est. cost about $0.11. |
| `psf__requests-1142` | No | 50 (limit hit) | No patch submitted. Est. cost about $1.04. |
| `django__django-10097` | No | 50 (limit hit) | No patch submitted. Est. cost about $0.92. The gold patch also fails here (environment issue). |
| `pytest-dev__pytest-10081` | No | 15 | Patch fixed the target test but broke an existing one. Est. cost about $0.17. |
| `scikit-learn__scikit-learn-13439` | No | 50 (limit hit) | No patch submitted. Est. cost about $1.21. |
| `astropy__astropy-14309` | **Yes** | 9 | Est. cost about $0.08. |

**Score: 2 / 7 (29%)**, est. cost $4.20 in total. All four runs that hit the step limit got stuck repeating the same few commands after a broken `sed`/`echo` edit. The grader was checked by grading the official gold patches for the empty-patch tasks: they pass, except for `django__django-10097`, which this Docker image can't pass at all. See [results.md](results.md) for details.

## Requirements

- Linux with **Docker** installed and usable without sudo (your user in the `docker` group)
- **Python 3.10+**
- An **Azure OpenAI** resource with a GPT-4o deployment
- Disk space: each task image is about 1 GB, and Docker's storage (`/var/lib/docker`) may be on a different disk than this project, so check both
- Roughly 8 GB of RAM

## Setup

```bash
# 1. Python environment and packages
python3 -m venv venv
./venv/bin/python -m pip install --upgrade pip
./venv/bin/python -m pip install mini-swe-agent swebench python-dotenv

# 2. Azure credentials
cp .env.example .env   # or create .env by hand, see below
```

Create a `.env` file next to the scripts. It is git-ignored, so never commit it.

```dotenv
AZURE_API_KEY=<key 1 or key 2 from your Azure resource>
AZURE_API_BASE=https://<my-resource>.openai.azure.com/
AZURE_API_VERSION=2024-10-21
AZURE_DEPLOYMENT_NAME=<the name you gave your GPT-4o deployment>
MSWEA_COST_TRACKING=ignore_errors
```

Notes:

- `AZURE_API_BASE` must be just the endpoint, not the full "Target URI" with `/openai/deployments/...` and `?api-version=...`. Put the version in `AZURE_API_VERSION`.
- The deployment name is whatever *you* chose, not necessarily `gpt-4o`.
- `azure_gpt4o.yaml` refers to the model as `azure/gpt-4o`. If your deployment has a different name, update `model_name` there.

### Check the connection

```bash
./venv/bin/python test_azure.py
```

This sends one tiny request and prints `SUCCESS` if the deployment is reachable. It never prints the API key.

## Usage

### Run the agent on one task

```bash
./run_task.sh sympy__sympy-15599
```

The script loads `.env`, pulls the task's Docker image if needed (about 1 GB, no time limit), then runs mini-swe-agent. Output goes to `results/<instance_id>/`:

| File | Contents |
|---|---|
| `<instance_id>.traj.json` | Full trajectory, every step the agent took |
| `patch.diff` | The patch the agent submitted (empty if none) |
| `run.log` | Everything printed during the run |
| `summary.txt` | Exit status, steps, wall time, estimated cost |

The script refuses to overwrite an existing trajectory. Move or delete `results/<instance_id>/` to re-run.

### Run every task in `tasks.txt`

```bash
for id in $(grep -vE '^\s*(#|$)' tasks.txt); do ./run_task.sh "$id"; done
```

`tasks.txt` lists one SWE-bench Verified instance ID per line. Lines starting with `#` are ignored.

### Grade the results

```bash
./grade.sh
```

This collects the patches from every trajectory in `results/` into `preds.json`, runs the official SWE-bench harness with one worker, and prints a line per task:

```
sympy__sympy-15599    FAIL (no patch submitted)

Resolved 0 of 1 submitted.
```

The harness skips tasks it has already graded under the same run ID. To re-grade a re-run task, delete `logs/run_evaluation/azure-gpt4o/*/<instance_id>/` first.

`grade.sh` uses the `SWE-bench/SWE-bench_Verified` dataset. The older `princeton-nlp/SWE-bench_Verified` copy lacks fields that swebench 5.x needs and crashes with `KeyError: 'image'`.

## Agent configuration

[azure_gpt4o.yaml](azure_gpt4o.yaml) holds the agent settings:

| Setting | Value |
|---|---|
| Model | `azure/gpt-4o` (via LiteLLM) |
| Environment | Docker |
| Step limit | 50 |
| Cost limit | $3 per task |
| Command timeout | 60 s |

It also contains the system and instance prompts, which tell the agent to fix the issue in non-test source files, reproduce the bug first, and verify the fix.

## Project layout

```
.
├── azure_gpt4o.yaml   Agent config (model, limits, prompts)
├── run_task.sh        Run the agent on one task
├── grade.sh           Grade all submitted patches
├── test_azure.py      Azure connectivity smoke test
├── tasks.txt          Instance IDs to run
├── results.md         Human-readable results table
├── notes.md           Step-by-step setup log with gotchas
├── preds.json         Generated predictions file (input to the grader)
├── .env               Azure secrets (git-ignored, you create this)
├── venv/              Python environment (git-ignored)
├── results/           Agent output and grader reports (git-ignored)
└── logs/              Harness logs (git-ignored)
```

## Further reading

[notes.md](notes.md) is a detailed log of how the project was set up, including every command, the errors hit along the way, and how they were fixed.

## Troubleshooting

- **`AZURE_API_BASE looks like a full Target URI`**: trim it to just `https://<resource>.openai.azure.com/`.
- **Docker image pull times out inside mini-swe-agent**: `run_task.sh` pulls the image beforehand for this reason. Make sure you ran it through the script.
- **Run ends with `LimitsExceeded` and an empty patch**: the agent used all 50 steps without submitting. Raise `step_limit` in `azure_gpt4o.yaml` or try a different task.
- **Running out of disk**: task images are large. Check `df -h /var/lib/docker`, not just the project disk.
