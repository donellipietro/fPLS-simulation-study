# 2D Simulation Study

This suite uses a functional predictor on the unit square and two scalar responses. The data
contain four smooth spatial signal components. Production runs use 30 replications, baseline
noise ratios `NSR_X = 3` for the final predictor component and `NSR_Y = 0.1`, and
`tol = 1e-8`, `max_iter = 1000` for iterative fits.

The compared methods are MV-PLS, fPCR, and R1-fPLS.

## Families

| Family | Levels | Fixed production setting |
|---|---|---|
| `vary_k` | `k = 25, 100, 400, 900, 1600, 2500` | `n = 100`, `m = 1600`, four fitted components |
| `vary_n` | `n = 50, 100, 200` | `m = 1600`, `k = 900`, four fitted components |
| `vary_m` | `m = 900, 1600, 2400` | `n = 100`, `k = 900`, four fitted components |
| `vary_NSRX` | `NSR_X = 1, 3, 5, 10` | `n = 100`, `m = 1600`, `k = 900`, `NSR_Y = 0.1` |
| `vary_NSRY` | `NSR_Y = 0.01, 0.1, 0.5, 1` | `n = 100`, `m = 1600`, `k = 900`, `NSR_X = 3` |
| `vary_H` | prefixes `H = 1, ..., 5` | one five-component fit at `n = 100`, `m = 1600`, `k = 900` |

Here `n` is the sample size, `m` the number of observed locations, and `k` the number of mesh
nodes used by the source discretization.

## Metrics and outputs

The suite records RMSE for noise-free Y and X reconstructions and separate paper-compatible,
sign-aligned unit-norm beta shape RMSEs for the two responses. `vary_H` additionally records
the reconstructed variance of X and Y and reconstructed X--Y cross-covariance for each prefix.
Aggregates retain compute-only `fit_seconds`, peak RAM, selected penalties, iteration counts,
and monotonicity when available. The central `vary_n` setting also produces a representative
beta-map panel with one truth-fixed colour range per response.

## Commands

```sh
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=vary_n
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=vary_m
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=vary_H
```
