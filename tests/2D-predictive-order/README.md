# Supplementary predictive-order experiment

This suite implements the Supplementary Material experiment separating predictor variance from
response relevance. The predictor has ten trigonometric components with decreasing score
variance; only components 9 and 10 enter the two responses, scaled to equal response variance.
MV-PLS, fPCR, and R1-fPLS are fitted once with ten components and evaluated at every prefix
`H = 1,...,10`.

The only family is `vary_H`. Production settings are `n = 100`, `m = 1600`, `k = 900` on a
`30 x 30` finite-element mesh, 30 replications, `NSR_X = 3`, `NSR_Y = 0.1`, tolerance `1e-8`,
and at most 1000 iterations.

Outputs include noise-free Y/X reconstruction RMSE, separate unit-norm beta-shape
RMSEs preserving the coefficient signs, and explained X and Y variance. The experiment shows
the difference between variance-ordered and response-oriented extraction. It does not establish
that two PLS components are sufficient: exact reconstruction of the generative construction
requires all ten, and `H = 10` is fixed by design rather than selected from data.

After completing the [repository setup](../../README.md#setup-and-execution), run from the
repository root. `TEST_NAME=all` runs the sole family, `vary_H`, and prepares the complete
manuscript inputs:

```sh
# Run the predictive-order experiment
make run_test TEST_SUITE=2D-predictive-order TEST_NAME=all
```

Expected paper inputs are `results/2D-predictive-order/aggregate/vary_H/loaded_vary_H.rds`,
`explained_structure.csv`, `latent_design.csv`, diagnostics, and the complete production status.
