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

Running the same `make run_test` commands without `SMOKE_TEST=1` executes the
full configured grids and 30 replications and creates all of those production
figures. They remain candidate paper-facing outputs, not accepted paper
reproductions, until the provisional comparator, basis/RNG, metric, and
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

The submitted metric formula
`||A - A_hat||_F / (p q ||A||_F)` is implemented but remains explicitly
provisional pending final metric acceptance. Historical lambda grids, seeds,
location RNG adaptations, tolerance, iteration cap, and the precise meaning of
source `k` are also provisional.

The B/PB and MV comparator implementations are runnable candidates matching
the paper definitions, not accepted reproduction evidence. Aggregation can
mark an executed smoke or production run complete only after checking every
expected model, batch, raw output, provenance field, metric, and repetition.
It always leaves `paper_design_complete` and `paper_results_reproduced` false
until explicit scientific and numerical acceptance decisions are recorded.

## Excluded Scope

No application data or analysis, `test0`, full NSR cross-products, population
convergence, fPCA/fPCR revision benchmark, GCV-cost experiment, timing-only
benchmark, scaling report, near-zero-lambda diagnostic, or NSR-only revision
test is included.
