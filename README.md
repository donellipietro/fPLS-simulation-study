# fPLS simulation study

This repository contains the simulation code supporting the article and Supplementary Material
for “Rank-One Functional Partial Least Squares Regression”. It includes the simulation experiments,
execution and aggregation scripts, manuscript figure and table sources, and the editable Affinity layout. Generated data, fitted
models, aggregate results, logs, panels, and exported PDFs are intentionally outside Git.

## Paper map

| TEST_SUITE/TEST_NAME | Article or Supplementary Material output |
|---|---|
| `1D/vary_k` | Article: Simulation 1 data, varying-basis and qualitative-beta figures |
| `1D/vary_n` | Article: Simulation 1 sample-size figure |
| `1D/vary_m` | Supplement: varying observed locations |
| `1D/vary_NSRX`, `1D/vary_NSRY` | Supplement: Simulation 1 noise robustness |
| `2D/vary_H` | Article: Simulation 2 component-prefix figure |
| `2D/vary_n` | Article: representative beta maps; Supplement: sample-size figure |
| `2D/vary_m`, `2D/vary_k` | Supplement: observation- and mesh-resolution figures |
| `2D/vary_NSRX`, `2D/vary_NSRY` | Supplement: Simulation 2 noise robustness |
| `GCV/sensitivity`, `GCV/sensitivity_high_NSRX` | Supplement: GCV performance and selected-penalty figures |
| `GCV/small_lambda_m_gt_k`, `GCV/small_lambda_m_lt_k` | Supplement: fixed-penalty numerical experiments for `m > k` and `m < k` |
| `2D-predictive-order/vary_H` | Supplement: low-predictor-variance predictive-order experiment |

The Simulation 1 figures compare MV-PLS, the B-fPLS variants, PB-fPLS, and R1-fPLS. Simulation 2
and the predictive-order experiment compare MV-PLS, fPCR, and R1-fPLS.

## Prerequisites

Install the following on your machine before running the workflow:

- GNU Make, Bash, Git and R;
- a C++20 compiler and Eigen for native compilation with the `macos` or `linux` profile;
- GNU Parallel and `bc` for parallel execution;
- Docker Desktop with WSL2 integration for the `windows` profile.

`make build` automatically installs missing R packages listed in
[`src/installation/install_packages.R`](src/installation/install_packages.R) and `femR`, and prepares
the nlohmann/json headers and the pinned `fdaPDE-cpp` stack. The native revisions
are pinned in `config.R`. For the `windows` profile, the build also prepares the configured Docker image.

For local execution, choose `macos` on macOS, `linux` on Linux, or `windows` on Windows.
The Linux profile uses `gcc`, `g++`, and Eigen in `/usr/include/eigen3`; override `CC`, `CXX`,
or `PATH_EIGEN_INCLUDE` if your installation uses different paths. Inspect a profile with:

```sh
make config PROFILE=macos
```

## Setup and execution

Select a profile when preparing the runtime. The build saves it in `.env`, and subsequent
commands reuse it:

```sh
make build PROFILE=macos
```

Use `PROFILE=linux` or `PROFILE=windows` for the corresponding platform.
`TEST_SUITE` selects the simulation suite, and `TEST_NAME` selects an experiment or
`all` for every experiment in that suite. `make run_test` automatically compiles
the selected suite before execution:

```sh
# Run one experiment in the 1D suite
make run_test TEST_SUITE=1D TEST_NAME=vary_k

# Run all experiments in the 1D suite
make run_test TEST_SUITE=1D TEST_NAME=all
```

Production option cells use 30 replications and single-threaded model fits.

## Results

After `make run_test`, aggregated results are available in
`results/<TEST_SUITE>/aggregate/<TEST_NAME>/` and figures in
`images/<TEST_SUITE>/<TEST_NAME>/` for a single-family run, relative to the repository root.
For example, running `TEST_SUITE=1D TEST_NAME=vary_k` writes results to
`results/1D/aggregate/vary_k/` and figures to `images/1D/vary_k/`.

To generate all manuscript panels and convergence tables, first run each suite (`1D`, `2D`,
`GCV`, and `2D-predictive-order`) with `TEST_NAME=all`. Once the complete `aggregate/all`
results and the associated raw files are available, run from the repository root:

```sh
make simulation_figure_panels
make simulation_paper_tables
```

See the [figure guide](paper-figures/README.md) and [table guide](paper-tables/README.md)
for output locations and further options.

## Metrics and computational boundary

Reported RMSE values compare fitted quantities with their noise-free references. Regression
coefficient functions are normalized separately to unit Frobenius norm, preserving their signs,
before RMSE evaluation. The GCV sensitivity figures report these errors at each retained component prefix.

`fit_seconds` is compute-only: it includes method-specific preprocessing/tuning, fitting, and
in-memory post-processing, but excludes data generation, result I/O, and accuracy evaluation.
It is not total campaign runtime and must not be compared across different hardware as though it
were. The paper reports fit time, peak resident memory, and iteration counts.

## Reproducibility boundary

The manuscript figures were generated from complete aggregate trees with 30 replications per
option cell. Generated results are not distributed in Git. Reproduction requires running the
simulations with the recorded fdaPDE commits, or supplying the corresponding complete aggregates
and raw files required by the figure scripts. Full simulation runs require substantial compute. GCV
uses a deterministic seed of 0 and 100 stochastic trace probes, but exact timing and low-level
numerics remain platform-dependent. Alternative initialization sensitivity was not studied.

Figure panels require Cairo PDF support and Arial. Figure assembly requires Affinity and the
versioned `paper-figures/layouts/figures.af`; this proprietary layout step is not automated.
See the [simulation catalog](tests/README.md), [figure sources](paper-figures/README.md), and
[table sources](paper-tables/README.md) for experiment details and post-processing commands.
