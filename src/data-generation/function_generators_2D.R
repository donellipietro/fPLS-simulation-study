# = ========================================================================== =
# - Script: function_generators_2D.R
# - Desc: 2D function generators for tests, including synthetic loading fields,
#         Laplacian eigenfunctions (translated), anisotropic diffusion operators,
#         eigenfunctions of generic linear operators, and mean field generators.
# = ========================================================================== =


# - Function: translated_laplacian_eigenfunction
# - Args:
#   * locs: matrix/data.frame with columns x (locs[,1]) and y (locs[,2])
#   * i: integer index of the eigenfunction (or row in ab_grid)
#   * x_t, y_t: optional translations along x and y
#   * ab_grid: optional integer matrix with two columns (n, m) per row
# - Desc:
#   Computes Laplacian eigenfunctions with Neumann boundary conditions
#   on the unit square: cos(n*pi*(x-x_t)) * cos(m*pi*(y-y_t)).
translated_laplacian_eigenfunction <- function(locs, i, x_t = 0, y_t = 0, ab_grid = NULL) {
  ## Select frequencies
  if (is.null(ab_grid)) {
    n <- pi * i
    m <- pi * i
  } else {
    n <- pi * ab_grid[i, 1]
    m <- pi * ab_grid[i, 2]
  }
  ## Evaluate eigenfunction
  return(cos(n * (locs[, 1] - x_t)) * cos(m * (locs[, 2] - y_t)))
}


# - Function: anis_diff_op_2D
# - Args:
#   * alpha: rotation angle (radians) for principal axes
#   * gamma: anisotropy ratio (> 0); gamma > 1 stretches one axis
# - Desc:
#   Builds an anisotropic diffusion operator K and returns a function that,
#   given a femR function f, computes div(K * grad(f)).
anis_diff_op_2D <- function(alpha, gamma) {
  ## Define the roation matrix
  R <- matrix(
    c(
      cos(alpha), -sin(alpha),
      sin(alpha), cos(alpha)
    ),
    nrow = 2, ncol = 2
  )
  ## Define the scaling matrix
  Sigma <- matrix(
    c(
      1 / sqrt(gamma), 0,
      0, sqrt(gamma)
    ),
    nrow = 2, ncol = 2
  )
  ## Define the diffusion tensor
  K <- R %*% Sigma %*% t(R)
  return(
    function(f) {
      return(femR::div(K * femR::grad(f)))
    }
  )
}


# - Function: eigenfunctions.Lop
# - Args:
#   * locs: matrix/data.frame of locations where eigenfunctions are evaluated
#   * fpc_indexes: integer vector of eigenvector indices to extract
#   * femr_mesh: femR mesh object (to define FE space)
#   * L: linear operator builder; accepts a femR Function and returns an operator
#   * f: forcing term function(points) used by Pde
# - Desc:
#   Computes eigenfunctions of a generic linear operator (via femR) under
#   homogeneous Dirichlet boundary conditions. Returns the selected
#   eigenfunctions evaluated at 'locs'.
eigenfunctions_elliptic_operator <- function(locs, indexes, femr_mesh, L, f) {
  ## Define the PDE
  Vh <- FunctionSpace(femr_mesh, fe_order = 1)
  u <- Function(Vh)
  pde <- femR::Pde(L(u), f)

  ## Compute Mass and Stiffness matrices
  A <- pde$stiff()
  M <- pde$mass()

  ## Enforce homogeneous Dirichlet boundary conditions
  for(b_node in which(femr_mesh$boundary() == 1)) {
    A[b_node, ] <- 0
    A[, b_node] <- 0
    A[b_node, b_node] <- 1
  }

  ## Compute eigenpairs of A u = lambda M u
  k <- max(indexes)
  res <- PRIMME::eigs_sym(A, NEig = k, which = "SA", B = M, tol = 1e-8)

  ## Evaluate at locs
  FF <- res$vectors
  Psi <- Vh$basis()$eval(as.matrix(locs))
  FF_locs <- Psi %*% FF

  return(FF_locs[, indexes])
}

# A, B are numeric symmetric matrices; B must be SPD
gen_eig_spd <- function(A, B) {
  L <- chol(B) # B = L^T L
  Linv <- backsolve(L, diag(nrow(B))) # L^{-1}
  C <- t(Linv) %*% A %*% Linv # symmetric
  es <- eigen(C, symmetric = TRUE) # stable & fast
  V <- Linv %*% es$vectors # generalized eigenvectors
  list(values = es$values, vectors = V)
}


# - Function: c_shape_domain_loadings
# - Args:
#   * locs: matrix/data.frame with columns x (locs[,1]) and y (locs[,2])
#   * i: component index (1, 2, or 3)
# - Desc:
#   Produces localized Gaussian-like blobs
c_shape_domain_loadings <- function(locs, i) {
  if (i == 1L) {
    f <- exp(-0.5 * ((locs[, 1] - 2.5)^2 + (locs[, 2] + 0.5)^2)) * (locs[, 1] > 0) * (locs[, 2] < 0)
  } else if (i == 2L) {
    f <- exp(-((locs[, 1] - 1.5)^2 + (locs[, 2])^2)) * (locs[, 1] > 0) * (locs[, 2] > 0)
  } else if (i == 3L) {
    f <- exp(-8 * ((locs[, 1] + 0.5)^2 + 1 / 2 * (locs[, 2])^2)) * (locs[, 1] < 0)
  }
  return(f)
}


# - Function: log_mean_generator
# - Args:
#   * locs: matrix/data.frame with columns x (locs[,1]) and y (locs[,2])
# - Desc:
#   Produces a smooth logarithmic mean scaled to lie in [-1, 1].
log_mean_generator <- function(locs) {
  ## Scale log-based mean to [-1, 1]
  return((2 * log((locs[, 1] + locs[, 2]) + 1) / log(3) - 1))
}


# - Function: sin_mean_generator
# - Args:
#   * locs: matrix/data.frame with columns x (locs[,1]) and y (locs[,2])
# - Desc:
#   Generates a localized sinusoidal mean pattern with Gaussian tapering
#   around the center of the unit square.
sin_mean_generator <- function(locs) {
  ## Compute localized sinusoidal mean
  return(sin(4 * pi * locs[, 1]) * sin(4 * pi * locs[, 2]) *
           exp(-8 * ((locs[, 1] - 0.5)^2 + (locs[, 2] - 0.5)^2)))
}
