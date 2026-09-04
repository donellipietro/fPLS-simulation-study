# Simulation suites

Each suite follows the same production contract: generate explicit JSON options, execute one or
more batches, save fitted models and evaluations, then aggregate only complete matching results.
Production cells use 30 replications; `SMOKE_TEST=1` reduces the workload for plumbing checks.

| Suite | Families | Paper mapping |
|---|---|---|
| [`1D`](1D/README.md) | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY` | Article Simulation 1 and its supplementary resolution/noise analyses |
| [`2D`](2D/README.md) | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY`, `vary_H` | Article Simulation 2 and its supplementary analyses |
| [`GCV`](GCV/README.md) | `sensitivity`, `sensitivity_high_NSRX`, `small_lambda_m_gt_k`, `small_lambda_m_lt_k` | Supplementary GCV sensitivity and near-zero-penalty checks |
| [`2D-predictive-order`](2D-predictive-order/README.md) | `vary_H` | Supplementary predictive-order experiment |

Run one family or every family in a suite:

```sh
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=vary_k
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=all
```

`GCV/sensitivity_review` is a convenience group containing the two GCV sensitivity families; it
is not a separate experiment. Generated queue, data, result, image, log, and build trees are
ignored. A manuscript-facing aggregate must have a complete non-smoke `run_status.json` and all
expected replications before it is used by figure or table scripts.
