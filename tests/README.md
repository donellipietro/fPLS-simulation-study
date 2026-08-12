# Simulation Suites

| Suite | Effective families | Primary varying quantity |
|---|---|---|
| [`1D`](1D/README.md) | `vary_k`, `vary_n`, `vary_m`, `vary_NSRX`, `vary_NSRY` | curve resolution, sample size, observed locations, predictor noise, response noise |
| [`2D`](2D/README.md) | `vary_k`, `vary_n`, `vary_NSRX`, `vary_NSRY`, `vary_H` | mesh resolution, sample size, predictor noise, response noise, retained components |
| [`GCV`](GCV/README.md) | `sensitivity`, `sensitivity_high_NSRX`, `lambda_to_zero`, `small_lambda_m_gt_k`, `small_lambda_m_lt_k` | tuning rule, sample size, or fixed near-zero penalty |
| [`2D-predictive-order`](2D-predictive-order/README.md) | `vary_H` | progressive prefixes from one ten-component fit |

Every production option cell uses 30 replications. Run all effective families in one suite with
`TEST_NAME=all`, or replace `all` with a family listed above:

```sh
make run_test PROFILE=macbook TEST_SUITE=1D TEST_NAME=all
make run_test PROFILE=macbook TEST_SUITE=2D TEST_NAME=vary_n
make run_test PROFILE=macbook TEST_SUITE=GCV TEST_NAME=sensitivity_review
make run_test PROFILE=macbook TEST_SUITE=2D-predictive-order TEST_NAME=all
```

`GCV/sensitivity_review` is the group containing only `sensitivity` and
`sensitivity_high_NSRX`; it is not an additional experiment family.
