# Simulation-study figure assets

`scripts/` contains one R entry point for each simulation-study figure in the
current manuscript. Each script writes only the independent panels needed for
the Affinity layout into `panels/<figure-name>/`.

Run a script from the simulation-study checkout, for example:

```sh
Rscript paper-figures/scripts/1D_vary_k.R
```

To regenerate every simulation-study panel in one command, run:

```sh
make simulation_figure_panels
```

The scripts read this checkout's aggregated `results/` outputs. Set
`FPLS_RESULTS` only if they live elsewhere.

The PDFs are final-size vector panels for a 174 mm-wide figure. Do not resize
them in Affinity: place them at 100%. The quantitative panels are 84.3 ×
51.2 mm, the 2D maps are 36.0 mm square, and the two Simulation 1 data panels
are 52.9 mm square and 116.1 × 52.9 mm. `layouts/figures.af` is the versioned
Affinity master; `exports/` and regenerated panel PDFs are intentionally
ignored.

Panel lettering, titles, and axis labels belong in Affinity. Numeric tick marks
and the one shared legend supplied for each quantitative figure remain in the
scientific graphic and are therefore produced by R.

The 1D qualitative figure provides one linked zoom panel for each of `k = 11`
and `k = 101`; draw the corresponding selection rectangles in Affinity.

`S_1D_gcv_sensitivity.R` writes the panels for the two GCV sensitivity
conditions. Performance panels are always regenerated from their aggregated
results. Selection panels (combined GCV curves with selected-lambda markers)
are written only when the Kami run has supplied every `*_gcv_h*.csv` raw file.

`05_2d_vary_H.R` writes the RMSE and reconstructed-structure panels for the
`vary_H` experiment, plus a vertical model legend for the bottom-right slot.

The four supplementary noise-ratio scripts (`S_1D_vary_nsrx.R`,
`S_1D_vary_nsry.R`, `S_2D_vary_nsrx.R`, and `S_2D_vary_nsry.R`) follow the same
panel layouts as the corresponding `vary_n` figures.

`S_2D_vary_H_extended.R` writes the same panel set for the
ten-component predictive-order experiment (`H = 1, ..., 10`).

The `vary` fit-time panels use log10 axes with ticks labelled in original units,
median lines, and (only for `vary_k`) dashed/dot-dashed slope guides for
linear/quadratic growth in k. These guides are references, not fitted complexity claims.
Their labels have a small white background to stay clear of grid lines. GCV
fit-time panels retain the original boxplots on a log10 time axis, with tick labels in seconds. Run
`Rscript paper-figures/scripts/check_time_panels.R` to check both panel types.

The approved model palette is defined once in `scripts/common.R` and applied
when reading figure data, without modifying aggregated result archives. It is
shared by quantitative panels, qualitative curves, legends, and GCV model colours.
fPCR uses the approved green `#2D9950`; fixed-lambda GCV comparisons keep their light-blue category.
