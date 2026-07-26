suppressPackageStartupMessages({
  library(data.table)
  library(lcmm)
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
study_dir <- if (length(args) >= 1) normalizePath(args[[1]], mustWork = TRUE) else getwd()
data_dir <- file.path(study_dir, "data")
result_dir <- file.path(study_dir, "results", "gbtm")
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

set.seed(20260726)
detected_cores <- parallel::detectCores(logical = FALSE)
if (is.na(detected_cores)) detected_cores <- 2L
trajectory_workers <- min(4L, max(1L, detected_cores - 1L))

mimic <- fread(file.path(data_dir, "mimic_daily_long.csv"))
mimic <- mimic[
  strict_eligible == 1 & !is.na(daily_delirium),
  .(stay_id = as.numeric(stay_id),
    icu_day = as.numeric(icu_day),
    daily_delirium = as.numeric(daily_delirium))
]
valid_ids <- mimic[, .N, by = stay_id][N >= 2, stay_id]
mimic <- mimic[stay_id %in% valid_ids]
mimic[, day_c := icu_day - 2]

if (uniqueN(mimic$stay_id) < 500L) {
  stop("Fewer than 500 strict-eligibility MIMIC stays have at least two valid outcome days.")
}

m1 <- lcmm(
  daily_delirium ~ day_c + I(day_c^2),
  random = ~1,
  subject = "stay_id",
  ng = 1,
  data = mimic,
  link = "thresholds",
  maxiter = 300,
  verbose = FALSE
)

models <- list(m1)
for (k in 2:4) {
  message("Fitting ", k, "-class trajectory model")
  fit_call <- bquote(
    gridsearch(
      rep = 30,
      maxiter = 30,
      minit = m1,
      cl = trajectory_workers,
      lcmm(
        daily_delirium ~ day_c + I(day_c^2),
        mixture = ~day_c + I(day_c^2),
        random = ~1,
        subject = "stay_id",
        ng = .(k),
        data = mimic,
        link = "thresholds",
        maxiter = 300,
        verbose = FALSE
      )
    )
  )
  fit <- eval(fit_call)
  models[[k]] <- fit
}

model_summary <- as.data.table(do.call(
  summarytable,
  c(models, list(
    which = c("G", "loglik", "conv", "npm", "AIC", "BIC", "SABIC",
              "entropy", "ICL", "%class"),
    display = FALSE
  ))
), keep.rownames = "model")
fwrite(model_summary, file.path(result_dir, "gbtm_model_selection.csv"))

eligible <- model_summary[conv == 1 & G >= 2]
class_cols <- grep("^%class", names(eligible), value = TRUE)
if (length(class_cols)) {
  eligible[, min_class_pct := do.call(pmin, c(.SD, na.rm = TRUE)), .SDcols = class_cols]
  eligible <- eligible[min_class_pct >= 5]
}
if ("entropy" %in% names(eligible) && nrow(eligible[entropy >= 0.70]) > 0) {
  eligible <- eligible[entropy >= 0.70]
}
if (nrow(eligible) == 0) {
  stop("No 1-4 class model met convergence and minimum class-size criteria.")
}

selected_row <- eligible[which.min(BIC)]
selected_k <- as.integer(selected_row$G)
selected <- models[[selected_k]]
saveRDS(models, file.path(result_dir, "gbtm_candidate_models.rds"))
saveRDS(selected, file.path(result_dir, "gbtm_selected_model.rds"))

posterior <- as.data.table(selected$pprob)
setnames(posterior, names(posterior)[1], "stay_id")
setnames(posterior, "class", "trajectory_class")
posterior[, stay_id := as.numeric(stay_id)]

assigned <- posterior[, .(stay_id, trajectory_class)]
class_days <- merge(mimic, assigned, by = "stay_id")[
  , .(
    observed_n = .N,
    delirium_probability = mean(daily_delirium)
  ),
  by = .(trajectory_class, icu_day)
]
class_overall <- merge(mimic, assigned, by = "stay_id")[
  , .(
    class_n = uniqueN(stay_id),
    overall_delirium_probability = mean(daily_delirium),
    positive_days_mean = sum(daily_delirium) / uniqueN(stay_id)
  ),
  by = trajectory_class
]
late_prob <- class_days[icu_day >= 4,
                        .(late_delirium_probability = mean(delirium_probability)),
                        by = trajectory_class]
class_profile <- merge(class_overall, late_prob, by = "trajectory_class", all.x = TRUE)
class_profile[, high_risk_score :=
                overall_delirium_probability + late_delirium_probability +
                0.25 * positive_days_mean]
high_risk_class <- class_profile[which.max(high_risk_score), trajectory_class]
class_profile[, high_risk_trajectory := as.integer(trajectory_class == high_risk_class)]

posterior[, high_risk_trajectory := as.integer(trajectory_class == high_risk_class)]
fwrite(posterior, file.path(result_dir, "mimic_trajectory_membership.csv"))
fwrite(class_days, file.path(result_dir, "mimic_trajectory_daily_profiles.csv"))
fwrite(class_profile, file.path(result_dir, "mimic_trajectory_class_summary.csv"))

p <- ggplot(class_days, aes(
  x = icu_day, y = delirium_probability,
  color = factor(trajectory_class), group = trajectory_class
)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = 2:5) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(
    x = "ICU day", y = "Observed delirium probability",
    color = "Trajectory class"
  ) +
  theme_minimal(base_size = 11)
ggsave(file.path(result_dir, "mimic_trajectory_profiles.png"), p,
       width = 7, height = 4.5, dpi = 300)

eicu_path <- file.path(data_dir, "eicu_daily_long.csv")
if (file.exists(eicu_path)) {
  eicu <- fread(eicu_path)
  eicu <- eicu[
    strict_eligible == 1 & !is.na(cam_daily_delirium),
    .(stay_id = as.numeric(patientunitstayid),
      icu_day = as.numeric(icu_day),
      daily_delirium = as.numeric(cam_daily_delirium))
  ]
  eicu_valid_ids <- eicu[, .N, by = stay_id][N >= 2, stay_id]
  eicu <- eicu[stay_id %in% eicu_valid_ids]
  eicu[, day_c := icu_day - 2]
  if (uniqueN(eicu$stay_id) > 0) {
    eicu_posterior <- as.data.table(
      predictClass(selected, newdata = as.data.frame(eicu), subject = "stay_id")
    )
    setnames(eicu_posterior, names(eicu_posterior)[1], "stay_id")
    setnames(eicu_posterior, names(eicu_posterior)[2], "trajectory_class")
    eicu_posterior[, high_risk_trajectory :=
                     as.integer(trajectory_class == high_risk_class)]
    fwrite(eicu_posterior, file.path(result_dir, "eicu_frozen_trajectory_membership.csv"))
  }
}

writeLines(
  c(
    paste0("selected_classes=", selected_k),
    paste0("high_risk_class=", high_risk_class),
    paste0("mimic_stays=", uniqueN(mimic$stay_id))
  ),
  file.path(result_dir, "gbtm_run_summary.txt")
)
