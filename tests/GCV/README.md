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

The `sensitivity_componentwise` family keeps the baseline `NSR_X = 3`, uses a
true rank-four DGP, fits two components, and evaluates each fitted prefix
against its matching noise-free truth. For each component, the fixed direction
and loading penalties are constrained to be equal. Production crosses
`lambda_1` and `lambda_2` over `10^(-9:2)`, yielding 144 fixed schedules, then
adds one native-GCV cell and one MV-PLS cell: 146 fits per
replicate. The option records retain both lambda coordinates.
The fixed schedule path requires the companion `develop_fPLS` native change
that accepts one fixed penalty block per fitted component.

Aggregation saves median fixed-grid surfaces and paired, metric-specific
GCV/MV regrets relative to the best fixed schedule for the same simulated
replicate. This is a post-hoc truth oracle, not an implementable selector, and
it is constrained to the tested grid with equal direction/loading penalties
within each component. A negative reported regret is therefore possible when
GCV or MV-PLS beats that constrained fixed grid. Fixed-only plots show `h = 1`
box plots against `lambda_1` and `h = 2` heatmaps. A diamond marks the best
fixed-grid median shown in each plot. Since `h = 1` is independent of
`lambda_2`, its oracle `lambda_2` is reported as not applicable. Native GCV may
choose direction and loading penalties independently, so its selected component
pairs are shown in separate direction and loading plots rather than overlaid on
the fixed surface. Prefix outputs use RMSE for predictor and response
reconstruction, component-wise absolute cosine similarity for X directions,
X loadings, and X scores, and signed Frobenius cosine similarity for cumulative
beta. Components retain their sequential order without permutation matching.
For every metric, positive regret means worse than the constrained fixed-grid
truth oracle.

Smoke mode uses one replicate and the two distinct fixed levels `1e-6` and `1`
for each component, giving four fixed schedules plus the GCV and MV-PLS cells:

```bash
SMOKE_TEST=1 make run_test TEST_SUITE=GCV TEST_NAME=sensitivity_componentwise
```

The paired `sensitivity_competitors` and
`sensitivity_high_NSRX_competitors` families compare MV-PLS, both B-fPLS
variants, PB-fPLS, fPCR, and R1-fPLS on the same two data-generating scenarios.
Each competitor uses its own submitted calibration rule. These are one-cell
reference comparisons: the R1-fPLS lambda axis is deliberately not assigned to
methods whose tuning parameters have different meanings.

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
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity_componentwise
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test TEST_SUITE=GCV TEST_NAME=all
```
