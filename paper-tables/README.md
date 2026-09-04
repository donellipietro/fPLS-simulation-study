# Manuscript table sources

`scripts/generate_iteration_tables.R` checks production diagnostics and writes the CSV
summaries supporting the Supplementary Material's R1-fPLS convergence table and the article's
global convergence statements.

From the repository root:

```sh
FPLS_RESULTS=/absolute/path/to/results make simulation_paper_tables
```

The result root must contain complete non-smoke `aggregate/all` trees for `1D`, `2D`, `GCV`, and
`2D-predictive-order`. The generator fails if a required family, level, repetition, diagnostic,
or finite solution is missing. The non-iterative `lambda = 0` MV-PLS benchmark in the GCV
sensitivity families is checked but excluded from R1-fPLS iteration summaries.

Generated files under `paper-tables/csv/` are ignored:

- `fixed_h_iterations.csv`: component-wise median and maximum for four-component experiments;
- `varying_h_iterations.csv`: long-format summaries for the two varying-H experiments;
- `convergence_summary.csv`: global finite-solution, iteration-cap, monotonicity, median, and
  maximum checks used by the manuscript text.

The checked-in manuscript contains formatted values rather than including these CSV files
directly. Regeneration therefore checks the recorded aggregate values but does not edit the
paper. Production diagnostics are external to Git; without them the tables cannot be rebuilt.
