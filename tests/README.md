# Simulation suites

Each suite saves generated data, fitted models and accuracy metrics, then aggregates complete
simulation results. Each option cell uses 30 replications.

| Suite | Families | Paper mapping |
|---|---|---|
| [`1D`](1D/README.md) | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY` | Article Simulation 1 and its supplementary resolution/noise analyses |
| [`2D`](2D/README.md) | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY`, `vary_H` | Article Simulation 2 and its supplementary analyses |
| [`GCV`](GCV/README.md) | `sensitivity`, `sensitivity_high_NSRX`, `small_lambda_m_gt_k`, `small_lambda_m_lt_k` | Supplementary GCV sensitivity and near-zero-penalty experiments |
| [`2D-predictive-order`](2D-predictive-order/README.md) | `vary_H` | Supplementary predictive-order experiment |

First follow the [repository setup](../README.md#setup-and-execution) to select a platform
profile with `make build`. The build installs missing R dependencies through
[`install_packages.R`](../src/installation/install_packages.R) and saves the profile in `.env`.
Subsequent commands reuse that profile, and `make run_test` compiles the selected suite
automatically. From the repository root, run one family or every family in a suite:

```sh
make run_test TEST_SUITE=1D TEST_NAME=vary_k
make run_test TEST_SUITE=1D TEST_NAME=all
```

For all manuscript panels and tables, run each suite with
`TEST_NAME=all`; the scripts read complete results from `results/<TEST_SUITE>/aggregate/all/`,
with 30 replications per option cell. See the [figure guide](../paper-figures/README.md) and
[table guide](../paper-tables/README.md) for the required raw files and output locations.
