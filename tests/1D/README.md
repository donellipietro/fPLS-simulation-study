# Simulation 1: one-dimensional support

This suite implements Simulation 1 from the article and its supplementary resolution and noise
analyses. It uses a predictor on `[0,1]`, one scalar response, four latent signal components, 30
production replications, `NSR_X = 3`, `NSR_Y = 0.1`, tolerance `1e-8`, and at most 1000 solver
iterations unless the selected family varies that quantity.

The manuscript comparisons are MV-PLS, B-fPLS with regression splines, B-fPLS with smoothing
splines, PB-fPLS, and R1-fPLS.

| Family | Production levels | Paper mapping |
|---|---|---|
| `vary_k` | `k = 5, 11, 21, 51, 101`; `n = 100`, `m = 200` | Article varying-basis figure; `k = 11,101` qualitative beta figure; `k = 11` data figure |
| `vary_n` | `n = 50, 100, 200`; `m = 200`, source `k = 51` | Article sample-size figure |
| `vary_m` | `m = 50, 100, 200`; `n = 100`, source `k = 51` | Supplementary observed-location figure |
| `vary_NSRX` | `NSR_X = 1, 3, 5, 10`; `n = 100`, `m = 200`, source `k = 51` | Supplementary predictor-noise figure |
| `vary_NSRY` | `NSR_Y = 0.01, 0.1, 0.5, 1`; `n = 100`, `m = 200`, source `k = 51` | Supplementary response-noise figure |

Here `n` is sample size, `m` is the number of observed locations, and `k` is the source
discretization size. B-fPLS/PB-fPLS use the family-specific basis settings encoded by
`utils/generate_options.R`.

For every component prefix, the suite records noise-free Y- and X-reconstruction RMSE and the
sign-aligned unit-norm beta-shape RMSE. Aggregates also contain compute-only fit time, peak RAM,
selected penalties, iteration counts, finite-solution flags, and monotonicity where available.

```sh
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=vary_k
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=vary_NSRX
```

Expected paper inputs are `results/1D/aggregate/all/loaded_<family>.rds`, the corresponding
diagnostic/metric CSV files, and representative raw batches for the data and qualitative panels.
