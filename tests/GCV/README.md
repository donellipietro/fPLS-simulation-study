# Supplementary GCV and numerical checks

This one-dimensional suite supports the Supplementary Material's GCV sensitivity figures and
near-zero fixed-penalty checks. Every production option cell uses 30 replications, four fitted
components, GCV seed `0`, 100 Rademacher trace probes, tolerance `1e-8`, and at most 1000
iterations.

| Family | Production levels | Supplementary mapping |
|---|---|---|
| `sensitivity` | GCV, the MV-PLS limit, and common fixed direction/loading penalties `1e-9,...,1e-2`; `NSR_X = 3` | GCV performance and selected-penalty figures |
| `sensitivity_high_NSRX` | same tuning choices with `NSR_X = 10` | High-noise GCV performance and selected-penalty figures |
| `small_lambda_m_gt_k` | fixed exponents `-300,-200,-100,-50,-30,-20,...,-9`; `n = 100`, `m = 100`, `k = 51` | Reported finite-solution check for `m > k` |
| `small_lambda_m_lt_k` | fixed exponents `-300,-200,-100`, every two from `-50` to `-30`, then `-20,...,-9`; `n = 100`, `m = 25`, `k = 51` | Reported finite-solution threshold check for `m < k` |

The sensitivity grid is intentionally restricted to `1e-9,...,1e-2` because it contains the
observed GCV optima and makes the displayed curves readable. GCV chooses direction and loading
penalties separately after each deflation step. The `lambda = 0` cell is the non-iterative
MV-PLS benchmark and has no objective history.

Sensitivity outputs evaluate every fitted prefix against its matching noise-free prefix. They
retain X/Y RMSE, sign-aligned unit-norm beta-shape RMSE, signed Frobenius cosine for cumulative
beta, and absolute cosine for each direction, loading, and score in extraction order. The
near-zero families retain finite-solution, iteration-cap, monotonicity, fit-time, and peak-RAM
diagnostics against the final truth.

```sh
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_high_NSRX
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=small_lambda_m_gt_k
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=small_lambda_m_lt_k
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=all
```

Selection-panel regeneration additionally requires every raw
`direction_gcv_h*.csv` and `loading_gcv_h*.csv` file. Aggregated performance data alone are not
enough to redraw the selected-penalty curves. These numerical experiments describe the recorded
grid and dimensions; they are not a general guarantee for arbitrary penalties or designs.
