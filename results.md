# Results: mini-swe-agent + GPT-4o (Azure) on SWE-bench Verified

Setup: mini-swe-agent 2.4.6, `gpt-4o-2024-11-20` (Azure deployment `gpt-4o`),
temperature 0.0, step limit 50, graded with swebench 5.0.2 on
`SWE-bench/SWE-bench_Verified`.

| task ID | passed? | steps | time | notes |
|---|---|---|---|---|
| sympy__sympy-15599 | ❌ No | 50 (limit hit) | 4m 32s | No patch submitted (`LimitsExceeded`). Tried the fix from the issue with a `sed` one-liner in step 3 but never checked the edit; spent ~18 steps fixing `IndentationError`s from its own debug prints. Est. cost $0.67 (98% of prompt tokens cached). |

**Score so far: 0 / 1 resolved.**

"time" is agent time only. The first run of each task also downloads its
Docker image (~1 GB, ~15 min here).

Grader check: the official gold patch for sympy__sympy-15599 passes
(FAIL_TO_PASS 1/1, PASS_TO_PASS 80/80), so the grading setup works.
