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
inputs. Interpretive comments remain hand-written in the TeX and are never generated.

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
compatible aggregate under `aggregate/all`, the relevant grouped target, or the individual
family; validates production completeness; and overwrites the committed CSV snapshots. The
iteration tables report medians across every level and repetition in a family. A dash denotes a
non-iterative method or unavailable iterative diagnostics.

## GCV outputs used by the report

For `sensitivity` and `sensitivity_high_NSRX`, `tests/GCV/aggregate_results.R` validates and
plots all of the following:

- RMSE for prefix reconstructions of X and Y;
- paper-compatible, sign-aligned normalized beta shape-RMSE (`Beta1_locations.pdf`);
- signed Frobenius beta cosine (`Beta_locations.pdf`), used by the GCV tables;
- absolute cosines for directions, loadings, and scores;
- compute telemetry (`fit_seconds.pdf` and `peak_ram_mib.pdf`).

The six paper figure crops under `reports/paper_figure_crops/` are external submitted-manuscript
assets, not simulation outputs. Their original extraction script and source-PDF version are not
stored in this repository, so exact regeneration of those six comparison images remains an
evidence gap.
