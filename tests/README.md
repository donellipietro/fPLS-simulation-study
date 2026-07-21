# fPLS Paper Test Suites

The repository contains four independently runnable suites:

```text
tests/
|-- 1D/
|   |-- config.R
|   |-- main.R
|   |-- aggregate_results.R
|   `-- utils/
|       |-- competitors.R
|       |-- fit_and_evaluate.R
|       |-- generate_data.R
|       |-- generate_options.R
|       |-- models_evaluation.R
|       |-- plot_qualitative_results.R
|       `-- wrappers.R
|-- 2D/
|   |-- config.R
|   |-- main.R
|   |-- aggregate_results.R
|   `-- utils/
|-- 2D-predictive-order/
|   |-- config.R
|   |-- main.R
|   |-- aggregate_results.R
|   `-- utils/
|       |-- generate_data.R
|       `-- generate_options.R
`-- GCV/
    |-- config.R
    |-- main.R
    |-- aggregate_results.R
    `-- utils/
        `-- generate_options.R
```

The 1D and 2D suites contain the submitted-design families plus additional
noise-sensitivity families. The 2D suite also studies progressive
component counts. The GCV suite isolates tuning sensitivity, large-sample
behavior, and near-zero penalties. The separate 2D predictive-order suite is an
experimental comparison of variance-ordered fPCR with response-relevant fPLS.
`all` resolves each suite's families through the shared testbench group utility.

- [1D suite](1D/README.md): curve-based experiments and submitted 1D comparators.
- [2D suite](2D/README.md): submitted spatial experiments and noise-sensitivity extensions.
- [2D predictive-order suite](2D-predictive-order/README.md): experimental late-response-component design.
- [GCV suite](GCV/README.md): one-dimensional tuning and numerical-stability diagnostics.

```bash
make run_test TEST_SUITE=1D TEST_NAME=vary_k
make run_test TEST_SUITE=2D TEST_NAME=vary_n
make run_test TEST_SUITE=2D-predictive-order TEST_NAME=all
make run_test TEST_SUITE=GCV TEST_NAME=sensitivity
```
