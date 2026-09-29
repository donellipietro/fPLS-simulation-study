# Manuscript figure sources

The R scripts in `scripts/` convert complete simulation results into vector panels. Article and
supplementary PDFs are assembled in the versioned Affinity document
`layouts/figures.af`; generated panels and exports are ignored.

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

From the repository root, point `FPLS_RESULTS` to a result root containing the complete suite
aggregates and run either one script or the complete target:

```sh
FPLS_RESULTS=/absolute/path/to/results Rscript paper-figures/scripts/1D_vary_k.R
FPLS_RESULTS=/absolute/path/to/results make simulation_figure_panels
```

The scripts stop when required aggregate or representative raw files are missing. GCV
performance panels use aggregate results; selected-penalty panels additionally require every
raw `direction_gcv_h*.csv` and `loading_gcv_h*.csv` file from the production campaign.

Panels are written below `panels/<figure-name>/` at the sizes defined by the scripts.
They require R with Cairo PDF support and Arial. Place panels in Affinity at 100% of their
generated size.

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
