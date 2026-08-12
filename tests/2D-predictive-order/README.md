# Predictive Component Ordering in 2D

This separate diagnostic suite compares variance-ordered and response-relevant component
extraction. Its only family is `vary_H` (and therefore also the suite target `all`).

## Design

The predictor contains ten trigonometric spatial components with decreasing score variance.
Only components 9 and 10 enter the two responses, scaled to equal response variance. MV-PLS,
fPCR, and R1-fPLS are each fitted once with ten components and evaluated at every progressive
prefix `H = 1, ..., 10`.

Production settings are `n = 100`, `m = 1600`, `k = 900` on a `30 x 30` finite-element mesh,
30 replications, `NSR_X = 3`, `NSR_Y = 0.1`, `tol = 1e-8`, and `max_iter = 1000`.

## Metrics and outputs

For every prefix the suite records RMSE for noise-free Y and X reconstructions and separate
sign-aligned unit-norm beta shape RMSEs for both responses. It also records reconstructed X and
Y variance and reconstructed X--Y cross-covariance. Compute-only `fit_seconds`, peak RAM,
selected penalties, iteration counts, monotonicity, and the imposed variance/relevance design
plot are retained.

## Commands

```sh
make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=vary_H
make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=all
```
