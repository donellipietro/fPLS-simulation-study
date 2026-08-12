# GCV Diagnostics

This one-dimensional suite studies R1-fPLS tuning and numerical behavior with four extracted
components. Production option cells use 30 replications, GCV seed `0` with 100 probe vectors,
`tol = 1e-8`, and `max_iter = 1000`.

## Families

| Family | Varying levels | Fixed production setting |
|---|---|---|
| `sensitivity` | GCV, the MV-PLS limit, and equal fixed direction/loading penalties `1e-9, ..., 1e-2` | `n = 100`, `m = 200`, `k = 51`, `NSR_X = 3`, `NSR_Y = 0.1` |
| `sensitivity_high_NSRX` | the same tuning choices | the same dimensions with `NSR_X = 10` |
| `lambda_to_zero` | `n = 50, 100, 200, 500, 1000, 2000, 5000` under GCV | `m = 100`, `k = 51`, `NSR_X = 3`, `NSR_Y = 0.1` |
| `small_lambda_m_gt_k` | fixed penalties with exponents `-300, -200, -100, -50, -30, -20, ..., -9` | `n = 100`, `m = 100`, `k = 51` |
| `small_lambda_m_lt_k` | fixed penalties with exponents `-300, -200, -100`, every two units from `-50` through `-30`, then `-20, ..., -9` | `n = 100`, `m = 25`, `k = 51` |

For the sensitivity families, GCV chooses direction and loading penalties separately at each
component from `1e-9, ..., 1e-2`. `sensitivity_review` is a group containing the two sensitivity
families; `all` contains all five families.

## Metrics and outputs

The sensitivity families evaluate every fitted prefix against its matching noise-free prefix.
They retain RMSE for X and Y reconstruction, the paper-compatible sign-aligned unit-norm beta
shape RMSE, signed Frobenius cosine similarity for cumulative beta, and absolute cosine
similarity for the component-wise X direction, loading, and score. No permutation matching is
applied.

The other families retain RMSE for X, Y, and beta against the final noise-free truth. Numerical
outputs include selected penalties, finite-solution and iteration-cap flags, iteration counts,
monotonicity, compute-only `fit_seconds`, and peak RAM. Objective histories are available for
penalized native fits; the `lambda = 0` MV-PLS limit does not provide them.

## Commands

```sh
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_high_NSRX
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=lambda_to_zero
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=small_lambda_m_gt_k
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=small_lambda_m_lt_k
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=all
```
