# fPLS Simulation Study

This repository ports the submitted fPLS simulations to the current
`fdaPDE-test-bench` architecture and the outer `fdaPDE-cpp` branch
`develop_fPLS`. It was generated from testbench commit `e92e1a1` with fresh
Git history. All generated dependencies, builds, data, queues, logs, results,
and images remain repository-local and ignored.

## Test Suites

The scientific code is divided into two self-contained testbench suites.

### `1D`

| Test | Production levels | Fixed setting |
| --- | --- | --- |
| `vary_k` | `k = 5, 11, 21, 51, 101` | `n = 100`, `m = 200` |
| `vary_n` | `n = 50, 100, 200` | `m = 200`; R1 `k = 51`; B/PB `k = 11` |
| `vary_m` | `m = 50, 100, 200` | `n = 100`; R1 `k = 51`; B/PB `k = 11` |

Models, in paper plotting order: MV-PLS, B-fPLS with regression splines,
B-fPLS with smoothing splines, PB-fPLS, and R1-fPLS.

### `2D`

| Test | Production levels | Fixed setting |
| --- | --- | --- |
| `vary_k` | `k = 25, 100, 400, 900, 1600, 2500` | `n = 100`, `m = 1600` |
| `vary_n` | `n = 50, 100, 200` | `k = 900`, `m = 1600` |
| `vary_m` | `m = 900, 1600, 2400` | `n = 100`, `k = 900` |

Models: MV-PLS and R1-fPLS. The submitted paper restricts B-fPLS and PB-fPLS
to scalar responses on one-dimensional supports. The 2D `vary_n` family and
its `n = 100`, `k = 900`, `m = 1600` beta scenario are submitted-paper
experiments. The requested 2D `vary_k` and `vary_m` families are retained and
explicitly labeled as Pietro-requested historical families.

Every production option fixes final-component `NSR_X = 3`, `NSR_Y = 0.1`,
and 30 replications. Historical NSR Cartesian products are not generated.

## Native Integration

`cpp/1D/main.cpp` and `cpp/2D/main.cpp` call `<fdaPDE/models.h>` directly and
compile through the standard suite-selected target. Their thin suite-local R
wrappers serialize inputs, call `cpp/run.sh`, validate outputs, and return the
standard testbench model object. No historical R fitting bridge is used.

Native fits preserve CSV inputs, parameters, every component-wise output,
selected lambdas, telemetry, and outer/core commit provenance under the
standard batch result directory. R competitors preserve their component-wise
fits, calibration details, telemetry, and provenance in the same batch cache.

## Competitor Provenance

The fdaPDE-R fitting bridge remains archaeology and is not used. MV-PLS and
the B-fPLS/PB-fPLS competitors are adapted from Pietro's corrected competitor
implementation at historical design commit `7fb9172`, while retaining the
standard testbench model and batch contracts. The adaptation uses `pls::plsr`
with orthogonal-scores PLS, the source B-spline coefficient representation,
and the source coefficient-function projection.

The submitted paper and corrected implementation agree on the competitor
families but require more precise wording in five places. Source `k` is the
number of spline breakpoints and produces `k + 2` cubic B-spline basis
functions. The smoothing-spline B-fPLS lambda is the kernel-density mode on
the log10 scale of per-curve GCV optima. PB-fPLS uses five folds inherited
from the RNG state immediately after each batch's data generation; the exact
fold assignments are retained with every fit. Finally, source PB validation
passes the untransformed basis-coefficient matrix to the prediction method
for a model fitted in the penalty-transformed space. That last source-era
detail is reproduced for figure fidelity and remains a methodological point
to state or revise explicitly, not something the migration silently changes.
The reported beta curves also use the corrected source's coefficient-space
projection rather than being reconstructed from the fitted response.

## Workflow

```bash
make build PROFILE=macbook
SMOKE_TEST=1 make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
SMOKE_TEST=1 make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
```

The standard testbench owns configuration, cloning, compilation, queues,
execution strategy, batch files, result loading, telemetry, aggregation, and
quantitative plotting. Each family produces three metric PDFs and a standalone
`legend.pdf`. Production 1D `vary_k` also creates the `k=11/101` qualitative
beta comparison; production 2D `vary_n` creates the representative beta maps.
Boxplots use the submitted black-outline style. The 1D `vary_k` plots retain
the submitted figure ranges, and its qualitative beta comparison normalizes
and sign-aligns coefficient shapes before plotting. MV-PLS is shown at its
observed vertices, functional curves are restricted to the observed support,
and `data_1D.pdf` uses the submitted pink-to-purple palette.

Running the same `make run_test` commands without `SMOKE_TEST=1` executes the
full configured grids and 30 replications and creates all of those production
figures. They remain candidate paper-facing outputs, not accepted paper
reproductions, until the competitor-description, basis/RNG, metric, and
numerical-matching decisions below are resolved.

Cached fit paths do not encode smoke mode. Before switching this working copy
from smoke to production, clean each family through the standard target:

```bash
for suite in 1D 2D; do
  for family in vary_k vary_n vary_m; do
    make clean_test PROFILE=macbook TEST_SUITE="$suite" TEST_NAME="$family"
  done
done
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=all
```

## Provisional Contract

Paper-facing plots default to the committed source-era figure metrics: ordinary
RMSE for `Y` and `X`, and sign-aligned unit-norm shape RMSE for `beta`. The
submitted manuscript formula `||A - A_hat||_F / (p q ||A||_F)` is retained in
every batch evaluation as `submitted_normalized_rmse`. Both remain explicitly
provisional because the submitted notation and source evaluator disagree.
Historical lambda grids, seeds, location RNG adaptations, tolerance, iteration
cap, and the precise meaning of source `k` are also provisional.

The B/PB implementation now reproduces Pietro's corrected source mechanics
rather than a paper-definition reimplementation. This resolves the previous
custom PB behavior, but it does not by itself validate the paper's current
method description: basis-count semantics, inherited fold RNG, validation
space, and the source coefficient projection remain explicit source-era
details. Aggregation can mark an executed smoke or production run complete
only after checking every expected model, batch, raw output, provenance field,
metric, and repetition. It always leaves `paper_design_complete` and
`paper_results_reproduced` false until the scientific wording, final metric,
and numerical matching are accepted.

## Excluded Scope

No application data or analysis, `test0`, full NSR cross-products, population
convergence, fPCA/fPCR revision benchmark, GCV-cost experiment, timing-only
benchmark, scaling report, near-zero-lambda diagnostic, or NSR-only revision
test is included.
