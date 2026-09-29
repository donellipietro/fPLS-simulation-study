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

Here `n` is sample size, `m` is the number of observed locations, and `k` is the number
of R1-fPLS basis functions. In `vary_k`, B-fPLS and PB-fPLS use the same basis sizes.
In the other families, B-fPLS and PB-fPLS use 11 basis functions and R1-fPLS uses 51.

For every component prefix, the suite records noise-free Y- and X-reconstruction RMSE and the
unit-norm beta-shape RMSE preserving the coefficient signs. Aggregates also contain compute-only
fit time, peak RAM, selected penalties, iteration counts, finite-solution flags, and monotonicity
where available.

After completing the [repository setup](../../README.md#setup-and-execution), run from the
repository root. Choose `TEST_NAME=all` to prepare the complete manuscript inputs, or select
one family:

```sh
make run_test TEST_SUITE=1D TEST_NAME=vary_k
make run_test TEST_SUITE=1D TEST_NAME=all
```

Expected paper inputs are `results/1D/aggregate/all/loaded_<family>.rds`, the corresponding
diagnostic/metric CSV files, and representative raw batches for the data and qualitative panels.
