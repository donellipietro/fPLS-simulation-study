suppressMessages(library(jsonlite))

output_root <- tempfile("fpls-runtime-metadata-")
on.exit(unlink(output_root, recursive = TRUE), add = TRUE)
previous_output <- Sys.getenv("TESTBENCH_OUTPUT", unset = "")
on.exit(Sys.setenv(TESTBENCH_OUTPUT = previous_output), add = TRUE)
Sys.setenv(TESTBENCH_OUTPUT = output_root)

status <- system2(
  "Rscript",
  c("src/write_runtime_metadata.R", "metadata-smoke", "vary_m"),
  stdout = TRUE,
  stderr = TRUE
)
if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
  stop(paste(status, collapse = "\n"))
}

metadata_file <- file.path(output_root, "results", "metadata-smoke", "runtime_metadata.json")
if (!file.exists(metadata_file)) stop("runtime metadata file was not written")
metadata <- fromJSON(metadata_file, simplifyVector = FALSE)
stopifnot(
  identical(metadata$suite, "metadata-smoke"),
  identical(metadata$requested_test, "vary_m"),
  nzchar(metadata$host$hostname),
  !is.null(metadata$host$logical_cores),
  !is.null(metadata$thread_environment)
)
cat("runtime metadata smoke check passed\n")
