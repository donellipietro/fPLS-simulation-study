# fPLS Simulation Study

This repository contains the submitted fPLS simulation design and additional
diagnostic experiments. It follows the
`fdaPDE-test-bench` architecture through canonical `stable` commit `89ba803`
and uses the native `fdaPDE-cpp` implementation directly. The obsolete
fPLS-R fitting bridge is not used.

Generated dependencies, builds, data, queues, logs, results, figures, and
local reports remain repository-local and ignored.

## Test Suites

| Suite | Families | Purpose |
| --- | --- | --- |
| `1D` | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY` | Submitted curve simulations plus noise-sensitivity and fPCR comparisons |
| `2D` | `vary_k`, `vary_n`, `vary_NSRX`, `vary_NSRY`, `vary_H` | Submitted spatial simulations plus noise and component-prefix comparisons |
| `GCV` | sensitivity, large-sample, and near-zero-lambda families | Tuning behavior, cost, and numerical-stability diagnostics |
| `2D-predictive-order` | `all` | Experimental comparison of variance-ordered fPCR and response-relevant fPLS components |

Each suite has a scientific README under `tests/<suite>/README.md`. The
standard 1D and 2D families use 30 replications in production. The GCV and
predictive-order suites are separate diagnostic experiments.

## Methods

The one-dimensional comparisons include MV-PLS, fPCR, B-fPLS with regression
splines, B-fPLS with smoothing splines, PB-fPLS, and R1-fPLS. The spatial and
predictive-order comparisons use MV-PLS, fPCR, and R1-fPLS.

R1-fPLS and fPCR call `<fdaPDE/models.h>` through direct C++ drivers. Thin R
wrappers serialize inputs, invoke `cpp/run.sh`, validate outputs, and return
the standard testbench model object. Competitor code is adapted from the
corrected submitted implementation at historical design commit `7fb9172`.

All iterative fits use `tol = 1e-8` and `max_iter = 1000`; native GCV uses
seed `0`. The standard R1-fPLS and PB-fPLS tests use the shared `10^(-9:2)`
grid, while the GCV sensitivity families use `10^(-9:-2)`. B-fPLS with
smoothing splines retains its original `10^seq(-9, 2, by = 0.1)` grid.

## Native Dependency

Runtime profiles select the repository-local fdaPDE clone on branch
`develop_fPLS`. The native implementation is available at:

- outer fdaPDE-cpp: `ecbf23ef37571174c438ab68c3d21d7ecd5cf18f`
- fdaPDE/core gitlink: `1b75249a7b49ccee72cb94207a9dc5daaa21848c`

Native telemetry records both commits for every fit. R competitors record the
versions of the scientific packages used by their implementation.

## Workflow

Prepare the selected runtime profile:

```bash
make build PROFILE=macbook
```

Run reduced plumbing checks:

```bash
SMOKE_TEST=1 make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
SMOKE_TEST=1 make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
SMOKE_TEST=1 make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=all
SMOKE_TEST=1 make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=all
```

Omit `SMOKE_TEST=1` for the complete configured experiment. Individual
families can replace `all`. Matching complete batches are skipped, and
matching generated data are reused when a fit or evaluation must be refreshed.

The available profiles are `macbook`, `windows`, `hpc-slurm`, and
`hpc-torque`. The active profile owns compilers, dependency locations,
execution strategy, threading, and scheduler resources; suite configuration
owns the scientific design.

The `hpc-torque` profile submits compilation and test jobs through Torque/PBS.
Its resource requests can be overridden with the `PBS_*` and
`PBS_COMPILE_*` variables; set `PBS_DRY_RUN=1` or `PBS_COMPILE_DRY_RUN=1` to
preview submissions without scheduling jobs.

## Outputs

Batch results retain component-wise reconstructions, regression-coefficient
estimates, selected penalties, objective histories, iteration counts,
monotonicity flags, execution time, peak RAM, and implementation provenance.
`fit_seconds` measures method-specific preprocessing and tuning, fitting, and
in-memory post-processing. It excludes data generation, result serialization
and loading, and accuracy evaluation.
Aggregation validates the expected option cells and replications before
writing quantitative figures, diagnostic CSV files, qualitative comparisons,
and a standalone `legend.pdf` for each family.

The primary metrics compare response and predictor reconstructions with their
noise-free truths. All suites retain the sign-aligned, Frobenius-normalized beta
shape error. The GCV sensitivity families additionally use signed Frobenius
cosine similarity for beta and absolute cosine similarity for X directions,
loadings, and scores. The 2D qualitative maps use the ParaView
`Cool to Warm (Extended)` palette, include the domain boundary, and share the
truth range within each row.

## Generated Outputs

The near-zero-lambda family is a numerical diagnostic: non-finite fits are
recorded as failed observations rather than treated as successful estimates.
Generated production outputs are intentionally not versioned. Aggregate
`run_status.json` files retain operational completion, smoke-mode, output, and
configuration metadata; paper-facing claims and acceptance decisions belong to
the project integration record rather than these run artifacts.
