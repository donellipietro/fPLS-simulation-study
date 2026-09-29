// compile with C++20 and the configured Eigen include path, then run the resulting executable
#include <Eigen/Dense>
#include <cassert>
#include <iostream>
#include <limits>

#include "../cpp/include/fpcr_score_map.h"

// check the coefficient map against explicit residual projections with nonorthogonal loadings
int main() {
    Eigen::MatrixXd X(6, 4);
    X << 1, 2, -1, 0, -2, 1, 0, 3, 3, -1, 2, 1, -1, -2, 1, 0, 2, -1, 0, -3, -3, 1, -2, -1;
    Eigen::MatrixXd basis(4, 3);
    basis << 1, 0, 0, 0.2, 1, 0, 0, 0.3, 1, 0.1, 0, 0.4;
    Eigen::MatrixXd F(3, 3);
    F << 1, 0.8, 0.5, 0.2, 1, 0.7, 0.1, 0.2, 1;
    Eigen::MatrixXd original_scores = Eigen::MatrixXd::Zero(6, 3);
    original_scores(0, 0) = 0.8;
    original_scores(1, 1) = 1.2;
    original_scores(2, 2) = 0.4;
    const Eigen::MatrixXd fields = basis * F;
    const auto [directions, scores] = fpcr_score_map(X, basis, F, original_scores);

    Eigen::MatrixXd residual = X;
    Eigen::VectorXd scales(F.cols());
    for (Eigen::Index h = 0; h < F.cols(); ++h) {
        Eigen::VectorXd projection = residual * fields.col(h);
        scales[h] = original_scores.col(h).norm() / projection.norm();
        projection *= scales[h];
        // the independent residual update is the oracle for each finalized score
        assert((projection - scores.col(h)).norm() < 1e-12);
        // the final projection retains the native component's fitted score norm
        assert(std::abs(scores.col(h).norm() - original_scores.col(h).norm()) < 1e-12);
        residual -= projection * fields.col(h).transpose();
    }
    // directions operate on original predictors, without requiring residual inputs
    assert((X * basis * directions - scores).norm() < 1e-12);

    Eigen::MatrixXd Y(6, 2);
    Y << 1, 2, -2, 3, 4, -1, -1, -2, 2, -3, -4, 1;
    Eigen::MatrixXd X_new(2, 4);
    X_new << 0.2, -1, 3, 0.7, -2, 1.1, 0.4, 2;
    Eigen::MatrixXd new_residual = X_new;
    Eigen::MatrixXd new_scores(X_new.rows(), F.cols());
    for (Eigen::Index h = 0; h < F.cols(); ++h) {
        new_scores.col(h) = scales[h] * new_residual * fields.col(h);
        new_residual -= new_scores.col(h) * fields.col(h).transpose();
        const Eigen::MatrixXd prefix = scores.leftCols(h + 1);
        const Eigen::MatrixXd coefficients = prefix.colPivHouseholderQr().solve(Y);
        const Eigen::MatrixXd beta = directions.leftCols(h + 1) * coefficients;
        // each coefficient prefix reproduces its score regression on the training sample
        assert((X * basis * beta - prefix * coefficients).norm() < 1e-11);
        // training scales also give the same linear predictor on unseen observations
        assert((X_new * basis * beta - new_scores.leftCols(h + 1) * coefficients).norm() < 1e-11);
        // the fixture exposes the former loading-times-regression error
        assert((X * fields.leftCols(h + 1) * coefficients - prefix * coefficients).norm() > 0.1);
    }

    Eigen::MatrixXd flipped_F = F;
    flipped_F.col(1) *= -1;
    const auto [flipped_directions, flipped_scores] = fpcr_score_map(X, basis, flipped_F, original_scores);
    const Eigen::MatrixXd beta = directions * scores.colPivHouseholderQr().solve(Y);
    const Eigen::MatrixXd flipped_beta = flipped_directions * flipped_scores.colPivHouseholderQr().solve(Y);
    // changing a latent component's orientation cancels in the final regression coefficient
    assert((beta - flipped_beta).norm() < 1e-11);

    for (double value : {0.0, std::numeric_limits<double>::quiet_NaN()}) {
        Eigen::MatrixXd invalid_X = Eigen::MatrixXd::Constant(X.rows(), X.cols(), value);
        bool rejected = false;
        try {
            fpcr_score_map(invalid_X, basis, F, original_scores);
        } catch (const std::runtime_error&) { rejected = true; }
        // zero and nonfinite projections cannot define a fitted projection scale
        assert(rejected);
    }
    std::cout << "fPCR score map, prediction prefixes and latent-sign invariance verified\n";
}
