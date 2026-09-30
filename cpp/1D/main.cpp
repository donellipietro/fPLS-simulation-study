#include <fdaPDE/models.h>

#include "../include/fpls_output_1D.h"

/** @brief fit supervised rank-one fPLS components and export each component prefix */
int run_fpls(const simulation_parameters& params) {
    // discretize the unit interval with cubic B-splines
    Triangulation<1, 1> domain = Triangulation<1, 1>::UnitInterval(params.n_mesh_nodes);
    BsSpace space(domain, 3);

    // define trial and test functions for the variational roughness penalty
    TrialFunction f(space);
    TestFunction v(space);

    // define the second-derivative bilinear form for the integrated squared-curvature penalty
    const auto penalty = integral(domain)(dxx(f) * dxx(v));

    // define the homogeneous smoothing load with zero forcing
    ZeroField<1> forcing;
    const auto load = integral(domain)(forcing * v);

    // begin native timing before data loading; domain and variational-form setup precede this checkpoint
    const auto wall_start = std::chrono::steady_clock::now();

    // read centered predictors (subjects by locations), responses and observation/evaluation grids
    const matrix_t X = read_matrix(params.X_file);
    const matrix_t Y = read_matrix(params.Y_file);
    const matrix_t locations = read_matrix(params.locations_file);
    const matrix_t evaluation = read_matrix(params.evaluation_file);

    // check agreement between statistical units, responses and observation locations
    if (X.rows() != Y.rows() || X.cols() != locations.rows()) {
        throw std::runtime_error("X, Y, and location dimensions do not agree");
    }

    // locate point observations in the domain and transpose X for the functional data block
    // the functional block uses rows for observation locations and columns for subjects
    GeoFrame data(domain);
    auto& layer = data.insert_scalar_layer<POINT>("observations", locations);
    layer.load_blk("X", X.transpose());

    // model definition: separate smoothers for supervised directions and predictor reconstruction loadings
    fPLS model("X", Y, data, bs_ls_elliptic(penalty, load), bs_ls_elliptic(penalty, load));

    // finish model setup timing before the calibration and fitting stage
    const auto setup_end = std::chrono::steady_clock::now();

    // calibrate each direction/loading by GCV or use the supplied shared or component-wise lambda schedules
    if (params.calibration == "gcv") {
        if (params.lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");

        // estimate supervised directions and loadings with component-wise GCV
        model.fit(
          params.n_comp,        // number of retained components
          params.lambda_grid,   // candidate lambdas for direction smoothing
          params.lambda_grid,   // candidate lambdas for loading smoothing
          OptimizeGCV,          // select both smoothing parameters by GCV per component
          params.max_iter,      // maximum alternating direction updates per component
          params.tolerance,     // objective tolerance for stopping and increase diagnostics
          params.gcv_probes,    // number of Hutchinson probes for effective degrees of freedom
          params.gcv_seed       // seed for stochastic effective degrees of freedom
        );
    } else if (params.calibration == "fixed") {
        // estimate all components using the supplied fixed smoothing parameters
        model.fit(
          params.n_comp,                    // number of retained components
          params.fixed_direction_lambdas,   // direction lambdas: shared scalar or one per component
          params.fixed_loading_lambdas,     // loading lambdas: shared scalar or one per component
          0,                                // disable GCV and use the supplied lambda schedules
          params.max_iter,                  // maximum alternating direction updates per component
          params.tolerance                  // objective tolerance for stopping and increase diagnostics
        );
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }

    // finish solver timing once all components and their calibration diagnostics have been fitted
    const auto fit_end = std::chrono::steady_clock::now();

    // export the model's predictions, reconstructions, coefficients and retained calibration diagnostics
    return write_fpls_output(
      params, space, model, X, Y,       // output settings, function space, fitted model and training data
      locations, evaluation,            // grids for observed and independent functional-field evaluations
      wall_start, setup_end, fit_end,   // timing checkpoints for data loading, model setup and fitting
      "spline"                          // discretization label recorded in telemetry
    );
}

int main(int argc, char* argv[]) {
    try {
        // read and validate the command-line parameter file
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " <params.json>\n";
            return 1;
        }
        const auto params = read_parameters(read_parameter_file(argv[1]), true);

        // run the native model used in the one-dimensional paper experiments
        if (params.model_name == "R1_fPLS") return run_fpls(params);
        throw std::runtime_error("model must be R1_fPLS");
    } catch (const std::exception& error) {
        std::cerr << "simulation failed: " << error.what() << '\n';
        return 2;
    }
}
