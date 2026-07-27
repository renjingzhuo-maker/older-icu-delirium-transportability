# Post-hoc data-quality and selection-mechanism audit

Updated on 2026-07-27 after correcting the eICU Caucasian race mapping,
negative urine-output sentinel, and invalid GCS/sodium values. Estimates below
come from the final regenerated analysis.

## Scope and grain

The audit covers the eICU strict external-validation cohort at one row per ICU
stay and the full candidate cohort at one row per ICU stay. It addresses two
publication-critical questions:

1. whether the change in first-24-hour temperature missingness from 92.07% to
   0.04% represents valid source recovery or artificial filling; and
2. whether adequate post-landmark CAM-ICU assessment is primarily determined
   by patient characteristics or hospital practice.

## Temperature finding

**Status: passed; high confidence.**

- `vitalPeriodic.temperature` covers 207/2,609 strict-cohort stays (7.93%).
- Valid `nursecharting` temperature covers 2,607/2,609 stays (99.92%).
- The final combined feature covers 2,608/2,609 stays (99.96%).
- There are 23,656 valid paired C/F rows across 2,607 stays.
- Mean and median C/F conversion differences are 0.015°C and 0.011°C.
- 99.97% of paired rows agree within 0.06°C.
- Median nurse-recorded count is 6 per stay; 91.94% have at least 4 readings.
- Only 0.54% of stays have one unique recorded temperature.
- The largest rounded-value concentration is 36.7°C at 8.64%; 37.0°C is 4.70%.
- In 204 overlapping stays, 6,886 nursing records matched a periodic-monitor
  temperature within 15 minutes; median time difference was 1 minute.
- Mean nursing-minus-periodic bias was 0.003°C, mean absolute difference was
  0.030°C, correlation was 0.982, and 95% limits of agreement were
  -0.327°C to 0.332°C.

The earlier 92.07% missingness resulted from using the sparse periodic monitor
source alone. The recovered nursing temperatures are observed raw values in
paired units, not imputed defaults. Numeric parsing, C/F-specific ranges, and
physiologic filtering occur before aggregation.

Automated SQL checks now fail the pipeline if combined coverage falls below
95%, median C/F disagreement exceeds 0.10°C, or one rounded value exceeds 25%
of valid nursing records.

## Assessment-selection finding

**Status: major transportability limitation; high confidence.**

| Selection model | Cross-validated AUROC | AUPRC |
|---|---:|---:|
| Patient features only | 0.717 | 0.132 |
| Measured hospital attributes only | 0.755 | 0.102 |
| Patient features + measured hospital attributes | 0.815 | 0.196 |
| Hospital identity only | 0.936 | 0.312 |
| Hospital identity + patient features | 0.944 | 0.377 |

Cross-validated permutation of hospital identity reduces AUROC by 0.365 on
average. No individual patient feature reduces AUROC by more than 0.004; the
largest mean decrease is 0.00418 for minimum temperature. Hospital identity is
therefore much more strongly associated with whether a patient has enough
CAM-ICU assessment to enter external validation than any single measured
patient feature.

The selection-model folds are grouped by patient, not held out by hospital.
This is intentional: hospital identity is used here to quantify known-site
assessment policy, not to predict practice at a previously unseen hospital.

Only 2,609/57,637 candidate eICU stays (4.53%) enter the strict cohort.
Stabilized IPW reduces effective sample size to approximately 391, indicating
severe non-overlap. Weighted performance is sensitivity evidence only and
cannot be interpreted as correction to the full eICU population.

## Hospital figure representation

- Candidate hospitals: 206
- Hospitals contributing strict-cohort patients: 40
- Hospitals with both outcome classes: 34
- Hospitals meeting forest-plot CI thresholds: 17
- Patients represented in the forest plot: 2,096/2,609 (80.34%)
- Events represented in the forest plot: 270/309 (87.38%)
- Hospitals meeting within-hospital calibration thresholds: 10

Excluded hospitals are predominantly small or have too few events for stable
interval estimates. The forest plot is representative of most patients and
events, but not of most participating hospitals.

## Model naming clarification

The nursing-assessment and treatment-enhanced model adds eight features to the
clinical baseline:

- minimum GCS, minimum RASS, and maximum RASS;
- sedative, benzodiazepine, opioid, antipsychotic, and transfusion exposure.

The manuscript should call this the “nursing-assessment and treatment-enhanced
model.” These variables are clinically relevant to nursing workflows but are
not all exclusive to nursing practice and must not be interpreted causally.

## Publication implications

Temperature can remain in the primary model. The assessment-selection mechanism
should be reported in the main Results and Discussion, not only in a supplement.
The defensible external-validity claim is restricted to eICU hospitals and
patients with sufficient structured CAM-ICU assessment.
