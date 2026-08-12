# Kami reviewer campaign (Torque/PBS)

Run every command below from the repository root on Kami.

The dedicated `kami_review_submit` target submits exactly one PBS job. Inside that allocation it
builds once, compiles all four C++ drivers once, then runs `1D/all`, `2D/all`, `GCV/all`, and
`2D-predictive-order/all` in that order through the serial runner. A failed stage stops the job;
families are never concurrent. The generic PBS runner is not used.

## Resource variables

Set these existing PBS variables for Kami before submission:

- `PBS_MULTI_CPUS` (required): every schedulable core on one complete node.
- `PBS_MULTI_MEM` (required): memory requested for the complete node, for example `128gb`.
- `PBS_MULTI_TIME` (required): wall time for the whole campaign, for example `72:00:00`.
- `PBS_QUEUE` and `PBS_ACCOUNT` (optional): the queue and account required by the site.
- `PBS_EXCLUSIVE_RESOURCE` (optional): the exact extra resource approved by the Kami
  administrators for exclusive placement, passed as one additional `qsub -l` value.

Torque has no portable exclusive-node flag. The target always requests
`nodes=1:ppn=$PBS_MULTI_CPUS`; this occupies a whole node only when the value is the node's full
core count and Kami's scheduling policy reserves all requested cores. If Kami exposes an explicit
resource such as a site-specific single-job access policy, set `PBS_EXCLUSIVE_RESOURCE` to the
administrator-provided value. If it does not, omit the variable, confirm the full-core policy with
the administrators, and treat the request as best effort rather than a guarantee.

`TESTBENCH_OUTPUT` may point to persistent scratch before submission. The profile creates root
links for generated outputs, so the paths below remain the handoff paths. Any existing compiler,
library, or fdaPDE environment overrides are inherited by `qsub -V`.

## Dry run and submission

First inspect the Make recipe and the exact `qsub` command; neither command submits work:

```sh
make -n kami_review_submit PROFILE=hpc-torque \
  PBS_MULTI_CPUS=<full-node-cores> PBS_MULTI_MEM=<full-node-memory> \
  PBS_MULTI_TIME=<campaign-walltime> PBS_QUEUE=<queue> PBS_ACCOUNT=<account>

make kami_review_submit PROFILE=hpc-torque PBS_DRY_RUN=1 \
  PBS_MULTI_CPUS=<full-node-cores> PBS_MULTI_MEM=<full-node-memory> \
  PBS_MULTI_TIME=<campaign-walltime> PBS_QUEUE=<queue> PBS_ACCOUNT=<account> \
  PBS_EXCLUSIVE_RESOURCE='<Kami-exclusive-resource>'
```

After replacing the placeholders, submit once by removing `PBS_DRY_RUN=1`:

```sh
make kami_review_submit PROFILE=hpc-torque \
  PBS_MULTI_CPUS=<full-node-cores> PBS_MULTI_MEM=<full-node-memory> \
  PBS_MULTI_TIME=<campaign-walltime> PBS_QUEUE=<queue> PBS_ACCOUNT=<account> \
  PBS_EXCLUSIVE_RESOURCE='<Kami-exclusive-resource>'
```

Omit `PBS_QUEUE`, `PBS_ACCOUNT`, or `PBS_EXCLUSIVE_RESOURCE` when Kami does not require or expose
them. The submission prints a run directory under `logs/kami/`; its `job_id.txt` is the value to
pass to `qstat`.

## Execution order and status

The single job performs these fail-fast stages:

1. `make build PROFILE=hpc-torque` once.
2. `make compile_all PROFILE=hpc-torque COMPILE_STRATEGY=local` once, on the allocated node.
3. `./tests/run_tests.sh 1D all`.
4. `./tests/run_tests.sh 2D all`.
5. `./tests/run_tests.sh GCV all`.
6. `./tests/run_tests.sh 2D-predictive-order all`.
7. `make review_tables` to validate the production aggregates and generate the reviewer CSVs.

Each serial runner finishes its aggregation before the next suite starts and pins solver/BLAS
thread counts to one. `logs/kami/<run-tag>/final_status.txt` records success or failure, the last
stage, timestamps, job id, and Git commit. PBS stdout and stderr are in `job.out` and `job.err` in
the same directory.

## Files to retain and download

After PBS reports the job complete, retain exactly these handoff outputs:

- `results/`, including every suite aggregate and
  `results/GCV/aggregate/all/run_status.json`;
- `images/`;
- `logs/`, including `logs/kami/<run-tag>/job_id.txt`, `job.out`, `job.err`, and
  `final_status.txt`;
- `reports/gcv_tables/*.csv`;
- `reports/review_tables/*.csv`.

The raw generated data under `data/` and queue/work files under `tmp/` are not required for report
aggregation and may be left out of the handoff package. If output paths are symlinks into scratch,
use `tar -h` so their contents, rather than only the links, are archived:

```sh
tar -chzf fpls-review-kami.tar.gz \
  results images logs reports/gcv_tables reports/review_tables
```
