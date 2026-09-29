#ifndef FPLS_SIMULATION_FPCR_SCORE_MAP_H
#define FPLS_SIMULATION_FPCR_SCORE_MAP_H

#include <Eigen/Core>
#include <cmath>
#include <stdexcept>
#include <utility>

/// @brief finalizes sequential fPCA score projections and their map from the original predictors
inline std::pair<Eigen::MatrixXd, Eigen::MatrixXd> fpcr_score_map(
  const Eigen::MatrixXd& X, const Eigen::MatrixXd& basis, const Eigen::MatrixXd& loadings,
  const Eigen::MatrixXd& fitted_scores) {
    const Eigen::MatrixXd fields = basis * loadings;
    Eigen::MatrixXd directions = loadings;
    Eigen::MatrixXd scores = X * fields;
    for (Eigen::Index h = 0; h < loadings.cols(); ++h) {
        // undo previous deflations in coefficient space as well as in the score projections
        const Eigen::VectorXd coupling = fields.leftCols(h).transpose() * fields.col(h);
        directions.col(h) -= directions.leftCols(h) * coupling;
        scores.col(h) -= scores.leftCols(h) * coupling;
        const double projected_norm = scores.col(h).norm();
        const double fitted_norm = fitted_scores.col(h).norm();
        if (!std::isfinite(projected_norm) || projected_norm == 0 || !std::isfinite(fitted_norm) || fitted_norm == 0) {
            throw std::runtime_error("fPCR cannot project a zero or non-finite component");
        }
        // retain the fitted score norm while using the final loading, not the previous solver iterate
        const double scale = fitted_norm / projected_norm;
        directions.col(h) *= scale;
        scores.col(h) *= scale;
    }
    return {directions, scores};
}

#endif
