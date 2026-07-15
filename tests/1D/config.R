# = ========================================================================== =
# - Test: fPLS paper simulation on a 1D support
# - Desc: Paper-facing basis, sample-size, and observed-location experiments.
# = ========================================================================== =

## Test suite full name and directory name ----
TEST_SUITE <- "fPLS paper simulation 1D"
test_suite <- "1D"

## Tests included in the grouped all target ----
test_groups <- list(all = c("vary_k", "vary_n", "vary_m"))

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
