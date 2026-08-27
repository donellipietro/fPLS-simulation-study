#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/kami_review_job.pbs"

is_truthy() {
  case "${1:-}" in 1|true|TRUE|yes|YES|y|Y) return 0 ;; *) return 1 ;; esac
}

for name in PBS_MULTI_CPUS PBS_MULTI_MEM PBS_MULTI_TIME; do
  if [[ -z "${!name:-}" ]]; then
    echo "Error: ${name} is required for the complete-node Kami submission." >&2
    exit 1
  fi
done
if [[ ! "${PBS_MULTI_CPUS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: PBS_MULTI_CPUS must be the positive number of cores on one complete node." >&2
  exit 1
fi
if ! is_truthy "${PBS_DRY_RUN:-0}" && ! command -v qsub >/dev/null 2>&1; then
  echo "Error: qsub not found in PATH." >&2
  exit 1
fi

RUN_TAG="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="${PROJECT_DIR}/logs/kami/${RUN_TAG}"
export KAMI_RUN_DIR="${RUN_DIR}"

QSUB_ARGS=(-V -N fpls_review -o "${RUN_DIR}/job.out" -e "${RUN_DIR}/job.err")
QSUB_ARGS+=(-l "nodes=1:ppn=${PBS_MULTI_CPUS}" -l "mem=${PBS_MULTI_MEM}")
QSUB_ARGS+=(-l "walltime=${PBS_MULTI_TIME}")
[[ -n "${PBS_QUEUE:-}" ]] && QSUB_ARGS+=(-q "${PBS_QUEUE}")
[[ -n "${PBS_ACCOUNT:-}" ]] && QSUB_ARGS+=(-A "${PBS_ACCOUNT}")
if [[ -n "${PBS_EXCLUSIVE_RESOURCE:-}" ]]; then
  QSUB_ARGS+=(-l "${PBS_EXCLUSIVE_RESOURCE}")
else
  echo "Warning: no site-specific exclusive-node resource was supplied; requesting every" >&2
  echo "configured core is the strongest portable Torque request, not an isolation guarantee." >&2
fi

if is_truthy "${PBS_DRY_RUN:-0}"; then
  printf 'mkdir -p %q\n' "${RUN_DIR}"
  printf 'qsub'
  printf ' %q' "${QSUB_ARGS[@]}" "${JOB_SCRIPT}"
  printf '\n'
  exit 0
fi

mkdir -p "${RUN_DIR}"
JOB_ID="$(qsub "${QSUB_ARGS[@]}" "${JOB_SCRIPT}")"
printf '%s\n' "${JOB_ID}" > "${RUN_DIR}/job_id.txt"
printf 'Submitted %s\nRun directory: %s\n' "${JOB_ID}" "${RUN_DIR}"
