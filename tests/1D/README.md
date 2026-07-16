# 1D Simulation Study

This suite studies multivariate functional PLS on curves observed over the
unit interval. Each simulated sample has four latent functional components and
two correlated responses. The final predictor component is deliberately
contaminated, making recovery of the smaller latent structure informative.

The suite compares ordinary multivariate PLS, the submitted basis-expansion
fPLS variants, and R1-fPLS. It reports response reconstruction, predictor
reconstruction, and regression-coefficient shape error as the number of mesh
nodes (`vary_k`), statistical units (`vary_n`), or observed locations
(`vary_m`) changes.

All families use 30 replications in a production run and four retained
components. The output also reports wall-clock time, peak memory, and selected
regularisation parameters. The `vary_k` report includes a qualitative beta
comparison at coarse and fine supports.
