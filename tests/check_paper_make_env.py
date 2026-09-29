"""Run with python3; checks Make recipes without R packages or simulation data."""

import os
from pathlib import Path
import subprocess
import tempfile


makefile = Path(__file__).resolve().parents[1] / "Makefile"
with tempfile.TemporaryDirectory(prefix="fpls-paper-make-") as directory:
    root = Path(directory)
    rscript = root / "Rscript"
    rscript.write_text("""#!/bin/sh
[ "$1" = '-e' ] && exit 0
printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$1" "$R_LIBS_USER" "$R_LIBS_SITE" "$FPLS_RESULTS" "$FPLS_GCV_HORIZONTAL_FINAL"
[ "$1" != "$FPLS_FAIL_SCRIPT" ]
""")
    rscript.chmod(0o755)
    env = dict(os.environ, R_LIBS_USER="inherited user library", R_LIBS_SITE="inherited site library",
               FPLS_RESULTS="/external results", FPLS_GCV_HORIZONTAL_FINAL="false", FPLS_FAIL_SCRIPT="")

    def run(target, fail="", figure=""):
        return subprocess.run(
            ["make", "--no-print-directory", "-f", str(makefile), target,
             f"RSCRIPT={rscript}", f"FIGURE={figure}"],
            cwd=root, env=dict(env, FPLS_FAIL_SCRIPT=fail), capture_output=True, text=True,
        )

    targets = ("simulation_figure_panels", "simulation_paper_tables")
    for configured in (False, True):
        if configured:
            (root / ".env").write_text(
                "TESTBENCH_PROFILE='windows'\nR_LIBS_USER='/custom user library'\n"
                "R_LIBS_SITE='/custom site library'\n"
            )
        expected_libraries = (["/custom user library", "/custom site library"] if configured
                              else [env["R_LIBS_USER"], env["R_LIBS_SITE"]])
        for target, figure, count in (
            (targets[0], "", 16), (targets[1], "", 1),
            (targets[0], "1D_vary_k", 1), (targets[0], "S_1D_gcv_sensitivity", 1),
        ):
            result = run(target, figure=figure)
            assert result.returncode == 0, result.stderr
            rows = [line.split("\t") for line in result.stdout.splitlines()]
            assert len(rows) == count, rows
            if figure:
                assert rows[0][0] == f"paper-figures/scripts/{figure}.R", rows
            for script, user, site, results, gcv_mode in rows:
                assert [user, site] == expected_libraries, (script, user, site)
                assert results == env["FPLS_RESULTS"], (script, results)
                assert gcv_mode == ("true" if script.endswith("S_1D_gcv_sensitivity.R") else "false")

    result = run(targets[0], figure="missing_figure")
    assert result.returncode != 0 and not result.stdout and "Unknown FIGURE" in result.stderr

    failed_script = "paper-figures/scripts/1D_vary_k.R"
    result = run(targets[0], fail=failed_script)
    assert result.returncode != 0
    assert [line.split("\t")[0] for line in result.stdout.splitlines()] == [
        "paper-figures/scripts/1D_data.R", failed_script,
    ], result.stdout

    (root / ".env").write_text("false\n")
    for target in targets:
        result = run(target)
        assert result.returncode != 0 and not result.stdout, result

print("PASS: all/single-figure targets load .env, preserve external results, and stop on errors.")
