# 2D Simulation Study

This suite studies multivariate functional PLS on the unit square. Predictors
are generated from four smooth spatial loading functions and paired with two
responses. The final latent predictor component receives the severe-noise
condition used in the submitted study.

The suite compares multivariate PLS, fPCR, and R1-fPLS while varying the spatial
mesh resolution (`vary_k`), number of statistical units (`vary_n`), or number
of observed spatial locations (`vary_m`). The `vary_NSRX` and `vary_NSRY`
families vary one noise level while fixing `n = 100`, `m = 1600`, and
`k = 900`. The `vary_H` family fits five components once and reports the
reconstruction trajectory from one through five retained components, together
with the observed variance reconstructed in `X` and `Y` and the reconstructed
`X`--`Y` cross-covariance structure. The
fixed-component families report predictor reconstruction and response-specific
regression-coefficient shape error after four retained components.

Production families use 30 replications. Reports include wall-clock time,
peak memory, selected regularisation parameters, and a representative beta-map
comparison for the central `vary_n` scenario. Within each beta-map row, the
truth fixes the shared colour scale so the fitted maps can be compared directly.
