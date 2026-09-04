# fPLS simulation study

This repository contains the simulation code supporting the article and Supplementary Material
for the R1-fPLS paper. The submitted branch is reviewer-facing: it contains the retained
scientific suites, production/aggregation machinery, manuscript figure and table sources, and
the editable Affinity layout. Generated data, fitted models, aggregate results, logs, panels,
and exported PDFs are intentionally outside Git.

The accepted numerical evidence was produced from commit
`a6f18492d821de36ee1093e30ffed4be9f4f8711`. Final manuscript figure sources were reviewed at
`f098249e782b794d118d1da624ac0146bc1f6114`. This branch documents and packages those workflows;
it does not claim that the production campaign was rerun after either commit.

## Paper map

| Suite/family | Article or Supplementary Material output |
|---|---|
| `1D/vary_k` | Article: Simulation 1 data, varying-basis and qualitative-beta figures |
| `1D/vary_n` | Article: Simulation 1 sample-size figure |
| `1D/vary_m` | Supplement: varying observed locations |
| `1D/vary_NSRX`, `1D/vary_NSRY` | Supplement: Simulation 1 noise robustness |
| `2D/vary_H` | Article: Simulation 2 retained-component figure |
| `2D/vary_n` | Article: representative beta maps; Supplement: sample-size figure |
| `2D/vary_m`, `2D/vary_k` | Supplement: observation- and mesh-resolution figures |
| `2D/vary_NSRX`, `2D/vary_NSRY` | Supplement: Simulation 2 noise robustness |
| `GCV/sensitivity`, `GCV/sensitivity_high_NSRX` | Supplement: GCV performance and selected-penalty figures |
| `GCV/small_lambda_m_gt_k`, `GCV/small_lambda_m_lt_k` | Supplement: fixed-penalty numerical checks for `m > k` and `m < k` |
| `2D-predictive-order/vary_H` | Supplement: low-predictor-variance predictive-order experiment |

fPCR is a reported benchmark only for Simulation 2 and the predictive-order experiment. The 1D
runner retains an fPCR implementation for source compatibility, but the paper-facing 1D figures
compare MV-PLS, the B-fPLS variants, PB-fPLS, and R1-fPLS.

## Prerequisites

- GNU Make, Bash, Git, R and a C++17 compiler;
- Eigen and the system libraries needed by the selected profile;
- the CRAN packages installed by `src/installation/install_femR.R`, plus `MASS`, `PRIMME`, and
  `cowplot` for data generation, 2D eigensolvers, and GCV figure composition;
- `fdaPDE-cpp` with its `fdaPDE/core` dependency. `make build` obtains the configured
  `develop_fPLS` branch through `cpp/clone_fdapde.sh`; production provenance records the exact
  outer and core commits used by each fit;
- Docker for the `windows` profile, or Apptainer/Singularity plus a scheduler for HPC profiles.

Available profiles are `macbook`, `windows`, `hpc-slurm`, and `hpc-torque`. Profile defaults are
machine-specific and may need environment overrides; inspect them with:

```sh
make config PROFILE=macbook
```

## Setup and execution

Prepare a runtime and compile one suite:

```sh
make build PROFILE=macbook
make compile PROFILE=macbook MODEL=1D
```

Run a retained family or all retained families in a suite:

```sh
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=vary_k
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=all
```

Production option cells use 30 replications and single-threaded model fits. `SMOKE_TEST=1`
reduces option grids and replications for plumbing checks, but still fits models and is not a
substitute for production evidence.

`make kami_review_submit` is optional cluster-specific infrastructure. It builds and executes
all retained suites serially inside one full-node Torque/PBS allocation, while individual fits
remain restricted to one computational thread. Use `PBS_DRY_RUN=1` to inspect the submission
command without submitting a job.

## Result flow and expected outputs

The standard flow is:

```text
generate_options.R -> queued JSON -> main.R batches -> fitted/evaluation files
                   -> aggregate_results.R -> results/<suite>/aggregate/<group>
```

A complete aggregate contains `run_status.json`, completeness information, diagnostics, paper
metrics, and `loaded_<family>.rds` files. Serial production runs also write runtime metadata with
host, CPU, RAM, scheduler allocation, thread settings, timestamp, and Git commit.

Set `TESTBENCH_OUTPUT` before setup to place generated trees outside the checkout. For existing
aggregates, figure and table scripts accept `FPLS_RESULTS=/absolute/path/to/results`. The expected
external root contains `1D`, `2D`, `GCV`, and `2D-predictive-order`, each with an
`aggregate/all` directory. Never substitute incomplete raw subtrees for validated aggregates.

## Metrics and computational boundary

Paper-facing RMSE values compare fitted quantities with their noise-free references. Regression
coefficient functions are normalized separately to unit Frobenius norm and sign-aligned before
RMSE evaluation. The GCV sensitivity families additionally retain signed Frobenius cosine for
the cumulative beta and absolute cosine for component-wise directions, loadings, and scores.

`fit_seconds` is compute-only: it includes method-specific preprocessing/tuning, fitting, and
in-memory post-processing, but excludes data generation, result I/O, and accuracy evaluation.
It is not total campaign runtime and must not be compared across different hardware as though it
were. The paper reports wall time, peak resident memory, and iteration counts; no processor-
utilization claim is supported.

## Reproducibility boundary

The manuscript figures were generated from complete validated aggregate trees with 30
replications per option cell. The external raw archive is supporting evidence, not part of the
submitted branch. Reproduction therefore requires external storage, the recorded fdaPDE commits,
and substantial compute. GCV uses a deterministic seed of 0 and 100 stochastic trace probes,
but exact timing and low-level numerics remain platform-dependent. Alternative initialization
sensitivity was not studied.

Figure panels require Cairo PDF support and Arial. Final assembly requires Affinity and the
versioned `paper-figures/layouts/figures.af`; this proprietary layout step is not automated.
See `paper-figures/README.md` and `paper-tables/README.md` for post-processing commands.
