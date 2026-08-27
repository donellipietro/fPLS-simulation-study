# Simulation-study paper tables

`scripts/` contains the generators for CSV tables used in the manuscript, and
`csv/` contains their reproducible outputs.

Run from the repository root:

```sh
make simulation_paper_tables
```

The generator reads the validated production aggregates under `results/` and
fails if a required experiment, diagnostic, repetition, or finite solution is
missing. Set `FPLS_RESULTS` only when the aggregate results live elsewhere.
In the GCV sensitivity families, the `lambda = 0` MV-PLS limit is validated but
excluded from the R1-fPLS iteration summaries because it is non-iterative.

The iteration outputs are:

- `fixed_h_iterations.csv`: component-wise median and maximum for experiments
  fitting four components;
- `varying_h_iterations.csv`: long-format summaries for the two varying-H
  experiments;
- `convergence_summary.csv`: global checks used by the manuscript statement.
