# Prespecified study protocol

## Objective

Develop an explainable early prediction model for late or persistent delirium
in older ICU patients using MIMIC-IV and evaluate transportability in eICU-CRD.
Latent trajectory discovery and bedside-score distillation are exploratory
secondary analyses.

## Cohorts

### Development cohort

- MIMIC-IV version 3.1.
- Age at ICU admission at least 65 years.
- First ICU stay for each patient in the database.
- ICU length of stay greater than 24 hours.
- Primary incident cohort: at least one negative delirium screen during ICU
  hour 0-24, no positive screen in that interval, and at least two assessable
  daily outcomes during ICU days 2-5.

### External evaluation cohort

- eICU-CRD version 2.0.
- Age at least 65 years; top-coded age greater than 89 is represented as 90.
- First unit visit and ICU stay longer than 24 hours.
- The primary cohort uses CAM-ICU only. ICDSC is reserved for sensitivity
  analysis because it is a different measurement instrument.
- eICU hospital is retained for center-level sensitivity analyses.
- External confidence intervals use two-stage hospital-and-patient bootstrap
  resampling to reflect multicenter clustering and within-hospital sampling.

## Time origin and boundaries

- Time zero: ICU admission.
- Predictor window: `0 <= event time < 24 hours`.
- Baseline delirium exclusion: `0 <= screen time <= 24 hours`.
- Outcome day 2: `24 < screen time <= 48 hours`.
- Outcome days 3-5 use the same left-open, right-closed 24-hour bins.
- Measurements after hour 24 are never predictors.

## Delirium outcome

Each assessable day is positive if any validated screen is positive; otherwise
it is negative if at least one validated screen is negative. Unassessable,
missing, discharged, and dead states are retained separately rather than coded
as negative.

The MIMIC trajectory model compares one through four latent classes using a
quadratic time function. Selection requires convergence, minimum class size of
5%, and considers BIC, entropy, posterior probabilities, and clinical
interpretability. Multiple random starts are used.

The prespecified portable binary outcome is `late_persistent_delirium`:

- at least two assessable outcome days; and
- at least two positive days, or a positive result on the last assessable day.

The same `late_persistent_delirium` rule is the prediction target in MIMIC and
the external reference in eICU. The selected MIMIC latent class with the highest
combined overall and late delirium burden is used only for exploratory
trajectory analysis. Applying the frozen MIMIC trajectory model to eICU outcome
paths is secondary and cannot replace validation against the harmonized binary
reference.

## Prediction models

- Clinical baseline: demographics, comorbidity, vital signs, laboratory tests,
  mechanical ventilation, vasopressors, and renal replacement therapy.
- Nursing-assessment and treatment-enhanced: clinical baseline plus candidate
  GCS, RASS, pain, restraint, sedation, benzodiazepine, opioid,
  antipsychotic, and transfusion exposure.
- Bedside score: exploratory sparse logistic model distilled from the leading
  SHAP predictors of the nursing-assessment and treatment-enhanced model.

Patient-level grouped five-fold cross-validation is used in MIMIC. Hyperparameter
tuning is confined to development data. Each inner search and the final
development-cohort search use the same 20-configuration budget. The final frozen
model is evaluated in eICU without refitting.

Primary transportable models retain only features with no more than 40%
missingness in either cohort and do not include missingness indicators.
Models using missingness indicators and the complete requested feature set are
sensitivity analyses because recording processes differ between databases.
The enhanced model denotes nurse-documented neurologic and sedation assessments
plus early treatment exposures. It does not imply that every incremental
variable is exclusively nurse-generated or causally attributable to nursing
care. The exact eight-feature incremental manifest is saved with results.

## Performance

- Binary discrimination: AUROC and AUPRC.
- Calibration: calibration intercept, calibration slope, Brier score, and
  expected calibration error.
- Classification: sensitivity, specificity, PPV, and NPV at the MIMIC
  out-of-fold Youden threshold.
- Clinical utility: decision curve analysis.
- Multiclass secondary analysis: macro and weighted one-vs-rest AUROC,
  multiclass log loss, multiclass Brier score, and accuracy.
- Center sensitivity: all eICU hospitals are reported with assessment coverage.
  Hospital-specific AUROC confidence intervals are estimated where there are at
  least 5 events and 20 non-events; calibration is estimated where there are at
  least 10 events and 10 non-events.
- Assessment-selection mechanism: compare patient-only, hospital-only, and
  patient-plus-hospital models for adequate CAM-ICU outcome assessment, with
  parallel models using measured teaching status, bed-number category, and
  region.
  Cross-validated raw-feature permutation importance quantifies the contribution
  of hospital identity versus patient characteristics.
  Folds are grouped by patient rather than held out by hospital because this
  analysis quantifies known-site assessment-policy differences; it is not an
  attempt to predict practice at an unseen hospital.

## Missing data and sensitivity analyses

- Model preprocessing estimates imputation values only from development folds.
- Missingness indicators are disabled in the primary models and evaluated in
  sensitivity models.
- Variables with more than 40% missingness in either database are excluded from
  primary transportable models.
- Primary analysis requires observed negative baseline screening and at least
  two assessable outcome days.
- Sensitivity analyses include the loose baseline cohort and an eICU
  CAM-ICU-or-ICDSC outcome.
- Assessment-selection propensity models and stabilized inverse-probability
  weights quantify sensitivity to differential CAM-ICU coverage. Effective
  sample size and propensity overlap must accompany weighted estimates.
- Severe propensity non-overlap or a markedly reduced weighted effective sample
  size precludes interpreting IPW estimates as corrected population performance.
- Antipsychotic exposure is removed in a sensitivity model because it may
  represent treatment of early neuropsychiatric symptoms.
- Psychiatric disorder, ICU type, and race are separately omitted in
  coding-harmonization analyses.
- Alternative outcomes require either at least two positive observed days or
  any positive post-24-hour day.
- Full-feature L2-regularized logistic models benchmark the contribution of
  feature content against model complexity.
- Performance is summarized by sex, age group, and harmonized race when a
  subgroup contains at least 20 events and 20 non-events.
- Sparse restraint and transfusion variables are excluded from predictive
  modeling if prevalence is clinically or statistically inadequate.
- The bedside score is not presented as deployable unless external
  discrimination and calibration are adequate.

## Leakage exclusions

Post-24-hour assessment count, first delirium time, future ICU length of stay,
hospital mortality, discharge state, and all outcome-summary fields are audit
or endpoint variables only. They cannot enter a prediction model.

## Dated analysis amendments

On 2026-07-27, after the first cross-database results were reviewed:

- the implementation was corrected so that the prespecified
  `late_persistent_delirium` rule is used as the prediction target in both
  MIMIC and eICU; legacy mismatched-target results were archived;
- primary transportable features were restricted to no more than 40%
  missingness in either database, without missingness indicators;
- eICU nurse-charted C/F temperature recovery received a source, conversion,
  coverage, and sentinel-value audit; and
- assessment-selection ablation and permutation analyses were added to
  characterize the severe external-cohort coverage restriction;
- hospital-level bootstrap resampling, calibration confidence intervals,
  apparent recalibration diagnostics, measured hospital attributes, alternative
  endpoints, regularized logistic benchmarks, and subgroup analyses were added
  during manuscript review.

These amendments and their rationale must be identified as data-quality and
transportability analyses rather than described as fully prespecified.

## Reporting

The manuscript will follow TRIPOD+AI, use PROBAST+AI for risk-of-bias review,
and report trajectory analysis using GRoLTS. Code may be shared; PhysioNet raw
data and row-level derivatives will not be redistributed.

- TRIPOD+AI: https://doi.org/10.1136/bmj-2023-078378
- PROBAST+AI: https://doi.org/10.1136/bmj-2024-082505
- GRoLTS: https://doi.org/10.1080/10705511.2016.1247646
