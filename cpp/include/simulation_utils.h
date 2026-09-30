#ifndef FPLS_SIMULATION_UTILS_H
#define FPLS_SIMULATION_UTILS_H

#include <fdaPDE/models.h>

#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace fdapde;
using nlohmann::json;

using matrix_t = Eigen::Matrix<double, Eigen::Dynamic, Eigen::Dynamic>;

/** @brief read a numeric CSV matrix through the fdaPDE table reader */
inline matrix_t read_matrix(const std::string& file) {
    const std::filesystem::path path(file);
    const std::string readable_path =
      path.is_absolute() ? std::filesystem::relative(path, std::filesystem::current_path()).string() : file;
    return read_csv<double>(readable_path, true, false).as_matrix();
}

/** @brief resolve an output filename within the configured result directory */
inline std::string output_file(const std::filesystem::path& output_dir, const std::string& name) {
    return (output_dir / name).string();
}

/** @brief accept one shared lambda or a schedule containing one lambda per retained component */
inline std::vector<double> lambda_schedule(const json& value, int n_comp, const char* name) {
    if (value.is_number()) { return {value.get<double>()}; }
    if (!value.is_array()) { throw std::runtime_error(std::string(name) + " must be a scalar or an array"); }
    const std::vector<double> schedule = value.get<std::vector<double>>();
    if (schedule.size() != static_cast<std::size_t>(n_comp)) {
        throw std::runtime_error(std::string(name) + " must have one value per component");
    }
    return schedule;
}

/** @brief export candidate EDF and GCV evaluations with the selection recorded during calibration */
inline matrix_t gcv_curve_matrix(
  const matrix_t& lambda_grid, const std::vector<double>& values, const std::vector<double>& edfs, int selected) {
    if (
      lambda_grid.cols() != 1 || lambda_grid.rows() != values.size() || values.size() != edfs.size() || selected < 0 ||
      selected >= values.size()) {
        throw std::runtime_error("GCV diagnostics and lambda grid sizes do not agree");
    }
    matrix_t curve(lambda_grid.rows(), 4);
    for (Eigen::Index i = 0; i < lambda_grid.rows(); ++i) {
        curve(i, 0) = lambda_grid(i, 0);
        curve(i, 1) = edfs[i];
        curve(i, 2) = values[i];
        curve(i, 3) = i == selected ? 1.0 : 0.0;
    }
    return curve;
}

using time_point_t = std::chrono::steady_clock::time_point;

/** @brief parse the JSON parameter file or report an unreadable input */
inline json read_parameter_file(const std::string& file) {
    std::ifstream input(file);
    if (!input) throw std::runtime_error("cannot open parameter file");
    return json::parse(input);
}

/** @brief validated inputs and calibration settings for a simulation driver */
struct simulation_parameters {
    std::string model_name;
    int n_mesh_nodes;
    int n_comp;
    int max_iter;
    double tolerance;
    int gcv_probes = 0;
    int gcv_seed = 0;
    std::string calibration;
    std::vector<double> lambda_grid;
    bool save_gcv_curves = false;
    double fixed_direction_lambda = 0;
    double fixed_loading_lambda = 0;
    std::vector<double> fixed_direction_lambdas;
    std::vector<double> fixed_loading_lambdas;
    json fixed_direction_input;
    json fixed_loading_input;
    std::filesystem::path output_dir;
    std::string X_file;
    std::string Y_file;
    std::string locations_file;
    std::string evaluation_file;
    json provenance;
};

/** @brief read simulation inputs and validate solver, centering and smoothing-schedule settings */
inline simulation_parameters read_parameters(const json& values, bool spline) {
    simulation_parameters params;
    params.n_mesh_nodes = values.at(spline ? "n_mesh_nodes" : "n_mesh_nodes_per_axis").get<int>();
    params.model_name = values.value("model", std::string("R1_fPLS"));
    params.n_comp = values.at("n_comp").get<int>();
    params.max_iter = values.at("max_iter").get<int>();
    params.tolerance = values.at("tolerance").get<double>();
    params.calibration = values.at("calibration").get<std::string>();
    // fixed fPCR ignores EDF settings; both models use explicit controls when calibrating by GCV
    if (params.model_name != "fPCR" || params.calibration == "gcv") {
        params.gcv_probes = values.at("gcv_probes").get<int>();
        params.gcv_seed = values.at("gcv_seed").get<int>();
    }
    params.lambda_grid = values.at("lambda_grid").get<std::vector<double>>();
    // read smoothing settings relevant to the selected model and discretization
    if (params.model_name == "fPCR") {
        params.fixed_loading_lambda = values.at("fixed_loading_lambda").get<double>();
    } else if (spline) {
        params.save_gcv_curves = values.value("save_gcv_curves", false);
    } else {
        params.fixed_direction_lambda = values.at("fixed_direction_lambda").get<double>();
        params.fixed_loading_lambda = values.at("fixed_loading_lambda").get<double>();
    }
    params.output_dir = values.at("output_dir").get<std::string>();

    // simulation inputs are centered upstream; this driver fits without an additional centering step
    if (values.at("center").get<bool>()) {
        throw std::runtime_error(
          params.model_name == "fPCR" ? "centering is not implemented for this simulation baseline" :
                                        "centering is not implemented for this source-era baseline");
    }
    if (
      params.n_comp < 1 || params.max_iter < 1 || params.tolerance <= 0 ||
      ((params.model_name != "fPCR" || params.calibration == "gcv") && params.gcv_probes < 1)) {
        throw std::runtime_error(
          params.model_name == "fPCR" ? "invalid fPCR configuration" : "invalid fPLS configuration");
    }
    // spline fPLS accepts per-component schedules and preserves their original JSON form for telemetry
    if (spline && params.model_name != "fPCR") {
        if (params.save_gcv_curves && params.calibration != "gcv") {
            throw std::runtime_error("GCV curves can only be saved for GCV calibration");
        }
        params.fixed_direction_input = values.at("fixed_direction_lambda");
        params.fixed_loading_input = values.at("fixed_loading_lambda");
        params.fixed_direction_lambdas =
          lambda_schedule(params.fixed_direction_input, params.n_comp, "fixed_direction_lambda");
        params.fixed_loading_lambdas =
          lambda_schedule(params.fixed_loading_input, params.n_comp, "fixed_loading_lambda");
    }
    params.X_file = values.at("X_file").get<std::string>();
    params.Y_file = values.at("Y_file").get<std::string>();
    params.locations_file = values.at("locations_file").get<std::string>();
    params.evaluation_file = values.at("evaluation_file").get<std::string>();
    params.provenance = values.at("provenance");
    return params;
}

#endif
