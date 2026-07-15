# = ========================================================================== =
# - Script: function_generators_1D.R
# - Desc: Defines orthogonal basis and mean functions on the unit interval [0,1].
#         Includes Laplacian eigenfunctions with Neumann boundary conditions
#         and simple smooth mean generators for testing functional data.
# = ========================================================================== =


## Function: laplacian_eigenfunction_1D
# - Args:
#   * locs: numeric vector of spatial locations in [0,1]
#   * i: integer index of the eigenfunction (or index in param_grid)
#   * x_t: optional shift of the eigenfunction (default 0)
#   * param_grid: optional vector specifying the sequence of n-values
# - Desc:
#   Computes the i-th eigenfunction of the Laplacian with Neumann boundary
#   conditions on [0,1], given by sqrt(2) * cos(n * pi * (x - x_t)).
#   These functions are orthogonal under the L² inner product.
laplacian_eigenfunction_1D <- function(locs, i, x_t = 0, param_grid = NULL) {
  ## Select the frequency index
  if (is.null(param_grid)) {
    n <- i
  } else {
    n <- param_grid[i]
  }
  ## Compute the eigenfunction
  return(sqrt(2) * cos(n * pi * (locs - x_t)))
}


## Function: log_mean_generator_1D
# - Args:
#   * locs: numeric vector of spatial locations in [0,1]
# - Desc:
#   Generates a smooth mean function based on the logarithm.
#   The result is scaled to lie between -1 and 1.
log_mean_generator_1D <- function(locs) {
  ## Compute the scaled logarithmic mean
  return((2 * log(locs + 1) / log(3)) - 1)
}