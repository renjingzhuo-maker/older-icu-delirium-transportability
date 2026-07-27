# TRIPOD+AI Reporting Checklist

Study: *Explainable Prediction of Late or Persistent Delirium in Serially Assessed Older ICU Patients: Development in MIMIC-IV and Multicenter Transportability Assessment in eICU-CRD*

This checklist follows the TRIPOD+AI expanded checklist (version 7 February 2024). The accompanying Word attachment adds page references from the current rendered submission draft; section locations are retained because they remain stable if journal typesetting changes page breaks.

| Item | Reporting requirement | Location |
|---|---|---|
| 1 | Identify prediction-model development/evaluation, target population, and outcome in the title | Title |
| 2 | Structured summary of objectives, data, setting, participants, methods, results, and conclusions | Abstract |
| 3a | Healthcare context and rationale, including existing models | Introduction |
| 3b | Target population, intended purpose, users, and care-pathway position | Introduction |
| 3c | Sociodemographic inequalities relevant to model evaluation | Introduction; Strengths and Limitations; Supplementary Table S4 |
| 4 | Development and evaluation objectives | Introduction, final paragraph |
| 5a | Development and evaluation data sources and representativeness | Methods: Study Design and Data Sources |
| 5b | Participant-data dates | Methods: Study Design and Data Sources |
| 6a | Setting, centres, and locations | Methods: Study Design and Data Sources |
| 6b | Eligibility criteria | Methods: Landmark, Eligibility, and Outcome |
| 6c | Treatment exposures and their handling | Methods: Predictor Extraction and Harmonization |
| 7 | Preprocessing, harmonization, and quality checks | Methods: Predictor Extraction and Harmonization; Supplementary Data-Quality Audit |
| 8a | Outcome, horizon, assessment, and rationale | Methods: Landmark, Eligibility, and Outcome |
| 8b | Outcome-assessor qualifications | Not available in retrospective deidentified routine-care data; addressed in Limitations |
| 8c | Blinding of outcome assessment | Routine assessments preceded retrospective model development; Methods: Landmark, Eligibility, and Outcome |
| 9a | Initial predictor choice and preselection | Methods: Predictor Extraction and Harmonization |
| 9b | Predictor definitions, timing, and measurement | Methods: Predictor Extraction and Harmonization; Supplementary Table S1; public SQL |
| 9c | Predictor-assessor qualifications | Not available in deidentified routine-care data; addressed in Limitations |
| 10 | Study-size determination and sufficiency | Methods: Model Development and Internal Validation |
| 11 | Missing-data handling and reasons for omissions | Methods: Predictor Extraction and Harmonization; Supplementary Table S1 |
| 12a | Use and partitioning of development/evaluation data | Methods: Model Development and Internal Validation |
| 12b | Predictor encoding, transformation, and standardization | Methods: Predictor Extraction and Harmonization |
| 12c | Model type, rationale, tuning, and internal validation | Methods: Model Development and Internal Validation |
| 12d | Cluster heterogeneity and handling | Methods: External Evaluation; Hospital-Level Transportability |
| 12e | Performance measures and plots | Methods: External Evaluation and Performance Measures |
| 12f | Model updating/recalibration | Methods: External Evaluation; Results: Primary Model Performance |
| 12g | Calculation of external predictions | Methods: External Evaluation; Code Availability; public code |
| 13 | Class-imbalance methods | None used; Methods: Model Development and Internal Validation |
| 14 | Fairness approaches | Methods: Sensitivity Analyses; Supplementary Table S4 |
| 15 | Probability output and classification threshold | Methods: Model Development and Internal Validation |
| 16 | Development/evaluation differences | Table 1; Supplementary Table S1; Discussion |
| 17 | Ethics approval and consent/waiver | Methods: Software, Reporting, and Ethics; Declarations |
| 18a | Funding and funder role | Declarations: Funding |
| 18b | Conflicts of interest | Declarations: Competing Interests |
| 18c | Protocol availability | Declarations: Protocol and Registration; Methods: Protocol Amendments |
| 18d | Registration | Declarations: Protocol and Registration |
| 18e | Data availability and restrictions | Declarations: Data Availability |
| 18f | Code availability, software, and version | Methods: Software, Reporting, and Ethics; Declarations: Code Availability |
| 19 | Patient and public involvement | Declarations: Patient and Public Involvement |
| 20a | Participant flow and outcome counts | Results: Cohort Formation; Figure 1 |
| 20b | Cohort characteristics and missingness | Table 1; Supplementary Table S1 |
| 20c | Development/evaluation distribution comparison | Table 1; Supplementary Table S1 |
| 21 | Participants and events in each analysis | Results; Tables 1-3; Supplementary Tables S2-S4 |
| 22 | Full model/code and reuse restrictions | Declarations: Code Availability; public repository |
| 23a | Performance with confidence intervals and subgroups | Table 2; Figure 3; Supplementary Tables S3-S4 |
| 23b | Heterogeneity across hospitals | Results: Hospital-Level Heterogeneity; Figure 5 |
| 24 | Model-updating results | Results: Primary Model Performance; apparent recalibration explicitly labelled diagnostic |
| 25 | Interpretation including fairness and comparison with prior studies | Discussion |
| 26 | Limitations, bias, uncertainty, and generalizability | Discussion: Strengths and Limitations |
| 27a | Handling unavailable or poor-quality inputs | Discussion: Calibration, Clinical Usefulness, and Site Heterogeneity |
| 27b | Required user interaction and expertise | Model is not proposed for implementation; Discussion |
| 27c | Future research and applicability | Discussion; Conclusions |

Reference: Collins GS, Moons KGM, Dhiman P, et al. TRIPOD+AI statement. *BMJ*. 2024;385:e078378. doi:10.1136/bmj-2023-078378.
