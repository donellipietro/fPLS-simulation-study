# Predictive Component Ordering In 2D

This experimental suite isolates the difference between components ordered by
predictor variance and components ordered by relevance to the response. It is
kept separate from the submitted 2D suite.

## Scientific Design

The predictor contains ten mutually orthogonal smooth spatial components. Their
sample variances decrease exactly as `1.0, 0.9, ..., 0.1` in every repetition.
The two response coordinates depend only on smooth predictor components 9 and
10, with scaling chosen so that both contribute equal response variance. The
earlier high-variance components are rougher and unrelated to the response.
The last predictor component is therefore necessary for complete response
reconstruction even though it explains the least predictor variance and the
first nine components already explain 98.2 percent of total predictor variance.

MV-PLS, fPCR, and R1-fPLS are each fitted once with ten components. Results are
then evaluated for the progressive prefixes `H = 1, ..., 10`. The central
comparison is response reconstruction: fPCR should need the late
variance-ordered components, whereas the two PLS methods can prioritize the
directions that explain the response. Predictor reconstruction is retained to
show the complementary advantage of variance ordering.

The experiment uses `n = 200`, `m = 900`, a `20 x 20` finite-element mesh,
30 repetitions, predictor-noise ratio `0.01` relative to the final component,
and response-noise ratio `0.01`. These low-noise settings isolate component
ordering from signal detectability. All iterative methods use `tol = 1e-8`,
`max_iter = 1000`, and GCV seed `0`.

## Outputs

The suite writes component-wise response, predictor, and coefficient-shape
errors; execution time, peak RAM, selected penalties, iteration counts, and
monotonicity diagnostics; a standalone model legend; and `latent_design.pdf`,
which records the imposed predictor-variance and response-relevance ordering.

Run the reduced plumbing check or the complete experiment with:

```bash
SMOKE_TEST=1 make run_test TEST_SUITE=2D-predictive-order TEST_NAME=all
make run_test TEST_SUITE=2D-predictive-order TEST_NAME=all
```
