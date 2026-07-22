#ifndef FPLS_SIMULATION_FPCR_DRIVER_H
#define FPLS_SIMULATION_FPCR_DRIVER_H

template <typename Domain, typename Space, typename Penalty>
int run_fpcr(
  const json& params, Domain& domain, Space& space, Penalty&& penalty,
  const char* discretization) {
    const auto wall_start = std::chrono::steady_clock::now();

    const int n_comp = params.at("n_comp").get<int>();
    const int max_iter = params.at("max_iter").get<int>();
    const double tolerance = params.at("tolerance").get<double>();
    const std::string calibration = params.at("calibration").get<std::string>();
    const std::vector<double> lambda_grid = params.at("lambda_grid").get<std::vector<double>>();
    const double fixed_lambda = params.at("fixed_loading_lambda").get<double>();
    const std::filesystem::path output_dir(params.at("output_dir").get<std::string>());

    if (params.at("center").get<bool>()) {
        throw std::runtime_error("centering is not implemented for this simulation baseline");
    }
    if (n_comp < 1 || max_iter < 1 || tolerance <= 0) {
        throw std::runtime_error("invalid fPCR configuration");
    }

    const matrix_t X = read_matrix(params.at("X_file").get<std::string>());
    const matrix_t Y = read_matrix(params.at("Y_file").get<std::string>());
    const matrix_t locations = read_matrix(params.at("locations_file").get<std::string>());
    const matrix_t evaluation = read_matrix(params.at("evaluation_file").get<std::string>());
    if (X.rows() != Y.rows() || X.cols() != locations.rows()) {
        throw std::runtime_error("X, Y, and location dimensions do not agree");
    }

    GeoFrame data(domain);
    auto& layer = data.template insert_scalar_layer<POINT>("observations", locations);
    layer.load_blk("X", X.transpose());
    fPCA model("X", data, std::forward<Penalty>(penalty));
    const auto setup_end = std::chrono::steady_clock::now();

    if (calibration == "gcv") {
        if (lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");
        model.fit(
          n_comp, lambda_grid, ComputeXactSVD | OptimizeGCV,
          fpca_power_solver(max_iter, tolerance));
    } else if (calibration == "fixed") {
        model.fit(
          n_comp, std::vector<double>{fixed_lambda}, ComputeXactSVD,
          fpca_power_solver(max_iter, tolerance));
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }
    const auto fit_end = std::chrono::steady_clock::now();

    const matrix_t basis_at_locations = internals::point_basis_eval(space, locations);
    const matrix_t basis_at_evaluation = internals::point_basis_eval(space, evaluation);
    const matrix_t F_locations = basis_at_locations * model.F();
    const matrix_t full_regression = model.S().colPivHouseholderQr().solve(Y);
    matrix_t fpca_lambdas = model.lambda();
    if (fpca_lambdas.rows() == 1 && fpca_lambdas.cols() == n_comp) {
        fpca_lambdas.transposeInPlace();
    }
    const std::vector<double> selected_lambda(
      fpca_lambdas.data(), fpca_lambdas.data() + fpca_lambdas.size());

    const matrix_t Y_space_directions = full_regression.transpose();
    const matrix_t nan_scores = matrix_t::Constant(
      X.rows(), n_comp, std::numeric_limits<double>::quiet_NaN());
    const matrix_t nan_lambdas = matrix_t::Constant(
      n_comp, 1, std::numeric_limits<double>::quiet_NaN());
    matrix_t component_diagnostics(n_comp, 6);
    std::vector<matrix_t> objective_histories(n_comp);
    std::vector<matrix_t> Y_hat(n_comp);
    std::vector<matrix_t> X_hat_locations(n_comp);
    std::vector<matrix_t> beta_coefficients(n_comp);
    std::vector<matrix_t> beta_locations(n_comp);
    std::vector<matrix_t> beta_evaluation(n_comp);
    json component_files = json::array();
    for (int h = 0; h < n_comp; ++h) {
        const auto& history = model.objective_history()[h];
        objective_histories[h] = Eigen::Map<const matrix_t>(history.data(), history.size(), 1);
        component_diagnostics(h, 0) = h + 1;
        component_diagnostics(h, 1) = model.iterations()[h];
        component_diagnostics(h, 2) = model.monotone()[h] ? 1.0 : 0.0;
        component_diagnostics(h, 3) = history.empty() ?
          std::numeric_limits<double>::quiet_NaN() : history.back();
        component_diagnostics(h, 4) = model.iterations()[h] >= max_iter ? 1.0 : 0.0;
        component_diagnostics(h, 5) =
          !history.empty() && std::isfinite(history.back()) ? 1.0 : 0.0;

        const int component = h + 1;
        const matrix_t scores = model.S().leftCols(component);
        const matrix_t coefficients = scores.colPivHouseholderQr().solve(Y);
        beta_coefficients[h] = model.F().leftCols(component) * coefficients;
        Y_hat[h] = scores * coefficients;
        X_hat_locations[h] = scores * F_locations.leftCols(component).transpose();
        beta_locations[h] = basis_at_locations * beta_coefficients[h];
        beta_evaluation[h] = basis_at_evaluation * beta_coefficients[h];
        const std::string suffix = "_h" + std::to_string(component) + ".csv";
        component_files.push_back(json {
          {"component", component},
          {"y_hat", "y_hat" + suffix},
          {"x_hat_locations", "x_hat_locations" + suffix},
          {"beta_coefficients", "beta_coefficients" + suffix},
          {"beta_locations", "beta_locations" + suffix},
          {"beta_evaluation", "beta_evaluation" + suffix}
        });
    }
    const auto postprocess_end = std::chrono::steady_clock::now();

    std::filesystem::create_directories(output_dir);
    write_csv(output_file(output_dir, "x_space_directions_coefficients.csv"), model.F());
    write_csv(output_file(output_dir, "x_space_directions_locations.csv"), F_locations);
    write_csv(output_file(output_dir, "y_space_directions.csv"), Y_space_directions);
    write_csv(output_file(output_dir, "x_latent_scores.csv"), model.S());
    write_csv(
      output_file(output_dir, "y_latent_scores.csv"),
      nan_scores);
    write_csv(output_file(output_dir, "x_loadings_coefficients.csv"), model.F());
    write_csv(output_file(output_dir, "x_loadings_locations.csv"), F_locations);
    write_csv(output_file(output_dir, "y_loadings.csv"), Y_space_directions);
    write_csv(
      output_file(output_dir, "direction_lambdas.csv"),
      nan_lambdas);
    write_csv(
      output_file(output_dir, "loading_lambdas.csv"),
      nan_lambdas);
    write_csv(output_file(output_dir, "fpca_lambdas.csv"), fpca_lambdas);
    write_csv(output_file(output_dir, "x_mean_locations.csv"), matrix_t::Zero(1, X.cols()));
    write_csv(output_file(output_dir, "y_mean.csv"), matrix_t::Zero(1, Y.cols()));

    for (int h = 0; h < n_comp; ++h) {
        write_csv(
          output_file(output_dir, "objective_history_h" + std::to_string(h + 1) + ".csv"),
          objective_histories[h]);
    }
    write_csv(
      output_file(output_dir, "component_diagnostics.csv"), component_diagnostics,
      std::vector<std::string>{
        "component", "iterations", "monotone", "objective", "hit_max_iter", "finite_solution"
      });

    for (int h = 1; h <= n_comp; ++h) {
      const std::string suffix = "_h" + std::to_string(h) + ".csv";
        write_csv(output_file(output_dir, "y_hat" + suffix), Y_hat[h - 1]);
        write_csv(output_file(output_dir, "x_hat_locations" + suffix), X_hat_locations[h - 1]);
        write_csv(output_file(output_dir, "beta_coefficients" + suffix), beta_coefficients[h - 1]);
        write_csv(output_file(output_dir, "beta_locations" + suffix), beta_locations[h - 1]);
        write_csv(output_file(output_dir, "beta_evaluation" + suffix), beta_evaluation[h - 1]);
    }
    const auto serialization_end = std::chrono::steady_clock::now();

    const double setup_seconds = std::chrono::duration<double>(setup_end - wall_start).count();
    const double solver_seconds = std::chrono::duration<double>(fit_end - setup_end).count();
    const double postprocess_seconds = std::chrono::duration<double>(postprocess_end - fit_end).count();
    const double fit_seconds = setup_seconds + solver_seconds + postprocess_seconds;
    const double serialization_seconds = std::chrono::duration<double>(serialization_end - postprocess_end).count();
    const double wall_seconds = std::chrono::duration<double>(serialization_end - wall_start).count();

    std::ofstream telemetry(output_file(output_dir, "telemetry.json"));
    telemetry << json {
      {"schema_version", 4},
      {"model", "fPCR"},
      {"mode", "native_fdaPDE_cpp"},
      {"discretization", discretization},
      {"center", false},
      {"calibration", calibration},
      {"fit_includes_gcv", calibration == "gcv"},
      {"n_units", X.rows()},
      {"n_locations", X.cols()},
      {"n_responses", Y.cols()},
      {"n_components", n_comp},
      {"n_basis", space.n_dofs()},
      {"n_evaluation_points", evaluation.rows()},
      {"max_iter", max_iter},
      {"tolerance", tolerance},
      {"lambda_grid", lambda_grid},
      {"fixed_loading_lambda", fixed_lambda},
      {"setup_seconds", setup_seconds},
      {"solver_seconds", solver_seconds},
      {"postprocess_seconds", postprocess_seconds},
      {"fit_seconds", fit_seconds},
      {"serialization_seconds", serialization_seconds},
      {"output_seconds", serialization_seconds},
      {"wall_seconds", wall_seconds},
      {"iteration_counts_available", true},
      {"iteration_counts", model.iterations()},
      {"monotone", model.monotone()},
      {"selected_lambda", selected_lambda},
      {"component_files", component_files},
      {"provenance", params.at("provenance")}
    }.dump(2) << '\n';

    return 0;
}

#endif
