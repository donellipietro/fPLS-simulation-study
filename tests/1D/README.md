# 1D Simulation Study

This suite uses a functional predictor on the unit interval and one scalar response. The data
contain four latent functional components. Production runs use 30 replications, four fitted
components, baseline noise ratios `NSR_X = 3` for the final predictor component and
`NSR_Y = 0.1`, and `tol = 1e-8`, `max_iter = 1000` for iterative fits.

The compared methods are MV-PLS, B-fPLS with regression splines, B-fPLS with smoothing
splines, PB-fPLS, fPCR, and R1-fPLS.

## Families

| Family | Levels | Fixed production setting |
|---|---|---|
| `vary_k` | `k = 5, 11, 21, 51, 101` | `n = 100`, `m = 200`; competitor basis size follows `k` |
| `vary_n` | `n = 50, 100, 200` | `m = 200`, source `k = 51`, competitor basis size `11` |
| `vary_m` | `m = 50, 100, 200` | `n = 100`, source `k = 51`, competitor basis size `11` |
| `vary_NSRX` | `NSR_X = 1, 3, 5, 10` | `n = 100`, `m = 200`, source `k = 51`, `NSR_Y = 0.1` |
| `vary_NSRY` | `NSR_Y = 0.01, 0.1, 0.5, 1` | `n = 100`, `m = 200`, source `k = 51`, `NSR_X = 3` |

Here `n` is the sample size, `m` the number of observed locations, and `k` the source
discretization size.

## Metrics and outputs

For every retained component the suite records RMSE for the noise-free Y and X
reconstructions and the paper-compatible, sign-aligned unit-norm beta shape RMSE. Aggregates
also retain compute-only `fit_seconds`, peak RAM, selected penalties, iteration counts, and
monotonicity when available. `vary_k` produces the submitted qualitative beta comparison for
`k = 11` and `k = 101`; that panel deliberately keeps the submitted model subset, while all
six methods remain in the quantitative results.

## Commands

```sh
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=vary_k
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=vary_NSRX
```
