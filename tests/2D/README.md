# Simulation 2: two-dimensional support

This suite implements Simulation 2 from the article and Supplementary Material. It uses a
functional predictor on the unit square, two responses, and four smooth signal components. The
reported methods are MV-PLS, fPCR, and R1-fPLS. fPCR smooths the predictor components with the
same candidate grid used by R1-fPLS, selecting each fPCA penalty by GCV before regressing the
response on the corresponding score prefix.

Production cells use 30 replications, baseline `NSR_X = 3`, `NSR_Y = 0.1`, tolerance `1e-8`,
and at most 1000 iterations unless the family varies the named quantity.

| TEST_NAME | Production levels | Paper mapping |
|---|---|---|
| `vary_n` | `n = 50, 100, 200`; `m = 1600`, `k = 900`, `H = 4` | Article representative beta maps at `n = 100`; Supplementary sample-size figure |
| `vary_m` | `m = 900, 1600, 2400`; `n = 100`, `k = 900`, `H = 4` | Supplementary observation-resolution figure |
| `vary_k` | `k = 25, 100, 400, 900, 1600, 2500`; `n = 100`, `m = 1600`, `H = 4` | Supplementary mesh-resolution figure |
| `vary_NSRX` | `NSR_X = 1, 3, 5, 10`; `n = 100`, `m = 1600`, `k = 900` | Supplementary predictor-noise figure |
| `vary_NSRY` | `NSR_Y = 0.01, 0.1, 0.5, 1`; `n = 100`, `m = 1600`, `k = 900` | Supplementary response-noise figure |
| `vary_H` | prefixes `H = 1,...,5` from one five-component fit | Article component-prefix figure |

The suite records Y- and X-reconstruction RMSE and separate unit-norm beta-shape
RMSEs for both responses, preserving the coefficient signs. `vary_H` also reports
explained X and Y variance at each prefix. Fit time is
compute-only and excludes data generation, I/O, and accuracy evaluation.

After completing the [repository setup](../../README.md#setup-and-execution), run from the
repository root. Choose `TEST_NAME=all` to prepare the complete manuscript inputs, or select
one family:

```sh
# Run one experiment in the 2D suite
make run_test TEST_SUITE=2D TEST_NAME=vary_n

# Run all experiments in the 2D suite
make run_test TEST_SUITE=2D TEST_NAME=all
```

`TEST_NAME=all` runs and aggregates every experiment separately. Paper inputs include
`results/2D/aggregate/<TEST_NAME>/loaded_<TEST_NAME>.rds`
for each experiment name in the table above, such as `loaded_vary_n.rds`, plus diagnostics,
paper metrics, explained-structure CSV files, and the representative `vary_n` raw batch
used for the qualitative beta maps.
