# = ========================================================================== =
# - Test: fPLS GCV and numerical-stability diagnostics
# - Desc: One-dimensional tuning, asymptotic, and near-zero-lambda tests.
# = ========================================================================== =

## Test suite full name and directory name ----
TEST_SUITE <- "fPLS GCV diagnostics"
test_suite <- "GCV"

## Tests included in the grouped all target ----
sensitivity_families <- c(
  "sensitivity", "sensitivity_componentwise", "sensitivity_competitors",
  "sensitivity_high_NSRX", "sensitivity_high_NSRX_competitors"
)
test_groups <- list(
  sensitivity_review = sensitivity_families,
  all = c(
    sensitivity_families, "lambda_to_zero",
    "small_lambda_m_gt_k", "small_lambda_m_lt_k"
  )
)

## Fit and evaluation controls ----
FORCE_FIT <- FALSE
FORCE_EVALUATE <- FALSE
RUN <- list(tests = TRUE, analysis = TRUE, quantitative_analysis = TRUE)

## Execution modifiers ----
SMOKE_TEST <- tolower(Sys.getenv("SMOKE_TEST", "false")) %in% c("1", "true", "yes", "y")
IGNORE_CPP_OUTPUT <- TRUE

## Defaults ----
name_main_test_default <- "all"
order <- 1L
