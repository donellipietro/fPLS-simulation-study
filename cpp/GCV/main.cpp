#include <fdaPDE/models.h>

#include "../1D/output.h"
#include "../include/fpcr_output.h"

/** @brief fit supervised rank-one fPLS components and export each component prefix */
int run_fpls(
  const simulation_parameters& params   // input paths, mesh size, calibration and output settings
) {
    // discretize the unit interval with cubic B-splines
    Triangulation<1, 1> domain = Triangulation<1, 1>::UnitInterval(params.n_mesh_nodes);
    BsSpace space(domain, 3);
    TrialFunction f(space);
    TestFunction v(space);

    // penalize integrated squared curvature through the second-derivative bilinear form
    // zero forcing gives a homogeneous smoothing penalty
    const auto penalty = integral(domain)(dxx(f) * dxx(v));
    ZeroField<1> forcing;
    const auto load = integral(domain)(forcing * v);

    const auto wall_start = std::chrono::steady_clock::now();

    // read centered predictors (subjects by locations), responses and observation/evaluation grids
    const matrix_t X = read_matrix(params.X_file);
    const matrix_t Y = read_matrix(params.Y_file);
    const matrix_t locations = read_matrix(params.locations_file);
    const matrix_t evaluation = read_matrix(params.evaluation_file);
    if (X.rows() != Y.rows() || X.cols() != locations.rows()) {
        throw std::runtime_error("X, Y, and location dimensions do not agree");
    }

    // locate point observations in the domain; GeoFrame stores locations by subjects
    // transpose the CSV predictor matrix before loading the functional data block
    GeoFrame data(domain);
    auto& layer = data.insert_scalar_layer<POINT>("observations", locations);
    layer.load_blk("X", X.transpose());

    // use separate smoothers for supervised directions and predictor reconstruction loadings
    fPLS model("X", Y, data, bs_ls_elliptic(penalty, load), bs_ls_elliptic(penalty, load));
    const auto setup_end = std::chrono::steady_clock::now();

    matrix_t direction_lambdas;
    matrix_t loading_lambdas;

    // fit with GCV calibration or fixed smoothing parameters
    if (params.calibration == "gcv") {
        if (params.lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");
        model.fit(
          params.n_comp,        // number of retained components
          params.lambda_grid,   // candidate lambdas for direction smoothing
          params.lambda_grid,   // candidate lambdas for loading smoothing
          OptimizeGCV,          // select both smoothing parameters by GCV per component
          params.max_iter,      // maximum alternating direction updates per component
          params.tolerance,     // objective tolerance for stopping and increase diagnostics
          params.gcv_probes,    // Hutchinson probes for effective degrees of freedom
          params.gcv_seed       // seed for stochastic effective degrees of freedom
        );
        // retain the component-specific choices made during the sequential fit
        direction_lambdas = model.direction_lambda();
        loading_lambdas = model.loading_lambda();
    } else if (params.calibration == "fixed") {
        model.fit(
          params.n_comp,                    // number of retained components
          params.fixed_direction_lambdas,   // direction lambdas: shared scalar or one per component
          params.fixed_loading_lambdas,     // loading lambdas: shared scalar or one per component
          0,                                // disable GCV and use the supplied lambda schedules
          params.max_iter,                  // maximum alternating direction updates per component
          params.tolerance                  // objective tolerance for stopping and increase diagnostics
        );
        direction_lambdas = model.direction_lambda();
        loading_lambdas = model.loading_lambda();
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }
    const auto fit_end = std::chrono::steady_clock::now();

    // export fitted quantities, diagnostics and timings
    return write_fpls_output(
      params, space, model, X, Y, locations, evaluation, direction_lambdas, loading_lambdas, wall_start, setup_end,
      fit_end, "spline");
}

/** @brief fit smooth fPCA components and refit OLS for each score prefix */
int run_fpcr(
  const simulation_parameters& params   // input paths, mesh size, calibration and output settings
) {
    // discretize the unit interval with cubic B-splines
    Triangulation<1, 1> domain = Triangulation<1, 1>::UnitInterval(params.n_mesh_nodes);
    BsSpace space(domain, 3);
    TrialFunction f(space);
    TestFunction v(space);

    // penalize integrated squared curvature through the second-derivative bilinear form
    // zero forcing gives a homogeneous smoothing penalty
    const auto penalty = integral(domain)(dxx(f) * dxx(v));
    ZeroField<1> forcing;
    const auto load = integral(domain)(forcing * v);

    const auto wall_start = std::chrono::steady_clock::now();

    // read centered predictors (subjects by locations), responses and observation/evaluation grids
    const matrix_t X = read_matrix(params.X_file);
    const matrix_t Y = read_matrix(params.Y_file);
    const matrix_t locations = read_matrix(params.locations_file);
    const matrix_t evaluation = read_matrix(params.evaluation_file);
    if (X.rows() != Y.rows() || X.cols() != locations.rows()) {
        throw std::runtime_error("X, Y, and location dimensions do not agree");
    }

    // locate point observations in the domain; GeoFrame stores locations by subjects
    // transpose the CSV predictor matrix before loading the functional data block
    GeoFrame data(domain);
    auto& layer = data.insert_scalar_layer<POINT>("observations", locations);
    layer.load_blk("X", X.transpose());

    // estimate predictor components and refit multivariate OLS for every sequential score prefix
    fPCR model("X", Y, data, bs_ls_elliptic(penalty, load));
    const auto setup_end = std::chrono::steady_clock::now();

    // fit with GCV calibration or fixed smoothing parameters
    if (params.calibration == "gcv") {
        if (params.lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");
        model.fit(
          params.n_comp,                  // number of retained principal components
          params.lambda_grid,             // candidate lambdas for component smoothing
          ComputeXactSVD | OptimizeGCV,   // exact SVD initialization and GCV selection per component
          params.max_iter,                // solver iteration limit for each principal component
          params.tolerance,               // objective tolerance for stopping
          params.gcv_probes,              // Hutchinson probes for effective degrees of freedom
          params.gcv_seed                 // seed for stochastic effective degrees of freedom
        );
    } else if (params.calibration == "fixed") {
        model.fit(
          params.n_comp,                                       // number of retained principal components
          std::vector<double> {params.fixed_loading_lambda},   // fixed smoothing lambda shared by all components
          ComputeXactSVD,                                      // exact SVD initialization with fixed smoothing
          params.max_iter,                                     // solver iteration limit for each component
          params.tolerance                                     // objective tolerance for stopping
        );
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }
    const auto fit_end = std::chrono::steady_clock::now();

    // export predictions, reconstructions and coefficient fields supplied by the public model
    return write_fpcr_output(
      params, space, model, X, Y, locations, evaluation, wall_start, setup_end, fit_end, "spline");
}

int main(int argc, char* argv[]) {
    try {
        // read and validate the command-line parameter file
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " <params.json>\n";
            return 1;
        }
        const auto params = read_parameters(read_parameter_file(argv[1]), true);

        // dispatch the requested statistical model
        return params.model_name == "fPCR" ? run_fpcr(params) : run_fpls(params);
    } catch (const std::exception& error) {
        std::cerr << "fPLS simulation failed: " << error.what() << '\n';
        return 2;
    }
}
