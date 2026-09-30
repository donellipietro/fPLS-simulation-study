# Supplementary GCV and fixed-penalty experiments

This one-dimensional suite supports the Supplementary Material's GCV sensitivity figures and
near-zero fixed-penalty experiments. Every production option cell uses 30 replications, four fitted
components, GCV seed `0`, 100 Rademacher trace probes, tolerance `1e-8`, and at most 1000
iterations.

| TEST_NAME | Production levels | Supplementary mapping |
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
include X/Y RMSE, unit-norm beta-shape RMSE preserving the coefficient signs, and fit time. The
near-zero families provide the finite-solution results reported in the Supplementary Material
for `m > k` and `m < k`.

After completing the [repository setup](../../README.md#setup-and-execution), run from the
repository root. Choose `TEST_NAME=all` to prepare the complete manuscript inputs, or select
one family:

```sh
# Run one experiment in the GCV suite
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity

# Run all experiments in the GCV suite
make run_test TEST_SUITE=GCV TEST_NAME=all
```

Selection-panel regeneration additionally requires every raw
`direction_gcv_h*.csv` and `loading_gcv_h*.csv` file. Aggregated performance data alone are not
enough to redraw the selected-penalty curves. These numerical experiments describe the recorded
grid and dimensions; they are not a general guarantee for arbitrary penalties or designs.
