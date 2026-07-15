#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./cpp/run.sh [options] -- <command> [args...]
  ./cpp/run.sh --describe

Options:
  --workdir DIR, --cwd DIR  Run the command from DIR.
  --quiet                  Do not print runtime information before running.
  --describe               Print the selected runtime and exit.
  -h, --help               Show this help.

The runtime is selected from .env:
  - empty SINGULARITY_IMAGE: run on the host
  - filled SINGULARITY_IMAGE: run through apptainer or singularity exec
USAGE
}

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${CPP_DIR}/.." && pwd)"
QUIET=0
DESCRIBE=0
WORKDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      QUIET=1
      shift
      ;;
    --describe)
      DESCRIBE=1
      shift
      ;;
    --workdir|--cwd)
      if [[ $# -lt 2 ]]; then
        echo "Error: $1 requires a directory." >&2
        exit 1
      fi
      WORKDIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
  echo "Error: .env not found. Run: make build TESTBENCH_PROFILE=<profile>" >&2
  exit 1
fi

set -a
source "${PROJECT_DIR}/.env"
set +a

display_path() {
  local path="$1"

  if [[ "${path}" == "${PROJECT_DIR}" ]]; then
    printf '.'
  elif [[ "${path}" == "${PROJECT_DIR}/"* ]]; then
    printf '%s' "${path#"${PROJECT_DIR}/"}"
  else
    printf '%s' "${path}"
  fi
}

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export VECLIB_MAXIMUM_THREADS="${VECLIB_MAXIMUM_THREADS:-1}"

WORKDIR="${WORKDIR:-${PATH_REPO:-${PROJECT_DIR}}}"

if [[ -n "${SINGULARITY_IMAGE:-}" ]]; then
  if command -v apptainer >/dev/null 2>&1; then
    CONTAINER_RUNTIME="apptainer"
    RUNTIME="Apptainer"
  elif command -v singularity >/dev/null 2>&1; then
    CONTAINER_RUNTIME="singularity"
    RUNTIME="Singularity"
  else
    echo "Error: SINGULARITY_IMAGE is set, but Apptainer and SingularityCE are unavailable." >&2
    exit 1
  fi

  if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
    echo "Error: Singularity image not found: ${SINGULARITY_IMAGE}" >&2
    exit 1
  fi
else
  RUNTIME="host"
fi

if [[ "${DESCRIBE}" -eq 1 || "${QUIET}" -eq 0 ]]; then
  echo "Runtime: ${RUNTIME}"
  if [[ -n "${SINGULARITY_IMAGE:-}" ]]; then
    echo "Image: ${SINGULARITY_IMAGE}"
    echo "Bind paths: ${SINGULARITY_BIND_PATHS:-}"
  fi
  echo "Working directory: $(display_path "${WORKDIR}")"
fi

if [[ "${DESCRIBE}" -eq 1 ]]; then
  exit 0
fi

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

cd "${WORKDIR}"

if [[ -n "${SINGULARITY_IMAGE:-}" ]]; then
  singularity_args=()
  if [[ -n "${SINGULARITY_BIND_PATHS:-}" ]]; then
    singularity_args+=(--bind "${SINGULARITY_BIND_PATHS}")
  fi

  exec "${CONTAINER_RUNTIME}" exec "${singularity_args[@]}" "${SINGULARITY_IMAGE}" "$@"
fi

exec "$@"
