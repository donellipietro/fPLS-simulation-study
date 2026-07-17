# fPLS Simulation Study

This repository contains the submitted fPLS simulation design and the
additional experiments prepared for peer review. It follows the
`fdaPDE-test-bench` architecture through canonical `stable` commit `167e8c2`
and uses the native `fdaPDE-cpp` implementation directly. The obsolete
fPLS-R fitting bridge is not used.

Generated dependencies, builds, data, queues, logs, results, figures, and
local reports remain repository-local and ignored.

## Test Suites

| Suite | Families | Purpose |
| --- | --- | --- |
| `1D` | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY` | Submitted curve simulations plus noise-sensitivity and fPCR comparisons |
| `2D` | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY`, `vary_H` | Submitted spatial simulations plus noise and component-prefix comparisons |
| `GCV` | sensitivity, competitor, large-sample, and near-zero-lambda families | Review diagnostics for tuning behavior, cost, and numerical stability |
| `2D-predictive-order` | `all` | Experimental comparison of variance-ordered fPCR and response-relevant fPLS components |

Each suite has a scientific README under `tests/<suite>/README.md`. The
standard 1D and 2D families use 30 replications in production. The GCV and
predictive-order suites are review extensions and remain separate from the
submitted-design validation.

## Methods

The one-dimensional comparisons include MV-PLS, fPCR, B-fPLS with regression
splines, B-fPLS with smoothing splines, PB-fPLS, and R1-fPLS. The spatial and
predictive-order comparisons use MV-PLS, fPCR, and R1-fPLS.

R1-fPLS and fPCR call `<fdaPDE/models.h>` through direct C++ drivers. Thin R
wrappers serialize inputs, invoke `cpp/run.sh`, validate outputs, and return
the standard testbench model object. Competitor code is adapted from the
corrected submitted implementation at historical design commit `7fb9172`.

All iterative fits use `tol = 1e-8` and `max_iter = 1000`; native GCV uses
seed `0`. R1-fPLS and PB-fPLS use the shared `10^(-9:2)` grid. B-fPLS with
smoothing splines retains its original `10^seq(-9, 2, by = 0.1)` grid.

## Native Dependency

Runtime profiles select the repository-local fdaPDE clone on branch
`develop_fPLS`. The review implementation is available at:

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

The available profiles are `macbook`, `windows`, and `hpc-slurm`. The active
profile owns compilers, dependency locations, execution strategy, threading,
and scheduler resources; suite configuration owns the scientific design.

## Outputs

Batch results retain component-wise reconstructions, regression-coefficient
estimates, selected penalties, objective histories, iteration counts,
monotonicity flags, execution time, peak RAM, and implementation provenance.
Aggregation validates the expected option cells and replications before
writing quantitative figures, diagnostic CSV files, qualitative comparisons,
and a standalone `legend.pdf` for each family.

The primary metrics compare response and predictor reconstructions with their
noise-free truths. The beta metric is a sign-aligned, Frobenius-normalized
shape error. The 2D qualitative maps use the ParaView `Cool to Warm (Extended)`
palette, include the domain boundary, and share the truth range within each
row.

## Validation Status

The submitted 1D and 2D behavior has been validated against the submitted
simulation study. Production review runs are complete for the GCV,
noise-sensitivity, component-prefix, and predictive-order extensions. The
near-zero-lambda family is a numerical diagnostic: non-finite fits are
recorded as failed observations rather than treated as successful estimates.

Generated production outputs are intentionally not versioned. Scientific
claims and paper-facing selections must therefore cite the retained aggregate
status and provenance from the corresponding completed run.
