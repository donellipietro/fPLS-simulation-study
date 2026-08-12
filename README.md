# fPLS Simulation Study

This repository contains the simulation experiments used for the fPLS paper and its reviewer
diagnostics. Production runs use 30 replications per option cell and single-threaded fits.

## Experiment catalog

| Suite | Families in `all` | Comparison |
|---|---|---|
| `1D` | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY` | MV-PLS, two B-fPLS variants, PB-fPLS, fPCR, and R1-fPLS on a curve with a scalar response |
| `2D` | `vary_k`, `vary_n`, `vary_NSRX`, `vary_NSRY`, `vary_H` | MV-PLS, fPCR, and R1-fPLS on the unit square with two responses |
| `GCV` | `sensitivity`, `sensitivity_high_NSRX`, `lambda_to_zero`, `small_lambda_m_gt_k`, `small_lambda_m_lt_k` | R1-fPLS tuning and numerical diagnostics in 1D |
| `2D-predictive-order` | `vary_H` | MV-PLS, fPCR, and R1-fPLS when response-relevant components have low predictor variance |

The exact levels and fixed settings are documented in each suite README under `tests/`.

## Metrics

The paper-facing 1D and 2D suites report RMSE against the noise-free response and predictor
reconstructions. Regression-coefficient error is the RMSE between unit-Frobenius-norm beta
shapes after choosing the sign that minimizes the error; the 2D suite reports this separately
for both responses.

The two GCV sensitivity families additionally retain signed Frobenius cosine similarity for
the cumulative beta estimate and absolute cosine similarity for each X direction, loading, and
score. Components remain in extraction order. The predictive-order suite also reports the
reconstructed variance of X and Y and reconstructed X--Y cross-covariance.

`fit_seconds` is compute-only: it covers method-specific preprocessing/tuning, fitting, and
in-memory post-processing. It excludes data generation, result I/O, and accuracy evaluation.
Peak RAM, selected penalties, iteration counts, and monotonicity diagnostics are retained when
the fitted method supplies them.

## Run commands

Prepare one runtime profile, then run a suite or an individual family:

```sh
make build PROFILE=macbook
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=all

# Example: one family only
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity
```

Available profiles are `macbook`, `windows`, `hpc-slurm`, and `hpc-torque`. After all required
production aggregations are present, regenerate every report CSV and compile the reviewer report:

```sh
make review_report
```

See [`reports/README.md`](reports/README.md) for the table-to-aggregate provenance matrix.
