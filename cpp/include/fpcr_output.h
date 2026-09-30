#ifndef FPLS_SIMULATION_FPCR_OUTPUT_H
#define FPLS_SIMULATION_FPCR_OUTPUT_H

#include "simulation_utils.h"

/** @brief export smooth fPCR prefix predictions, regression fields, diagnostics and run metadata */
template <typename Space, typename Model>
int write_fpcr_output(
  const simulation_parameters& params, const Space& space, const Model& model, const matrix_t& X, const matrix_t& Y,
  const matrix_t& locations, const matrix_t& evaluation, time_point_t wall_start, time_point_t setup_end,
  time_point_t fit_end, const char* discretization) {
    // evaluate the model's coefficient fields on observation and independent evaluation grids
    const matrix_t basis_at_locations = internals::point_basis_eval(space, locations);
    const matrix_t basis_at_evaluation = internals::point_basis_eval(space, evaluation);
    const matrix_t F_locations = basis_at_locations * model.X_loadings();
    const matrix_t direction_locations = basis_at_locations * model.X_space_directions();
    // normalize the native lambda-vector orientation to one row per component for CSV output
    matrix_t fpca_lambdas = model.lambda();
    if (fpca_lambdas.rows() == 1 && fpca_lambdas.cols() == params.n_comp) { fpca_lambdas.transposeInPlace(); }
    const std::vector<double> selected_lambda(fpca_lambdas.data(), fpca_lambdas.data() + fpca_lambdas.size());

    const matrix_t Y_space_directions = model.score_coefficients().transpose();
    // fPCR has no separate response latent scores or fPLS direction/loading lambdas
    const matrix_t nan_scores = matrix_t::Constant(X.rows(), params.n_comp, std::numeric_limits<double>::quiet_NaN());
    const matrix_t nan_lambdas = matrix_t::Constant(params.n_comp, 1, std::numeric_limits<double>::quiet_NaN());
    // summarize fPCA iterations, objective monotonicity and stopping status for each component
    matrix_t component_diagnostics(params.n_comp, 6);
    std::vector<matrix_t> objective_histories(params.n_comp);
    std::vector<matrix_t> Y_hat(params.n_comp);
    std::vector<matrix_t> X_hat_locations(params.n_comp);
    std::vector<matrix_t> beta_coefficients(params.n_comp);
    std::vector<matrix_t> beta_locations(params.n_comp);
    std::vector<matrix_t> beta_evaluation(params.n_comp);
    matrix_t response_diagnostics(params.n_comp * Y.cols(), 4);
    json component_files = json::array();
    for (int h = 0; h < params.n_comp; ++h) {
        const auto& history = model.objective_history()[h];
        objective_histories[h] = Eigen::Map<const matrix_t>(history.data(), history.size(), 1);
        component_diagnostics(h, 0) = h + 1;
        component_diagnostics(h, 1) = model.iterations()[h];
        component_diagnostics(h, 2) = model.monotone()[h] ? 1.0 : 0.0;
        component_diagnostics(h, 3) = history.empty() ? std::numeric_limits<double>::quiet_NaN() : history.back();
        component_diagnostics(h, 4) = model.iterations()[h] >= params.max_iter ? 1.0 : 0.0;
        component_diagnostics(h, 5) = !history.empty() && std::isfinite(history.back()) ? 1.0 : 0.0;

        // use the model's independently refitted OLS and corrected original-X map for this prefix
        const int component = h + 1;
        beta_coefficients[h] = model.Beta(component);
        Y_hat[h] = model.fitted(component);
        X_hat_locations[h] = model.reconstructed(component);
        // evaluate the same regression coefficient function on observation and independent evaluation grids
        beta_locations[h] = basis_at_locations * beta_coefficients[h];
        beta_evaluation[h] = basis_at_evaluation * beta_coefficients[h];
        // summarize each response separately while retaining every response column in fitted matrices
        for (Eigen::Index response = 0; response < Y.cols(); ++response) {
            const double sse = (Y.col(response) - Y_hat[h].col(response)).squaredNorm();
            response_diagnostics.row(h * Y.cols() + response) << component, response + 1, sse, sse / Y.rows();
        }
        const std::string suffix = "_h" + std::to_string(component) + ".csv";
        component_files.push_back(
          json {
            {"component",         component                   },
            {"y_hat",             "y_hat" + suffix            },
            {"x_hat_locations",   "x_hat_locations" + suffix  },
            {"beta_coefficients", "beta_coefficients" + suffix},
            {"beta_locations",    "beta_locations" + suffix   },
            {"beta_evaluation",   "beta_evaluation" + suffix  }
        });
    }
    const auto postprocess_end = std::chrono::steady_clock::now();

    // serialize fitted functional coefficients, their point evaluations and the associated latent quantities
    std::filesystem::create_directories(params.output_dir);
    write_csv(output_file(params.output_dir, "x_space_directions_coefficients.csv"), model.X_space_directions());
    write_csv(output_file(params.output_dir, "x_space_directions_locations.csv"), direction_locations);
    write_csv(output_file(params.output_dir, "y_space_directions.csv"), Y_space_directions);
    write_csv(output_file(params.output_dir, "x_latent_scores.csv"), model.X_latent_scores());
    write_csv(output_file(params.output_dir, "y_latent_scores.csv"), nan_scores);
    write_csv(output_file(params.output_dir, "x_loadings_coefficients.csv"), model.X_loadings());
    write_csv(output_file(params.output_dir, "x_loadings_locations.csv"), F_locations);
    write_csv(output_file(params.output_dir, "y_loadings.csv"), Y_space_directions);
    write_csv(output_file(params.output_dir, "direction_lambdas.csv"), nan_lambdas);
    write_csv(output_file(params.output_dir, "loading_lambdas.csv"), nan_lambdas);
    write_csv(output_file(params.output_dir, "fpca_lambdas.csv"), fpca_lambdas);
    // centering was performed upstream, so these compatibility files contain zero fitted offsets
    write_csv(output_file(params.output_dir, "x_mean_locations.csv"), matrix_t::Zero(1, X.cols()));
    write_csv(output_file(params.output_dir, "y_mean.csv"), matrix_t::Zero(1, Y.cols()));

    // serialize the EDF and GCV evaluations retained during the actual calibration
    json gcv_curve_files = json::array();
    if (params.calibration == "gcv") {
        for (int h = 0; h < params.n_comp; ++h) {
            const std::string file = "fpca_gcv_h" + std::to_string(h + 1) + ".csv";
            write_csv(
              output_file(params.output_dir, file),
              gcv_curve_matrix(
                model.lambda_grid(), model.gcv_values()[h], model.gcv_edf()[h], model.selected_indices()[h]),
              std::vector<std::string> {"lambda", "edf", "gcv", "selected_by_fit"});
            gcv_curve_files.push_back(
              json {
                {"component", h + 1},
                {"loading",   file }
            });
        }
    }

    for (int h = 0; h < params.n_comp; ++h) {
        write_csv(
          output_file(params.output_dir, "objective_history_h" + std::to_string(h + 1) + ".csv"),
          objective_histories[h]);
    }
    write_csv(
      output_file(params.output_dir, "component_diagnostics.csv"), component_diagnostics,
      std::vector<std::string> {"component", "iterations", "monotone", "objective", "hit_max_iter", "finite_solution"});

    for (int h = 1; h <= params.n_comp; ++h) {
        const std::string suffix = "_h" + std::to_string(h) + ".csv";
        write_csv(output_file(params.output_dir, "y_hat" + suffix), Y_hat[h - 1]);
        write_csv(output_file(params.output_dir, "x_hat_locations" + suffix), X_hat_locations[h - 1]);
        write_csv(output_file(params.output_dir, "beta_coefficients" + suffix), beta_coefficients[h - 1]);
        write_csv(output_file(params.output_dir, "beta_locations" + suffix), beta_locations[h - 1]);
        write_csv(output_file(params.output_dir, "beta_evaluation" + suffix), beta_evaluation[h - 1]);
    }
    write_csv(
      output_file(params.output_dir, "response_diagnostics.csv"), response_diagnostics,
      std::vector<std::string> {"component", "response", "sse", "mse"});
    const auto serialization_end = std::chrono::steady_clock::now();

    // fit time includes setup, solver and numerical postprocessing; CSV serialization is timed separately
    const double setup_seconds = std::chrono::duration<double>(setup_end - wall_start).count();
    const double solver_seconds = std::chrono::duration<double>(fit_end - setup_end).count();
    const double postprocess_seconds = std::chrono::duration<double>(postprocess_end - fit_end).count();
    const double fit_seconds = setup_seconds + solver_seconds + postprocess_seconds;
    const double serialization_seconds = std::chrono::duration<double>(serialization_end - postprocess_end).count();
    const double wall_seconds = std::chrono::duration<double>(serialization_end - wall_start).count();

    // retain calibration settings, input provenance and the component-file manifest for reproducibility
    std::ofstream telemetry(output_file(params.output_dir, "telemetry.json"));
    telemetry << json {
          {"schema_version", 5},
          {"model", "fPCR"},
          {"fpcr_score_map", "sequential_projection_v1"},
          {"fpcr_implementation", "fdaPDE_cpp"},
          {"y_latent_scores_available", false},
          {"diagnostic_refits", 0},
          {"mode", "native_fdaPDE_cpp"},
          {"discretization", discretization},
          {"center", false},
          {"calibration", params.calibration},
          {"fit_includes_gcv", params.calibration == "gcv"},
          {"n_units", X.rows()},
          {"n_locations", X.cols()},
          {"n_responses", Y.cols()},
          {"n_components", params.n_comp},
          {"n_basis", space.n_dofs()},
          {"n_evaluation_points", evaluation.rows()},
          {"max_iter", params.max_iter},
          {"tolerance", params.tolerance},
          {"lambda_grid", params.lambda_grid},
          {"gcv_edf_applied", params.calibration == "gcv"},
          {"gcv_probes", params.gcv_probes},
          {"gcv_seed", params.gcv_seed},
          {"gcv_curve_files", gcv_curve_files},
          {"fixed_loading_lambda", params.fixed_loading_lambda},
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
          {"provenance", params.provenance}
        }.dump(2) << '\n';

    return 0;
}

#endif
