# Manuscript table sources

`scripts/generate_iteration_tables.R` checks production diagnostics and writes the CSV
summaries supporting the Supplementary Material's R1-fPLS convergence table and the article's
global convergence statements.

Follow the [setup and execution instructions](../README.md#setup-and-execution), then run each
suite (`1D`, `2D`, `GCV`, and `2D-predictive-order`) with `TEST_NAME=all` to prepare the complete
results. `make build` installs the required R packages.

From the repository root, generate all manuscript CSV tables with:

```sh
make simulation_paper_tables
```

The target loads `.env` when present, including the configured R library paths, and reads
`results/` by default. To use results stored elsewhere:

```sh
FPLS_RESULTS=/absolute/path/to/results make simulation_paper_tables
```

The result root must contain complete production results under
`results/<TEST_SUITE>/aggregate/<TEST_NAME>/` for the required experiments in `1D`, `2D`, `GCV`,
and `2D-predictive-order`. The generator fails if a required family, level, repetition, diagnostic,
or finite solution is missing. The non-iterative `lambda = 0` MV-PLS benchmark in the GCV
sensitivity families is checked but excluded from R1-fPLS iteration summaries.

The generated files are saved in `paper-tables/csv/`, relative to the repository root:

- `fixed_h_iterations.csv`: component-wise median and maximum for four-component experiments;
- `varying_h_iterations.csv`: long-format summaries for the two varying-H experiments;
- `convergence_summary.csv`: global finite-solution and iteration-cap counts, plus median and
  maximum iteration counts supporting the manuscript text.

The checked-in manuscript contains formatted values rather than including these CSV files
directly. Regeneration therefore checks the recorded aggregate values but does not edit the
paper. Production diagnostics are external to Git; without them the tables cannot be rebuilt.
