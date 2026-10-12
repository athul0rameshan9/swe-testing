# Results: mini-swe-agent + GPT-4o (Azure) on SWE-bench Verified

Setup: mini-swe-agent 2.4.6, `gpt-4o-2024-11-20` (Azure deployment `gpt-4o`),
temperature 0.0, step limit 50, graded with swebench 5.0.2 on
`SWE-bench/SWE-bench_Verified`.

Batch 1 was sympy__sympy-15599. Batch 2 (run 2026-10-12) added six tasks rated
"<15 min fix", one from each of six other repos.

| task ID | passed? | steps | time | notes |
|---|---|---|---|---|
| sympy__sympy-15599 | ❌ No | 50 (limit hit) | 4m 32s | No patch submitted (`LimitsExceeded`). Tried the fix from the issue with a `sed` one-liner in step 3 but never checked the edit; spent ~18 steps fixing `IndentationError`s from its own debug prints. Est. cost $0.67 (98% of prompt tokens cached). |
| pallets__flask-5014 | ✅ Yes | 11 | 1m 15s | Added an empty-name check to `Blueprint.__init__` and ran a small repro. FAIL_TO_PASS 1/1, PASS_TO_PASS 59/59. Est. cost $0.11. |
| psf__requests-1142 | ❌ No | 50 (limit hit) | 6m 44s | No patch submitted. Inserted a `GET` check into `prepare_content_length` with `sed '/.../a'` in step 8, got an `IndentationError`, then spent ~40 steps alternating between two indentation variants of the same `sed` without re-reading the file. Est. cost $1.04. |
| django__django-10097 | ❌ No | 50 (limit hit) | 6m 12s | No patch submitted. Its `sed` substitution on the `URLValidator` regex never matched (the `*` in its pattern is a quantifier, not a literal `*`), so the file never changed. Its own test printed "Valid" for every URL, and it repeated the same grep, sed, test cycle 13 times. Est. cost $0.92. Even the gold patch fails this task here; see "Grader checks". |
| pytest-dev__pytest-10081 | ❌ No | 15 | 1m 35s | Wrong patch submitted. Inverted the `_is_skipped(self.obj)` check instead of also checking the class. The target test passes (FAIL_TO_PASS 1/1), but an existing test now fails (PASS_TO_PASS 62/63: `test_pdb_teardown_skipped_for_functions[@unittest.skip]`). It only ran its own repro, never the existing tests. Est. cost $0.17. |
| scikit-learn__scikit-learn-13439 | ❌ No | 50 (limit hit) | 9m 5s | No patch submitted. Added `__len__` with `echo ... >> pipeline.py`, which put it at the end of the file, outside the `Pipeline` class. Blamed stale imports instead, ran `pip uninstall scikit-learn` inside the container, then repeated the same 4 commands for ~30 steps. Est. cost $1.21. |
| astropy__astropy-14309 | ✅ Yes | 9 | 1m 5s | Guarded `args[0]` with `if args:` in `is_fits`. Its first `sed` caused an `IndentationError`, which it noticed and fixed in the next step. FAIL_TO_PASS 1/1, PASS_TO_PASS 141/141. Est. cost $0.08. |

**Score: 2 / 7 resolved (29%).** Batch 2 alone: 2 / 6.

| | all 7 tasks | batch 2 (6 tasks) |
|---|---|---|
| Resolved | 2 | 2 |
| Steps | 235 | 185 |
| Agent time | 30m 28s | 25m 56s |
| Est. cost | $4.20 | $3.53 |
| Prompt tokens cached | 97% | 97% |

No rate-limit (429) errors in any run. The largest single prompt was 35,920
tokens (scikit-learn), well under the 100K tokens-per-minute limit.

"time" is agent time only. The first run of each task also downloads its
Docker image (~1 GB). In batch 2 the download plus container setup took
3 to 11 minutes per task (about 34 minutes in total), faster than sympy's
15 minutes because the images share base layers.

## What the runs show

- **The failures came from editing, not from understanding the bug.** In all
  four runs that hit the step limit, the agent found the right file and a
  plausible fix within 8 steps. A shell edit (`sed` or `echo >>`) then went
  wrong, and the agent never re-read the file to see what the edit had done.
  Each of these runs ended in a loop of the same 2 to 4 commands until the
  50-step limit.
- **Successful runs are short and cheap.** The two resolved tasks took 9 and
  11 steps and about $0.10 each. Every run that hit the limit used all 50
  steps and cost $0.67 to $1.21. Those four runs account for 91% of the total
  spend ($3.84 of $4.20).
- **The one wrong patch (pytest) passed the agent's own check.** It never ran
  the project's existing tests, which would have caught the regression.

## Grader checks

Where the agent submitted no patch, the grader never ran any tests. To confirm
the grading setup works for those tasks, the official gold patch was graded for
each one (`--predictions_path gold`, run ID `gold-check`):

| task ID | gold patch | FAIL_TO_PASS | PASS_TO_PASS |
|---|---|---|---|
| sympy__sympy-15599 | ✅ passes | 1/1 | 80/80 |
| psf__requests-1142 | ✅ passes | 1/1 | 5/5 |
| scikit-learn__scikit-learn-13439 | ✅ passes | 1/1 | 40/40 |
| django__django-10097 | ❌ fails | 431/438 | 1427/1427 |

**django__django-10097 can't be resolved in this setup.** All 7 failing
tests are in `auth_tests.test_templates` and error with
`TemplateDoesNotExist: registration/password_reset_form.html`. The URL-validator
fix doesn't touch that template, so these 7 tests fail in this Docker image
whatever the patch is. The agent submitted nothing, so it fails either way.
Leaving this task out, the score is 2 / 6.
