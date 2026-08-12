# GCV Diagnostics

This one-dimensional suite studies tuning and numerical behavior for R1-fPLS.
It uses the submitted simulation generator and the common settings `tol = 1e-8`,
`max_iter = 1000`, and GCV seed `0`.

## Sensitivity Experiments

The `sensitivity` family compares GCV (`lambda = -1`), the MV-PLS limit
(`lambda = 0`), and fixed equal direction/loading penalties from `1e-9` to
`1e-2`. The fixed dimensions are `n = 100`, `m = 200`, and `k = 51`, the
intersection of the fixed settings in the 1D paper families.

The `sensitivity_high_NSRX` family repeats that experiment with the predictor
noise-to-signal ratio increased from `3` to `10`; the response noise remains
`0.1`. This isolates whether GCV supplies useful regularization when the
functional predictor is more contaminated.

Both one-lambda sensitivity families evaluate each fitted prefix `h` against
its matching noise-free `X_h`, `Y_h`, and cumulative `beta_h`. They report RMSE
for predictor and response reconstruction, signed Frobenius cosine similarity
for beta, and component-wise absolute cosine similarity for X directions,
X loadings, and X scores. Components retain their sequential order without
permutation matching.

## Asymptotic And Numerical Experiments

The `lambda_to_zero` family increases `n` from 50 to 5000 with `m = 100` and
`k = 51`, recording the component-wise GCV choices. The
`small_lambda_m_gt_k` and `small_lambda_m_lt_k` families probe very small fixed
positive penalties with `m = 100, k = 51` and `m = 25, k = 51`, respectively.
The `m < k` grid is refined every two log10 units from `1e-50` through `1e-30`,
where the initial experiment located the finite-solution transition.

All families retain objective histories, iteration counts, monotonicity flags,
execution times, peak RAM, reconstruction errors, and selected penalties.

## Monotonicity Scope

For a fixed component and fixed nonnegative penalty, the direction iteration minimizes

`J(v, f) = ||M - v f^T||_F^2 + P_lambda(f)`, subject to `||v|| = 1`.

The update of `v` is the exact conditional minimizer for fixed `f`, and the
penalized smoother is the exact conditional minimizer for fixed `v`.
Consequently each complete alternating step cannot increase `J`. Since
`J >= 0`, the recorded objective sequence converges. This argument establishes
objective monotonicity within each deflated component; it does not establish a
global optimum, convergence of the iterates without further assumptions, or a
comparison of objective values across components. The same
alternating-minimization principle appears in penalized rank-one FPCA. RGCCA is
a related example of a component algorithm with a proved monotone objective,
but it optimizes a different criterion.

## References

- Huang, Shen, and Buja (2008), [Functional principal components analysis via
  penalized rank one approximation](https://doi.org/10.1214/08-EJS218).
- Tenenhaus and Tenenhaus (2011), [Regularized Generalized Canonical
  Correlation Analysis](https://doi.org/10.1007/s11336-011-9206-8).
- Tseng (2001), [Convergence of a Block Coordinate Descent Method for
  Nondifferentiable Minimization](https://doi.org/10.1023/A:1017501703105), for
  general stationary-point conditions beyond objective descent.

Run one family or the complete suite with the standard testbench commands:

```bash
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity_high_NSRX
make run_test TEST_SUITE=GCV TEST_NAME=lambda_to_zero
make run_test TEST_SUITE=GCV TEST_NAME=small_lambda_m_gt_k
make run_test TEST_SUITE=GCV TEST_NAME=small_lambda_m_lt_k
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test TEST_SUITE=GCV TEST_NAME=all
```
