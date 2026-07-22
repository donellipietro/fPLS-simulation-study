#ifndef FPLS_SIMULATION_MAIN_IMPL_H
#define FPLS_SIMULATION_MAIN_IMPL_H

#include <fdaPDE/models.h>

#include <nlohmann/json.hpp>

#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace fdapde;
using nlohmann::json;

using matrix_t = Eigen::Matrix<double, Eigen::Dynamic, Eigen::Dynamic>;

matrix_t read_matrix(const std::string& file) {
    const std::filesystem::path path(file);
    const std::string readable_path = path.is_absolute() ?
      std::filesystem::relative(path, std::filesystem::current_path()).string() : file;
    return read_csv<double>(readable_path, true, false).as_matrix();
}

std::string output_file(const std::filesystem::path& output_dir, const std::string& name) {
    return (output_dir / name).string();
}

#include "../include/fpcr_driver.h"

template <typename Domain, typename Space, typename DirectionPenalty, typename LoadingPenalty>
int run_fpls(
  const json& params, Domain& domain, Space& space, DirectionPenalty&& direction_penalty,
  LoadingPenalty&& loading_penalty, const char* discretization) {
    const auto wall_start = std::chrono::steady_clock::now();

    const int n_comp = params.at("n_comp").get<int>();
    const int max_iter = params.at("max_iter").get<int>();
    const double tolerance = params.at("tolerance").get<double>();
    const int gcv_probes = params.at("gcv_probes").get<int>();
    const int gcv_seed = params.at("gcv_seed").get<int>();
    const std::string calibration = params.at("calibration").get<std::string>();
    const std::vector<double> lambda_grid = params.at("lambda_grid").get<std::vector<double>>();
    const double fixed_direction_lambda = params.at("fixed_direction_lambda").get<double>();
    const double fixed_loading_lambda = params.at("fixed_loading_lambda").get<double>();
    const std::filesystem::path output_dir(params.at("output_dir").get<std::string>());

    if (params.at("center").get<bool>()) {
        throw std::runtime_error("centering is not implemented for this source-era baseline");
    }
    if (n_comp < 1 || max_iter < 1 || tolerance <= 0 || gcv_probes < 1) {
        throw std::runtime_error("invalid fPLS configuration");
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

    fPLS model(
      "X", Y, data, std::forward<DirectionPenalty>(direction_penalty),
      std::forward<LoadingPenalty>(loading_penalty));
    const auto setup_end = std::chrono::steady_clock::now();

    matrix_t direction_lambdas;
    matrix_t loading_lambdas;
    if (calibration == "gcv") {
        if (lambda_grid.empty()) throw std::runtime_error("empty GCV lambda grid");
        model.fit(
          n_comp, lambda_grid, lambda_grid, OptimizeGCV, max_iter, tolerance,
          gcv_probes, gcv_seed);
        direction_lambdas = model.direction_lambda();
        loading_lambdas = model.loading_lambda();
    } else if (calibration == "fixed") {
        Eigen::Matrix<double, 1, 1> direction_lambda;
        Eigen::Matrix<double, 1, 1> loading_lambda;
        direction_lambda << fixed_direction_lambda;
        loading_lambda << fixed_loading_lambda;
        model.fit(n_comp, direction_lambda, loading_lambda, max_iter, tolerance);
        direction_lambdas = matrix_t::Constant(n_comp, 1, fixed_direction_lambda);
        loading_lambdas = matrix_t::Constant(n_comp, 1, fixed_loading_lambda);
    } else {
        throw std::runtime_error("calibration must be gcv or fixed");
    }
    const auto fit_end = std::chrono::steady_clock::now();

    const matrix_t basis_at_locations = internals::point_basis_eval(space, locations);
    const matrix_t basis_at_evaluation = internals::point_basis_eval(space, evaluation);
    const matrix_t X_directions = model.X_space_directions();
    const matrix_t X_direction_locations = basis_at_locations * X_directions;
    const matrix_t X_loadings = model.X_loadings();
    const matrix_t X_loading_locations = basis_at_locations * X_loadings;

    matrix_t component_diagnostics(n_comp, 6);
    std::vector<matrix_t> objective_histories(n_comp);
    std::vector<matrix_t> Y_hat(n_comp);
    std::vector<matrix_t> X_hat_locations(n_comp);
    std::vector<matrix_t> beta_coefficients(n_comp);
    std::vector<matrix_t> beta_locations(n_comp);
    std::vector<matrix_t> beta_evaluation(n_comp);
    json component_files = json::array();
    for (int h = 0; h < n_comp; ++h) {
        const auto& history = model.direction_objective_history()[h];
        objective_histories[h] = Eigen::Map<const matrix_t>(history.data(), history.size(), 1);
        component_diagnostics(h, 0) = h + 1;
        component_diagnostics(h, 1) = model.direction_iterations()[h];
        component_diagnostics(h, 2) = model.direction_monotone()[h] ? 1.0 : 0.0;
        component_diagnostics(h, 3) = history.empty() ?
          std::numeric_limits<double>::quiet_NaN() : history.back();
        component_diagnostics(h, 4) = model.direction_iterations()[h] >= max_iter ? 1.0 : 0.0;
        component_diagnostics(h, 5) =
          !history.empty() && std::isfinite(history.back()) ? 1.0 : 0.0;

        const int component = h + 1;
        beta_coefficients[h] = model.Beta(component);
        Y_hat[h] = model.fitted(component);
        X_hat_locations[h] = model.reconstructed(component);
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
    write_csv(output_file(output_dir, "x_space_directions_coefficients.csv"), X_directions);
    write_csv(output_file(output_dir, "x_space_directions_locations.csv"), X_direction_locations);
    write_csv(output_file(output_dir, "y_space_directions.csv"), model.Y_space_directions());
    write_csv(output_file(output_dir, "x_latent_scores.csv"), model.X_latent_scores());
    write_csv(output_file(output_dir, "y_latent_scores.csv"), model.Y_latent_scores());
    write_csv(output_file(output_dir, "x_loadings_coefficients.csv"), X_loadings);
    write_csv(output_file(output_dir, "x_loadings_locations.csv"), X_loading_locations);
    write_csv(output_file(output_dir, "y_loadings.csv"), model.Y_loadings());
    write_csv(output_file(output_dir, "direction_lambdas.csv"), direction_lambdas);
    write_csv(output_file(output_dir, "loading_lambdas.csv"), loading_lambdas);
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
      {"model", "R1_fPLS"},
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
      {"gcv_probes", gcv_probes},
      {"gcv_seed", gcv_seed},
      {"lambda_grid", lambda_grid},
      {"fixed_direction_lambda", fixed_direction_lambda},
      {"fixed_loading_lambda", fixed_loading_lambda},
      {"setup_seconds", setup_seconds},
      {"solver_seconds", solver_seconds},
      {"postprocess_seconds", postprocess_seconds},
      {"fit_seconds", fit_seconds},
      {"serialization_seconds", serialization_seconds},
      {"output_seconds", serialization_seconds},
      {"wall_seconds", wall_seconds},
      {"iteration_counts_available", true},
      {"iteration_counts", model.direction_iterations()},
      {"monotone", model.direction_monotone()},
      {"component_files", component_files},
      {"provenance", params.at("provenance")}
    }.dump(2) << '\n';

    return 0;
}

int fpls_simulation_main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <params.json>\n";
        return 1;
    }

    std::ifstream input(argv[1]);
    if (!input) throw std::runtime_error("cannot open parameter file");
    const json params = json::parse(input);

#ifdef FPLS_SIMULATION_1D
    const int n_mesh_nodes = params.at("n_mesh_nodes").get<int>();
    Triangulation<1, 1> domain = Triangulation<1, 1>::UnitInterval(n_mesh_nodes);
    BsSpace space(domain, 3);
    TrialFunction f(space);
    TestFunction v(space);
    const auto penalty = integral(domain)(dxx(f) * dxx(v));
    ZeroField<1> forcing;
    const auto load = integral(domain)(forcing * v);
    return run_fpls(
      params, domain, space, bs_ls_elliptic(penalty, load),
      bs_ls_elliptic(penalty, load), "spline");
#elif defined(FPLS_SIMULATION_2D)
    const int n_mesh_nodes_per_axis = params.at("n_mesh_nodes_per_axis").get<int>();
    Triangulation<2, 2> domain = Triangulation<2, 2>::UnitSquare(n_mesh_nodes_per_axis);
    FeSpace space(domain, P1<1>);
    TrialFunction f(space);
    TestFunction v(space);
    const auto penalty = integral(domain)(dot(grad(f), grad(v)));
    ZeroField<2> forcing;
    const auto load = integral(domain)(forcing * v);
    if (params.value("model", std::string("R1_fPLS")) == "fPCR") {
        return run_fpcr(params, domain, space, fe_ls_elliptic(penalty, load), "fem");
    }
    return run_fpls(
      params, domain, space, fe_ls_elliptic(penalty, load),
      fe_ls_elliptic(penalty, load), "fem");
#else
#error "Select one fPLS simulation dimension"
#endif
}

#endif
