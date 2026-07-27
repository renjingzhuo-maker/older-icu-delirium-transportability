# Explainable Older ICU Delirium Prediction and Transportability

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21613442.svg)](https://doi.org/10.5281/zenodo.21613442)

Reproducible code for:

> Explainable Prediction of Late or Persistent Delirium in Serially Assessed
> Older ICU Patients: Development in MIMIC-IV and Multicenter Transportability
> Assessment in eICU-CRD

The study develops a first-24-hour prediction model in MIMIC-IV v3.1 and
evaluates it without refitting in eICU-CRD v2.0. It also examines nursing
assessment and treatment variables, model explanation, calibration,
assessment-selection bias, hospital-level heterogeneity, and exploratory
delirium trajectories. The repository also contains alternative-endpoint,
regularized-logistic, coding-harmonization, and demographic subgroup analyses.

## Study Design

- Population: first eligible ICU stay among adults aged 65 years or older.
- Landmark: ICU hour 24.
- Predictor window: ICU admission through strictly before hour 24.
- Outcome window: strictly after hour 24 through ICU day 5.
- Primary outcome: the same rule-based late or persistent delirium endpoint in
  both databases.
- Development: MIMIC-IV v3.1.
- External evaluation: eICU-CRD v2.0, without model refitting.

The locked analysis rules are documented in
[`docs/STUDY_PROTOCOL.md`](docs/STUDY_PROTOCOL.md).

## Repository Contents

```text
.
|-- sql/
|   |-- mimic_base_extraction/
|   `-- trajectory_pipeline/
|-- manuscript/
|-- docs/
|-- data/                 # local generated data; ignored by Git
|-- results/              # local generated results; ignored by Git
|-- 07_export_analysis_data.ps1
|-- 08_fit_gbtm.R
|-- 09_train_validate_models.py
|-- 16_analyze_assessment_selection.py
|-- 17_run_posthoc_diagnostics.ps1
|-- 20_run_revision_analyses.py
|-- 21_rerun_primary_models.py
|-- 22_run_subgroup_analysis.py
|-- 23_refresh_external_uncertainty.py
|-- 24_rerun_ancillary_models.py
|-- requirements.txt
`-- R_PACKAGES.txt
```

## Data Access

This repository does not contain MIMIC-IV or eICU-CRD data, patient-level
derived datasets, patient or stay identifiers, patient-level predictions, or
fitted model objects.

Researchers must obtain credentialed access to the source databases through
PhysioNet, complete the required training, sign the applicable data-use
agreements, and load the data locally:

- MIMIC-IV v3.1: <https://physionet.org/content/mimiciv/3.1/>
- eICU-CRD v2.0: <https://physionet.org/content/eicu-crd/2.0/>

See [`DATA_GOVERNANCE.md`](DATA_GOVERNANCE.md) before running or modifying the
pipeline.

## Requirements

- PostgreSQL with `psql` available on `PATH`
- MIMIC-IV v3.1 loaded as `mimiciv_hosp` and `mimiciv_icu`
- Official MIMIC derived concepts loaded as `mimiciv_derived`
- eICU-CRD v2.0 loaded as `eicu_crd`
- Python 3.13 with packages in `requirements.txt`
- R 4.6 with packages in `R_PACKAGES.txt`
- PowerShell 7 or Windows PowerShell 5.1 for export helpers

The database build code maintained by MIT-LCP is available from:

- <https://github.com/MIT-LCP/mimic-code>
- <https://github.com/MIT-LCP/eicu-code>

## Environment Setup

Create and activate a Python environment, then install the pinned packages:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Install the required R packages:

```powershell
Rscript install_r_packages.R
```

PostgreSQL authentication should be configured locally using a `.pgpass` file,
the system credential manager, or an interactive password prompt. Do not put a
database password in scripts or commit it to Git.

## Reproduction Workflow

Run commands from the repository root. Adjust database names if your local
installation differs.

### 1. Build MIMIC-IV Base Features

Build the official MIMIC derived concepts first. Then run:

```powershell
psql -X -v ON_ERROR_STOP=1 -d mimiciv -f sql/trajectory_pipeline/00_create_study_indexes.sql
psql -X -v ON_ERROR_STOP=1 -d mimiciv -f sql/mimic_base_extraction/01_build_mimiciv_delirium_24h.sql
psql -X -v ON_ERROR_STOP=1 -d mimiciv -f sql/mimic_base_extraction/02_run_qa_checks.sql
```

### 2. Build Daily Outcomes and Harmonized Features

MIMIC-IV:

```powershell
psql -X -v ON_ERROR_STOP=1 -d mimiciv -f sql/trajectory_pipeline/01_build_mimic_daily_delirium.sql
psql -X -v ON_ERROR_STOP=1 -v database=mimic -d mimiciv -f sql/trajectory_pipeline/06_build_outcome_summaries.sql
psql -X -v ON_ERROR_STOP=1 -d mimiciv -f sql/trajectory_pipeline/03_qa_mimic_daily_delirium.sql
psql -X -v ON_ERROR_STOP=1 -v database=mimic -d mimiciv -f sql/trajectory_pipeline/11_qa_analysis_tables.sql
```

eICU-CRD:

```powershell
psql -X -v ON_ERROR_STOP=1 -d eicu -f sql/trajectory_pipeline/02_build_eicu_daily_delirium.sql
psql -X -v ON_ERROR_STOP=1 -d eicu -f sql/trajectory_pipeline/05_build_eicu_features_24h.sql
psql -X -v ON_ERROR_STOP=1 -v database=eicu -d eicu -f sql/trajectory_pipeline/06_build_outcome_summaries.sql
psql -X -v ON_ERROR_STOP=1 -d eicu -f sql/trajectory_pipeline/04_qa_eicu_daily_delirium.sql
psql -X -v ON_ERROR_STOP=1 -v database=eicu -d eicu -f sql/trajectory_pipeline/11_qa_analysis_tables.sql
```

### 3. Export Local Analysis Files

This step writes restricted patient-level CSV files into the ignored `data/`
directory:

```powershell
.\07_export_analysis_data.ps1 -Psql psql -DatabaseUser postgres
```

### 4. Fit Trajectories and the Full Prediction Workflow

```powershell
Rscript 08_fit_gbtm.R .
python 09_train_validate_models.py .
```

The primary publication models can be regenerated separately:

```powershell
python 21_rerun_primary_models.py .
```

### 5. Run Transportability and Revision Analyses

```powershell
.\17_run_posthoc_diagnostics.ps1 -Psql psql -Python python -DatabaseUser postgres
python 16_analyze_assessment_selection.py .
python 20_run_revision_analyses.py .
python 22_run_subgroup_analysis.py .
python 24_rerun_ancillary_models.py .
```

`23_refresh_external_uncertainty.py` is a maintenance utility that refreshes
hospital-and-patient hierarchical confidence intervals for previously fitted
models.

### 6. Rebuild Manuscript Assets

```powershell
python manuscript/18_build_manuscript_assets.py
python manuscript/19_build_manuscript.py
python manuscript/20_build_reporting_checklist.py
```

## Primary Outputs

The pipeline writes local outputs to `results/` and manuscript assets to
`manuscript/assets/`. These directories may contain source-derived material and
are excluded from the public repository by default.

Aggregate results and interpretation limits are summarized in:

- [`docs/FINAL_RESULTS_SUMMARY.md`](docs/FINAL_RESULTS_SUMMARY.md)
- [`docs/POSTHOC_AUDIT_REPORT.md`](docs/POSTHOC_AUDIT_REPORT.md)

## Reproducibility Notes

- Random seed: `20260726`.
- Predictors are restricted to information available before ICU hour 24.
- Identifiers and post-landmark fields are excluded from prediction.
- External eICU evaluation is performed without refitting.
- External confidence intervals use two-stage hospital-and-patient bootstrap
  resampling.
- Alternative endpoints and L2-regularized logistic models test dependence on
  endpoint definition and algorithm choice.
- Sex, age-group, and harmonized race subgroup estimates are suppressed when
  fewer than 20 events or 20 non-events are available.
- The exploratory trajectory analysis is not the primary prediction target.
- Assessment-selection and hospital-heterogeneity analyses are reported because
  outcome observation was strongly institution dependent.

## Citation

Citation metadata are provided in [`CITATION.cff`](CITATION.cff). The current
release is version 1.1.0. Cite the exact software version used for an analysis:

- Version 1.0.0: <https://doi.org/10.5281/zenodo.21613443>
- Version 1.1.0: <https://doi.org/10.5281/zenodo.21615229>
- All versions (concept DOI): <https://doi.org/10.5281/zenodo.21613442>

The article DOI will be added after publication.

## License

The original code in this repository is released under the MIT License. Access
to and use of MIMIC-IV and eICU-CRD remain governed by their own licenses and
data-use agreements.
