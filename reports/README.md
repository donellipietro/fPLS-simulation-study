# Reviewer report

`review_simulation_results.tex` is the reviewer-facing report source. Run the full
simulation families and their aggregators first, then regenerate every data-backed table and
compile the report with:

```sh
make review_report
```

To refresh only the CSV snapshots, use `make review_tables`. For a focused plumbing check,
`Rscript reports/generate_review_tables.R gcv design` accepts any combination of `gcv`,
`design`, and `iterations`; the no-argument command used by Make requires all production
inputs. Run `Rscript tests/smoke_generate_review_tables.R` for the temporary-fixture validation
and atomicity smoke check.

The tables and the metrics they display are generated and validated automatically; the CSV
snapshots are ignored rather than versioned. Numeric values embedded in prose and all
interpretive comments remain hand-written in the TeX; this pipeline does not update or validate
those narrative claims.

## Table provenance

| Report table | Production input | CSV consumed by TeX |
|---|---|---|
| Submitted paper design | `tests/1D/utils/generate_options.R`, `tests/2D/utils/generate_options.R`, and the representative settings exported by the two `plot_qualitative_results.R` scripts | `review_tables/submitted_design.csv` |
| 1D iteration/monotonicity: `vary_k` | `tests/1D/aggregate_results.R` → `vary_k_diagnostics.csv` | `review_tables/1D_vary_k_iterations.csv` |
| 1D iteration/monotonicity: `vary_n` | `tests/1D/aggregate_results.R` → `vary_n_diagnostics.csv` | `review_tables/1D_vary_n_iterations.csv` |
| 1D iteration/monotonicity: `vary_m` | `tests/1D/aggregate_results.R` → `vary_m_diagnostics.csv` | `review_tables/1D_vary_m_iterations.csv` |
| 2D iteration/monotonicity: `vary_n` | `tests/2D/aggregate_results.R` → `vary_n_diagnostics.csv` | `review_tables/2D_vary_n_iterations.csv` |
| 2D iteration/monotonicity: `vary_k` | `tests/2D/aggregate_results.R` → `vary_k_diagnostics.csv` | `review_tables/2D_vary_k_iterations.csv` |
| GCV standard: RMSE Y, RMSE X, signed beta cosine, absolute direction/loading/score cosines | `tests/GCV/aggregate_results.R` → `loaded_sensitivity.rds` | `gcv_tables/sensitivity_{Y_reconstruction,X_reconstruction,Beta,X_direction,X_loading,X_scores}.csv` |
| GCV high-NSRX: the same six metrics | `tests/GCV/aggregate_results.R` → `loaded_sensitivity_high_NSRX.rds` | `gcv_tables/sensitivity_high_NSRX_{Y_reconstruction,X_reconstruction,Beta,X_direction,X_loading,X_scores}.csv` |

`reports/generate_review_tables.R` is the only CSV writer in this chain. It selects the newest
candidate under `aggregate/all`, the relevant grouped target, or the individual family and then
fails closed unless its paired `run_status.json` is present, complete, non-smoke, schema-compatible,
and coherent with the suite, target, and family. File modification times are not used to pair the
status with the aggregate: archive tools and cloud synchronization can rewrite those times without
changing the validated contents. For GCV, schema 6, all 30 repetitions, beta RMSE, prefix truth,
and the exact `-1, 0, 10^-9, ..., 10^-2` sensitivity grid are mandatory for both families. An
invalid newest candidate is an error; it is never treated as schema 6 or silently replaced by an
older candidate.

Every requested CSV is generated below one staging directory. Existing snapshots are replaced
only after every requested section has succeeded, with rollback on an installation error. The
iteration tables report medians across every level and repetition in a family. A dash denotes an
explicitly non-iterative method; missing fPCR or R1-fPLS iteration/monotonicity diagnostics are an
error.

## GCV outputs used by the report

For `sensitivity` and `sensitivity_high_NSRX`, `tests/GCV/aggregate_results.R` validates and
plots all of the following:

- RMSE for prefix reconstructions of X and Y;
- paper-compatible, sign-aligned normalized beta shape-RMSE (`Beta1_locations.pdf`);
- signed Frobenius beta cosine (`Beta_locations.pdf`), used by the GCV tables;
- absolute cosines for directions, loadings, and scores;
- compute telemetry (`fit_seconds.pdf` and `peak_ram_mib.pdf`).

The six original submitted-paper figures are expected under the ignored `reports/paper_figures/` directory.
The expected files are `1d_test3.pdf`, `qualitative_1D.pdf`, `1d_test1.pdf`, `1d_test2.pdf`,
`2d_beta.pdf`, and `2d_test1.pdf`. They are copied from the paper checkout for local report
compilation, but are not simulation outputs and are not tracked here. If an original is absent,
the TeX compiles with a red `Asset esterno mancante` placeholder that states that no substitute
result is being shown.
