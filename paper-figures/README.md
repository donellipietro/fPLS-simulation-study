# Manuscript figure sources

The R scripts in `scripts/` convert complete simulation results into vector PDF panels for
“Rank-One Functional Partial Least Squares Regression”. Article and supplementary figures
are assembled in the Affinity document [`layouts/figures.af`](layouts/figures.af).

## Figure map

| Manuscript PDF | Script and result family |
|---|---|
| `1D_data.pdf` | `1D_data.R`; representative raw `1D/vary_k`, `k = 11` batch |
| `1D_vary_k.pdf` | `1D_vary_k.R`; aggregate `1D/vary_k` |
| `1D_qualitative.pdf` | `1D_qualitative.R`; aggregate and raw `1D/vary_k`, `k = 11,101` |
| `1D_vary_n.pdf` | `1D_vary_n.R`; aggregate `1D/vary_n` |
| `2D_qualitative.pdf` | `2D_qualitative.R`; representative raw `2D/vary_n`, `n = 100` batch |
| `2D_vary_H.pdf` | `2D_vary_H.R`; aggregate `2D/vary_H` |
| `S_1D_vary_m.pdf` | `S_1D_vary_m.R`; aggregate `1D/vary_m` |
| `S_1D_vary_nsrx.pdf`, `S_1D_vary_nsry.pdf` | corresponding scripts; 1D noise families |
| four `S_1D_gcv_*.pdf` exports | `S_1D_gcv_sensitivity.R`; two GCV sensitivity families |
| `S_2D_vary_n.pdf`, `S_2D_vary_m.pdf`, `S_2D_vary_k.pdf` | corresponding scripts and 2D families |
| `S_2D_vary_nsrx.pdf`, `S_2D_vary_nsry.pdf` | corresponding scripts and 2D noise families |
| `S_2D_vary_H_extended.pdf` | `S_2D_vary_H_extended.R`; predictive-order `vary_H` |
| `S_scheme.pdf` | editable Affinity master; no code-only generator |

## Generate panels

Follow the [setup and execution instructions](../README.md#setup-and-execution), then run each
suite (`1D`, `2D`, `GCV`, and `2D-predictive-order`) with `TEST_NAME=all` to prepare the complete
results. Panel export also requires R with Cairo PDF support and the Arial font installed on
your machine; `make build` installs the required R packages.

From the repository root, generate all manuscript panels with:

```sh
make simulation_figure_panels
```

The target loads `.env` when present, including the configured R library paths, and reads
`results/` by default. It requires complete `aggregate/all` trees for `1D`, `2D`, `GCV`, and
`2D-predictive-order`, together with the representative raw batches used by the figure scripts.
To use results stored elsewhere:

```sh
FPLS_RESULTS=/absolute/path/to/results make simulation_figure_panels
```

To generate only the panels produced by one script, set `FIGURE` to its name without `.R`:

```sh
make simulation_figure_panels FIGURE=1D_vary_k
```

Make loads the saved environment automatically for both commands. The same `FPLS_RESULTS`
prefix can also be used when selecting a single figure.

The RMSE panels use the noise-free references and normalization described in the
[metric definitions](../README.md#metrics-and-computational-boundary), preserving the signs of
the regression coefficient functions. GCV performance panels use aggregate results;
selected-penalty panels additionally require every raw `direction_gcv_h*.csv` and
`loading_gcv_h*.csv` file from the simulation run.

Panels are written below `paper-figures/panels/<figure-name>/`, relative to the repository root,
at the sizes defined by the scripts. Place panels in Affinity at 100% of their generated size.

R produces scientific marks, numeric ticks, and shared legends. Panel letters, display titles,
and axis labels are maintained in Affinity. The 1D qualitative layout also contains the
selection rectangles linking the `k = 11` and `k = 101` zoom panels.

## Reproducibility limit

`layouts/figures.af` is the editable assembly source, so composition requires proprietary
Affinity software and is not automated by Make. Running the panel scripts alone does not
reproduce the assembled layout. Recreating the manuscript PDFs requires opening the Affinity
document, relinking generated panels when needed, and exporting the corresponding figures.

The `vary` fit-time panels use log10 axes with ticks labelled in original units and median
lines. `vary_k` also includes reference guides for linear and quadratic growth in `k`; these
are not fitted complexity claims. GCV fit-time panels retain boxplots on a log10 time axis,
with tick labels in seconds.

The model colours used in the manuscript are defined in `scripts/common.R` and shared by
quantitative panels, qualitative curves, legends, and GCV comparisons.
