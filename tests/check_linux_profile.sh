#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

Rscript --vanilla - <<'RS'
Sys.unsetenv(c('CC', 'CXX', 'PATH_EIGEN_INCLUDE',
               'TESTBENCH_CC', 'TESTBENCH_CXX', 'TESTBENCH_PATH_EIGEN_INCLUDE'))
source('config.R')
cfg <- get_config('linux')
stopifnot(cfg$TESTBENCH_PROFILE == 'linux', cfg$CC == 'gcc', cfg$CXX == 'g++',
          cfg$PATH_EIGEN_INCLUDE == '/usr/include/eigen3',
          cfg$COMPILE_STRATEGY == 'local', cfg$TEST_EXECUTION_STRATEGY == 'parallel',
          cfg$DOCKER_IMAGE == '', cfg$SINGULARITY_IMAGE == '')
path <- tempfile(fileext = '.env')
write_env(cfg, path)
stopifnot(read_env_file_value('TESTBENCH_PROFILE', path) == 'linux')
unlink(path)
Sys.setenv(CC = '/custom/gcc', CXX = '/custom/g++', PATH_EIGEN_INCLUDE = '/custom Eigen')
source('config.R')
cfg <- get_config('linux')
stopifnot(cfg$CC == '/custom/gcc', cfg$CXX == '/custom/g++',
          cfg$PATH_EIGEN_INCLUDE == '/custom Eigen')
RS

# Inspect the actual compiler flags without cloning dependencies or compiling fits.
source <(sed -n '/^compile_flags() {/,/^}/p' cpp/compile.sh)
unset CXXFLAGS LDFLAGS LDLIBS
PATH_CPP="$PWD/cpp"
PATH_NLOHMANN_JSON="$PWD/libraries/nlohmann-json"
TESTBENCH_PROFILE=linux
SINGULARITY_IMAGE=
DOCKER_IMAGE=
compile_flags
[[ " ${cxx_flags[*]} " == *EIGEN_ARRAYBASE_PLUGIN* ]]
echo 'PASS: Linux defaults, profile export, overrides and Eigen compatibility flags.'
