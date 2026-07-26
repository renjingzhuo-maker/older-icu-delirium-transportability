options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  timeout = 600
)

required <- c("lcmm", "data.table", "ggplot2")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(
    missing,
    dependencies = c("Depends", "Imports", "LinkingTo")
  )
}

status <- vapply(required, requireNamespace, logical(1), quietly = TRUE)
print(status)
if (!all(status)) {
  stop("One or more required R packages could not be installed.")
}
