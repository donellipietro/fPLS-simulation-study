"""Check the five public-model consumers with synthetic scalar and multivariate data.

Usage: python3 tests/check_cpp_driver_outputs.py [baseline-binaries]
The optional baseline contains brain, 1D, 2D, 2D-predictive-order and GCV.
Simulation fPCR GCV intentionally now uses explicit EDF probes/seeds and a real
residual degrees-of-freedom denominator; fixed fits retain the previous algorithm.
"""

import csv
import itertools
import json
import math
from pathlib import Path
import random
import subprocess
import sys
import tempfile


def write_matrix(path, rows):
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(range(len(rows[0])))
        writer.writerows(rows)


def read_matrix(path):
    with path.open(newline="") as stream:
        rows = csv.reader(stream)
        next(rows)
        return [[float(value) for value in row] for row in rows]


def inputs(directory, dimension, n_responses=None):
    rng = random.Random(41)
    if dimension == 1:
        locations = [[i / 16] for i in range(1, 16)]
    elif dimension == 2:
        locations = list(itertools.product((0.08, 0.36, 0.64, 0.92), repeat=2))
    else:
        locations = list(itertools.product((0, 0.5, 1), repeat=3))
        indices = {point: i for i, point in enumerate(locations)}
        elements = []
        for origin in itertools.product((0, 0.5), repeat=3):
            for axes in itertools.permutations(range(3)):
                point = list(origin)
                cell = [indices[tuple(point)]]
                for axis in axes:
                    point[axis] += 0.5
                    cell.append(indices[tuple(point)])
                elements.append(cell)
        write_matrix(directory / "elements.csv", elements)
        write_matrix(directory / "boundary.csv", [[int(any(v in (0, 1) for v in p))] for p in locations])
    scores = [(math.sin(i * 1.3), math.cos(i * 0.7), math.sin(i * 0.4)) for i in range(1, 13)]
    X = [[a * (1 + sum(p)) + b * (math.cos(3 * p[0]) + sum(v * v for v in p))
          + c * math.sin(5 * sum(p)) + 0.03 * rng.gauss(0, 1) + 0.2 for p in locations]
         for a, b, c in scores]
    if n_responses is None:
        n_responses = 1 if dimension == 3 else 2
    Y = [[a + 0.7 * b + 0.1 * c, 0.4 * b - c, -a + 0.3 * c][:n_responses] for a, b, c in scores]
    write_matrix(directory / "X.csv", X)
    write_matrix(directory / "Y.csv", Y)
    write_matrix(directory / "locations.csv", locations)
    write_matrix(directory / "evaluation.csv", locations)
    return dict(X_file=str(directory / "X.csv"), Y_file=str(directory / "Y.csv"),
                locations_file=str(directory / "locations.csv"), evaluation_file=str(directory / "evaluation.csv"),
                nodes_file=str(directory / "locations.csv"), elements_file=str(directory / "elements.csv"),
                boundary_file=str(directory / "boundary.csv"), n_mesh_nodes=9, n_mesh_nodes_per_axis=4,
                n_comp=2, max_iter=15, tolerance=1e-8, center=False, gcv_probes=12, gcv_seed=42,
                mean_gcv_probes=12, mean_gcv_seed=42, mean_lambda_grid=[0.001, 0.1],
                lambda_grid=[0.001, 0.1], fixed_direction_lambda=0.01, fixed_loading_lambda=0.1,
                provenance={"test": "public_model_consumers"})


def close_matrix(left, right, label, tolerance=2e-10):
    # dimensions are part of the oracle, so dropping a response column cannot pass
    assert len(left) == len(right) and all(len(a) == len(b) for a, b in zip(left, right)), label
    for a, b in zip(left, right):
        for x, y in zip(a, b):
            # allow equal missing compatibility values and numerical roundoff from model relocation
            assert (math.isnan(x) and math.isnan(y)) or math.isclose(x, y, abs_tol=tolerance, rel_tol=tolerance), (label, x, y)


def multiply(left, right):
    return [[sum(x * y for x, y in zip(row, column)) for column in zip(*right)] for row in left]


def transpose(value):
    return list(map(list, zip(*value)))


def deterministic_telemetry(directory):
    values = json.loads((directory / "telemetry.json").read_text())
    return {key: value for key, value in values.items() if not key.endswith("_seconds")}


def compare_repeated(before, after):
    names = {path.name for path in before.iterdir()}
    # repeated fits must retain the same diagnostics, CSV precision and file manifest
    assert names == {path.name for path in after.iterdir()}, (before, after)
    for name in sorted(names):
        if name == "telemetry.json":
            # wall-clock measurements are the only fields permitted to vary between identical fits
            assert deterministic_telemetry(before) == deterministic_telemetry(after), name
        else:
            # exact serialized equality checks reproducible fit diagnostics and their serialization
            assert (before / name).read_bytes() == (after / name).read_bytes(), (before.name, name)


def close_telemetry(left, right, label):
    if isinstance(left, dict):
        # nested diagnostic metadata retains the same structure within unchanged fields
        assert left.keys() == right.keys(), label
        for key in left:
            close_telemetry(left[key], right[key], f"{label}.{key}")
    elif isinstance(left, list):
        # component and candidate diagnostics retain their full ordered inventory
        assert len(left) == len(right), label
        for a, b in zip(left, right):
            close_telemetry(a, b, label)
    elif isinstance(left, float):
        # floating telemetry allows the same roundoff as exported matrices
        assert math.isclose(left, right, abs_tol=2e-10, rel_tol=2e-10), (label, left, right)
    else:
        # integral counts, settings and textual provenance remain exact
        assert left == right, (label, left, right)


def compare_baseline(before, after, model, brain):
    names = {path.name for path in before.iterdir()}
    added = {"response_diagnostics.csv"} if model == "fPCR" else set()
    # newly explicit response diagnostics are the only extra files in compatible baseline cases
    assert {path.name for path in after.iterdir()} == names | added, (before, after)
    for name in sorted(names - {"telemetry.json"}):
        if name.endswith("_gcv.csv") or "_gcv_h" in name:
            with (before / name).open() as stream:
                old = list(csv.DictReader(stream, skipinitialspace=True))
            with (after / name).open() as stream:
                new = list(csv.DictReader(stream, skipinitialspace=True))
            # unchanged lambda/GCV evaluations survive the added EDF/selection columns and replay rename
            assert len(old) == len(new), name
            common = set(old[0]) & set(new[0]) if old else set()
            for a, b in zip(old, new):
                close_matrix([[float(a[key]) for key in sorted(common)]],
                             [[float(b[key]) for key in sorted(common)]], name)
        else:
            close_matrix(read_matrix(before / name), read_matrix(after / name), name)
    old, new = deterministic_telemetry(before), deterministic_telemetry(after)
    changed = {"schema_version", "fpca_implementation", "fpca_gcv_edf",
               "fpls_loading_gcv_replay_matches_fit", "fpls_loading_gcv_minimum_matches_fit",
               "fpls_loading_gcv_source", "diagnostic_refits", "gcv_probes", "gcv_seed",
               "fpcr_implementation", "gcv_curve_files", "y_latent_scores_available",
               "y_latent_scores_layout", "response_diagnostics_file", "gcv_edf_applied"}
    for key in set(old) - changed:
        if key in new:
            # solver choices, dimensions, lambda selections and deterministic provenance retain their meaning
            close_telemetry(old[key], new[key], key)
        else:
            # only declared schema changes may remove deterministic fields
            assert key in changed, (key, old[key])


def validate_fpcr_prefixes(directory, params, brain):
    X = read_matrix(Path(params["X_file"]))
    Y = read_matrix(Path(params["Y_file"]))
    if brain:
        mean = read_matrix(directory / "functional_mean_locations.csv")
        mean = [row[0] for row in mean] if len(mean) == len(X[0]) else mean[0]
        X = [[value - shift for value, shift in zip(row, mean)] for row in X]
    scores = read_matrix(directory / "x_latent_scores.csv")
    loadings = read_matrix(directory / ("x_loadings_coefficients.csv" if brain else "x_loadings_locations.csv"))
    if not brain:
        directions = read_matrix(directory / "x_space_directions_locations.csv")
        # original-X directions must undo all preceding component deflations
        close_matrix(multiply(X, directions), scores, "original-X sequential scores", 2e-9)
    for h in range(1, params["n_comp"] + 1):
        prefix = [row[:h] for row in scores]
        fitted = read_matrix(directory / f"y_hat_h{h}.csv")
        beta = read_matrix(directory / (f"beta_coefficients_h{h}.csv" if brain else f"beta_locations_h{h}.csv"))
        # every response retains its own regression coefficient and fitted prediction
        assert len(fitted) == len(Y) and all(len(row) == len(Y[0]) for row in fitted), (h, "response dimensions")
        # coefficient fields reproduce prefix predictions on the predictors before all score deflations
        close_matrix(multiply(X, beta), fitted, f"beta prefix {h}", 2e-9)
        reconstructed = read_matrix(directory / f"x_hat_locations_h{h}.csv")
        # reconstruction uses precisely the retained sequential scores and normalized loadings
        close_matrix(multiply(prefix, transpose([row[:h] for row in loadings])), reconstructed,
                     f"reconstruction prefix {h}", 2e-9)
        residual = [[truth - estimate for truth, estimate in zip(a, b)] for a, b in zip(Y, fitted)]
        normal = multiply(transpose(prefix), residual)
        # the independent OLS normal equations detect reusing the full regression for an earlier prefix
        assert max(abs(value) for row in normal for value in row) < 2e-8, (h, "OLS normal equations", normal)
    response = list(csv.DictReader((directory / "response_diagnostics.csv").open(), skipinitialspace=True))
    # one diagnostic row per prefix and response prevents scalar-only summaries of multivariate Y
    assert len(response) == params["n_comp"] * len(Y[0]), "response diagnostics inventory"
    for row in response:
        h, q = int(float(row["component"])), int(float(row["response"]))
        fitted = read_matrix(directory / f"y_hat_h{h}.csv")
        sse = sum((a[q - 1] - b[q - 1]) ** 2 for a, b in zip(Y, fitted))
        # SSE and MSE use the matching response column rather than a flattened or first-column error
        close_matrix([[sse, sse / len(Y)]], [[float(row["sse"]), float(row["mse"])]], "response errors")


def validate_gcv(directory, params):
    files = list(directory.glob("*_gcv_h*.csv"))
    if (directory / "fpca_gcv.csv").exists():
        files.append(directory / "fpca_gcv.csv")
    if (directory / "fpls_loading_gcv.csv").exists():
        files.append(directory / "fpls_loading_gcv.csv")
    for path in files:
        rows = list(csv.DictReader(path.open(), skipinitialspace=True))
        by_component = {}
        for row in rows:
            by_component.setdefault(row.get("component", "1"), []).append(row)
        for curve in by_component.values():
            # the exported candidate order is the actual fit grid, including all retained EDF evaluations
            assert [float(row["lambda"]) for row in curve] == params["lambda_grid"], path
            values = [float(row["gcv"]) for row in curve]
            selected = [i for i, row in enumerate(curve) if float(row["selected_by_fit"]) == 1]
            # exactly the optimizer's first minimum is marked as selected
            assert selected == [min(range(len(values)), key=values.__getitem__)], path
            # EDF is saved for every evaluated candidate and contains finite numerical fit diagnostics
            assert all(math.isfinite(float(row["edf"])) and math.isfinite(float(row["gcv"])) for row in curve), path


def run(binary, params, directory):
    directory.mkdir()
    parameter_file = directory / "params.json"
    parameter_file.write_text(json.dumps({**params, "output_dir": str(directory / "output")}))
    result = subprocess.run([str(binary), str(parameter_file)], capture_output=True, text=True, timeout=60)
    # successful fits must complete through the same command-line entry point used by the R wrappers
    assert result.returncode == 0, (binary, result.stdout, result.stderr)
    return directory / "output"


def main():
    baseline = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
    simulation = Path(__file__).resolve().parents[1]
    application = simulation.parent / "fPLS-application"
    with tempfile.TemporaryDirectory(prefix="fpls-public-model-check-") as temporary:
        work = Path(temporary)
        for target, dimension in [("1D", 1), ("GCV", 1), ("2D", 2), ("2D-predictive-order", 2), ("brain", 3)]:
            directory = work / target
            directory.mkdir()
            params = inputs(directory, dimension)
            binary = (application if target == "brain" else simulation) / "build" / target / "fit_model"
            if baseline:
                cases = [("R1_fPLS", calibration, {}) for calibration in ("fixed", "gcv")]
                cases += [("fPCR", "fixed", {})]
                if dimension != 3:
                    cases += [("fPCR", "fixed", {"fixed_direction_lambda": "unused", "gcv_probes": "unused",
                                                "gcv_seed": "unused", "save_gcv_curves": "unused"})]
                if dimension == 1:
                    cases += [("R1_fPLS", "fixed", {"fixed_direction_lambda": [0.01, 0.1], "fixed_loading_lambda": [0.1, 0.01]}),
                              ("R1_fPLS", "gcv", {"save_gcv_curves": True})]
                if dimension == 3:
                    cases += [("fPCR", "gcv", {})]
                    cases += [(model, "fixed", {"write_beta": False, "write_reconstructions": False})
                              for model in ("R1_fPLS", "fPCR")]
                    cases += [("R1_fPLS", "fixed", {"fixed_fpca_lambda": "unused"})]
                for index, (model, calibration, extra) in enumerate(cases):
                    case = {**params, "model": model, "calibration": calibration, **extra}
                    old = run(baseline / target, case, directory / f"old-{index}")
                    new = run(binary, case, directory / f"baseline-new-{index}")
                    compare_baseline(old, new, model, dimension == 3)
                    print(f"OK baseline {target}: {model}, {calibration}, {extra}", flush=True)
            for responses in (1, 3):
                params = inputs(directory, dimension, responses)
                for model in ("R1_fPLS", "fPCR"):
                    for calibration, seed in (("fixed", 42), ("gcv", 0), ("gcv", 42)):
                        case = {**params, "model": model, "calibration": calibration, "gcv_seed": seed,
                                "n_comp": 3, "lambda_grid": [0.0001, 0.01, 1]}
                        if dimension == 1 and model == "R1_fPLS" and calibration == "gcv":
                            case["save_gcv_curves"] = True
                        label = f"{model}-{calibration}-{seed}-{responses}"
                        first = run(binary, case, directory / f"new-{label}")
                        second = run(binary, case, directory / f"repeat-{label}")
                        compare_repeated(first, second)
                        if model == "fPCR":
                            validate_fpcr_prefixes(first, case, dimension == 3)
                        if calibration == "gcv":
                            validate_gcv(first, case)
                        print(f"OK public {target}: {model}, {calibration}, seed={seed}, responses={responses}", flush=True)
            # an omitted model name selects the default simulation fPLS model
            if dimension != 3:
                case = {**params, "model": "R1_fPLS", "calibration": "fixed"}
                expected = run(binary, case, directory / "explicit-fpls")
                case.pop("model")
                actual = run(binary, case, directory / "default-fpls")
                # identical fitted fields and metadata verify that the default uses the explicit fPLS path
                compare_repeated(expected, actual)
            for changes in ({"center": True}, {"n_comp": 0}, {"calibration": "invalid"}, {"lambda_grid": []}, {"gcv_probes": 0}, {"model": "unknown"}):
                for model in ("R1_fPLS", "fPCR"):
                    case = {**params, "model": model, "calibration": "gcv", **changes,
                            "output_dir": str(directory / "invalid-output")}
                    path = directory / "invalid.json"
                    path.write_text(json.dumps(case))
                    result = subprocess.run([str(binary), str(path)], capture_output=True, timeout=60)
                    # trust-boundary validation rejects invalid inputs before exporting a successful fit
                    assert result.returncode != 0, (target, model, changes)
                    if changes.get("model") == "unknown":
                        # unsupported names report the model-selection error instead of fitting another model
                        assert b"model must be R1_fPLS or fPCR" in result.stderr, (target, result.stderr)
    print("Compatible baseline outputs, all response prefixes and reproducible GCV diagnostics verified.")


if __name__ == "__main__":
    main()
