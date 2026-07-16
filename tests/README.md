# fPLS Paper Test Suites

The repository contains two independently runnable suites:

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
`-- 2D/
    |-- config.R
    |-- main.R
    |-- aggregate_results.R
    `-- utils/
        |-- competitors.R
        |-- fit_and_evaluate.R
        |-- generate_data.R
        |-- generate_options.R
        |-- models_evaluation.R
        |-- plot_qualitative_results.R
        `-- wrappers.R
```

Both suites expose `vary_k`, `vary_n`, and `vary_m`; `all` resolves those names
through the shared testbench group utility. Suite code owns only scientific
options, generation, model adaptation, evaluation, validation, and report
composition. Root code retains the canonical testbench framework.

- [1D suite](1D/README.md): curve-based experiments and submitted 1D comparators.
- [2D suite](2D/README.md): spatial experiments comparing multivariate PLS and R1-fPLS.

```bash
make run_test TEST_SUITE=1D TEST_NAME=vary_k
make run_test TEST_SUITE=2D TEST_NAME=vary_n
```
