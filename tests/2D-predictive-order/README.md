# Predictive Component Ordering In 2D

This experimental suite isolates the difference between components ordered by
predictor variance and components ordered by relevance to the response. It is
kept separate from the submitted 2D suite.

## Scientific Design

The data generator is the submitted 2D generator extended from four to ten
trigonometric spatial components. Scores are independently sampled as in the
submitted test, with decreasing population variances. The two response
coordinates depend only on predictor components 9 and 10, scaled to have equal
response variance. The earlier high-variance components are unrelated to the
response. A noiseless multivariate PLS decomposition verifies exact
reconstruction of both `X` and `Y` before noise is added.
The last predictor component is therefore necessary for complete response
reconstruction even though it explains the least predictor variance and the
first nine components already explain 98.2 percent of total predictor variance.

MV-PLS, fPCR, and R1-fPLS are each fitted once with ten components. Results are
then evaluated for the progressive prefixes `H = 1, ..., 10`. The central
comparison is response reconstruction: fPCR should need the late
variance-ordered components, whereas the two PLS methods can prioritize the
directions that explain the response. Predictor reconstruction is retained to
show the complementary advantage of variance ordering.

The experiment uses the submitted 2D setting: `n = 100`, `m = 1600`, a
`30 x 30` finite-element mesh, 30 repetitions, predictor-noise ratio `3`
relative to the final component, and response-noise ratio `0.1`. All iterative
methods use `tol = 1e-8`, `max_iter = 1000`, and GCV seed `0`.

## Outputs

The suite writes component-wise response, predictor, and coefficient-shape
errors; observed `X`/`Y` variance and `X`--`Y` cross-covariance reconstruction;
execution time, peak RAM, selected penalties, iteration counts, and monotonicity
diagnostics; a standalone model legend; and `latent_design.pdf`, which records
the imposed predictor-variance and response-relevance ordering.

Run the reduced plumbing check or the complete experiment with:

```bash
SMOKE_TEST=1 make run_test TEST_SUITE=2D-predictive-order TEST_NAME=all
make run_test TEST_SUITE=2D-predictive-order TEST_NAME=all
```
