#!/usr/bin/env Rscript

suppressMessages(library(jsonlite))
source("src/utils/directories.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("usage: write_runtime_metadata.R <test-suite> <test-name>", call. = FALSE)
}

value_or_null <- function(name) {
  value <- Sys.getenv(name, unset = "")
  if (nzchar(value)) value else NULL
}

command_value <- function(command, args = character()) {
  tryCatch({
    output <- system2(command, args, stdout = TRUE, stderr = FALSE)
    if (length(output)) trimws(output[1]) else NULL
  }, error = function(...) NULL, warning = function(...) NULL)
}

linux_value <- function(path, field) {
  if (!file.exists(path)) return(NULL)
  line <- grep(paste0("^", field, "[[:space:]]*:"), readLines(path), value = TRUE)
  if (!length(line)) return(NULL)
  trimws(sub("^[^:]*:[[:space:]]*", "", line[1]))
}

memory_mib <- function() {
  value <- linux_value("/proc/meminfo", "MemTotal")
  if (!is.null(value)) return(as.integer(sub("[[:space:]].*$", "", value)) %/% 1024L)
  bytes <- command_value("sysctl", c("-n", "hw.memsize"))
  if (!is.null(bytes) && grepl("^[0-9]+$", bytes)) return(as.integer(as.numeric(bytes) / 1024^2))
  NULL
}

nodefile <- value_or_null("PBS_NODEFILE")
allocated_slots <- allocated_nodes <- NULL
if (!is.null(nodefile) && file.exists(nodefile)) {
  hosts <- readLines(nodefile, warn = FALSE)
  allocated_slots <- length(hosts)
  allocated_nodes <- length(unique(hosts))
}

os <- Sys.info()
cpu_model <- linux_value("/proc/cpuinfo", "model name")
if (is.null(cpu_model)) cpu_model <- command_value("sysctl", c("-n", "machdep.cpu.brand_string"))

metadata <- list(
  captured_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  suite = args[1],
  requested_test = args[2],
  git_commit = command_value("git", c("rev-parse", "HEAD")),
  host = list(
    hostname = unname(os[["nodename"]]),
    os = unname(os[["sysname"]]),
    os_release = unname(os[["release"]]),
    architecture = unname(os[["machine"]]),
    cpu_model = cpu_model,
    logical_cores = parallel::detectCores(logical = TRUE),
    physical_cores = parallel::detectCores(logical = FALSE),
    memory_mib = memory_mib()
  ),
  scheduler = list(
    pbs = list(
      job_id = value_or_null("PBS_JOBID"),
      allocated_slots = allocated_slots,
      allocated_nodes = allocated_nodes,
      requested_cores = value_or_null("PBS_MULTI_CPUS"),
      requested_memory = value_or_null("PBS_MULTI_MEM"),
      requested_walltime = value_or_null("PBS_MULTI_TIME"),
      queue = value_or_null("PBS_QUEUE"),
      account = value_or_null("PBS_ACCOUNT"),
      exclusive_resource = value_or_null("PBS_EXCLUSIVE_RESOURCE")
    ),
    slurm = list(
      job_id = value_or_null("SLURM_JOB_ID"),
      node_list = value_or_null("SLURM_NODELIST"),
      allocated_cores = value_or_null("SLURM_CPUS_ON_NODE")
    )
  ),
  thread_environment = list(
    omp_num_threads = value_or_null("OMP_NUM_THREADS"),
    openblas_num_threads = value_or_null("OPENBLAS_NUM_THREADS"),
    veclib_maximum_threads = value_or_null("VECLIB_MAXIMUM_THREADS")
  )
)

cfg <- load_config()
output_dir <- file.path(cfg$PATH_RESULTS, args[1])
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
write_json(
  metadata,
  file.path(output_dir, "runtime_metadata.json"),
  auto_unbox = TRUE,
  pretty = TRUE,
  null = "null"
)
