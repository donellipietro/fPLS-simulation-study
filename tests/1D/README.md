# Simulation 1: one-dimensional support

This suite implements Simulation 1 from the article and its supplementary resolution and noise
analyses. It uses a predictor on `[0,1]`, one scalar response, four latent signal components, 30
production replications, `NSR_X = 3`, `NSR_Y = 0.1`, tolerance `1e-8`, and at most 1000 solver
iterations unless the selected family varies that quantity.

The manuscript comparisons are MV-PLS, B-fPLS with regression splines, B-fPLS with smoothing
splines, PB-fPLS, and R1-fPLS.

| TEST_NAME | Production levels | Paper mapping |
|---|---|---|
| `vary_k` | `k = 5, 11, 21, 51, 101`; `n = 100`, `m = 200` | Article varying-basis figure; `k = 11,101` qualitative beta figure; `k = 11` data figure |
| `vary_n` | `n = 50, 100, 200`; `m = 200`, source `k = 51` | Article sample-size figure |
| `vary_m` | `m = 50, 100, 200`; `n = 100`, source `k = 51` | Supplementary observed-location figure |
| `vary_NSRX` | `NSR_X = 1, 3, 5, 10`; `n = 100`, `m = 200`, source `k = 51` | Supplementary predictor-noise figure |
| `vary_NSRY` | `NSR_Y = 0.01, 0.1, 0.5, 1`; `n = 100`, `m = 200`, source `k = 51` | Supplementary response-noise figure |

Here `n` is sample size, `m` is the number of observed locations, and `k` counts mesh
nodes/breaks, including endpoints. Cubic B-splines give `k + 2` basis functions.
In `vary_k`, all functional methods use the same `k`. In the other families, B-fPLS
and PB-fPLS use 11 breaks (13 basis functions), and R1-fPLS uses 51 nodes (53 basis functions).

For every component prefix, the suite records noise-free Y- and X-reconstruction RMSE and the
unit-norm beta-shape RMSE preserving the coefficient signs. Aggregates also contain compute-only
fit time, peak RAM, selected penalties, iteration counts, finite-solution flags, and monotonicity
where available.

After completing the [repository setup](../../README.md#setup-and-execution), run from the
repository root. Choose `TEST_NAME=all` to prepare the complete manuscript inputs, or select
one family:

```sh
# Run one experiment in the 1D suite
make run_test TEST_SUITE=1D TEST_NAME=vary_k

# Run all experiments in the 1D suite
make run_test TEST_SUITE=1D TEST_NAME=all
```

`TEST_NAME=all` runs and aggregates every experiment separately. Paper inputs include
`results/1D/aggregate/<TEST_NAME>/loaded_<TEST_NAME>.rds`
for each experiment name in the table above, such as `loaded_vary_k.rds`, plus the
corresponding diagnostic/metric CSV files and representative raw batches for the data and
qualitative panels.
