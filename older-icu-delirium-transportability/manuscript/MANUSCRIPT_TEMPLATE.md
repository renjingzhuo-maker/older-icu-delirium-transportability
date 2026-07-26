# Interpretable Machine Learning Prediction of Late or Persistent Delirium in Older ICU Patients: Multicenter Development and Transportability Assessment Using MIMIC-IV and eICU-CRD

**Short title:** Transportability of delirium prediction in older ICU patients

**Authors:** Ren Jingzhuo (1); Zhang Qiannan (1); Liu Lixin (2); Xue Zhaoping (2, corresponding author)

**Affiliations:**
1. School of Nursing, Jilin University, Changchun, China.
2. The First Bethune Hospital of Jilin University, Changchun, China.

**Corresponding author:** Xue Zhaoping, The First Bethune Hospital of Jilin University, No. 1 Xinmin Street, Changchun, Jilin, China, 130021. Email: xuezp@mails.jlu.edu.cn.

**Manuscript status:** Draft for author review

**Word count:** {{WORD_COUNT}}

[[PAGE_BREAK]]

## Abstract

**Background:** Delirium risk models developed from electronic health records may fail across hospitals because both clinical data and delirium assessment practices vary. We developed and externally evaluated an interpretable model for late or persistent delirium in older intensive care unit (ICU) patients and quantified the contribution of the assessment process to transportability.

**Methods:** We conducted a retrospective prediction-model study using MIMIC-IV version 3.1 for development and eICU-CRD version 2.0 for external evaluation. Eligible patients were aged 65 years or older, had a first ICU stay longer than 24 hours, had a documented negative delirium assessment during ICU hours 0-24, and had at least two observed daily Confusion Assessment Method for the ICU assessments during ICU days 2-5. Predictors were restricted to the first 24 hours. Extreme gradient boosting models were evaluated with patient-grouped nested cross-validation in MIMIC-IV and without refitting in eICU-CRD. A clinical baseline model was compared with a nursing-assessment and treatment-enhanced model. We evaluated discrimination, calibration, decision curves, SHapley Additive exPlanations, inverse-probability weighting, and hospital-level heterogeneity.

**Results:** The primary cohorts included {{MIMIC_N}} MIMIC-IV stays ({{MIMIC_EVENTS}} events; {{MIMIC_RATE}}%) and {{EICU_N}} eICU-CRD stays ({{EICU_EVENTS}} events; {{EICU_RATE}}%). The enhanced model achieved an internally validated AUROC of {{ENH_INT_AUROC_CI}} and an external AUROC of {{ENH_EXT_AUROC_CI}}, compared with {{CLIN_INT_AUROC_CI}} and {{CLIN_EXT_AUROC_CI}} for the clinical baseline model. The paired AUROC improvement was {{DELTA_MIMIC}} in MIMIC-IV and {{DELTA_EICU}} in eICU-CRD. External calibration remained imperfect (intercept {{ENH_EXT_CAL_INTERCEPT}}; slope {{ENH_EXT_CAL_SLOPE}}). Only {{EICU_SELECTION_RATE}}% of eICU candidates entered the strict cohort. Selection was predicted substantially better by hospital identity alone (AUROC {{EICU_HOSPITAL_ONLY_AUC}}) than by patient features alone (AUROC {{EICU_PATIENT_ONLY_AUC}}); permuting hospital identity decreased AUROC by {{HOSPITAL_PERMUTATION_DROP}}.

**Conclusions:** Early nursing assessments and treatment exposures improved discrimination across databases, but the model was not ready for bedside deployment because calibration and hospital-level performance were heterogeneous. Hospital-specific delirium assessment practice, rather than patient characteristics alone, was the dominant constraint on external cohort representativeness and model transportability.

**Keywords:** delirium; intensive care unit; older adults; machine learning; external validation; transportability; nursing assessment; selection bias

## Introduction

Delirium is an acute disorder of attention and cognition that is common among critically ill adults and particularly consequential in older patients. In a systematic review of critically ill populations, delirium was associated with greater mortality, longer mechanical ventilation and hospital stay, and subsequent cognitive impairment [1]. Duration and persistence also matter: more delirium days have been associated with worse long-term survival and cognitive outcomes [2,3]. These findings make early identification clinically relevant, provided that prediction occurs before the outcome and supports preventive, low-harm care.

Routine delirium surveillance is central to contemporary ICU practice. The Confusion Assessment Method for the ICU (CAM-ICU) was designed for critically ill patients, including those receiving mechanical ventilation, and showed high agreement with expert assessment in its initial validation [4]. Pain, sedation depth, delirium monitoring, mobility, and sleep are integrated in guideline-based ICU care [5]. Greater performance of the ABCDEF bundle has also been associated with less next-day delirium and other patient-centered benefits [6]. Nurses generate many of the data needed for early risk assessment, including Glasgow Coma Scale (GCS), Richmond Agitation-Sedation Scale (RASS), vital signs, and medication exposure records.

Existing ICU delirium prediction models include PRE-DELIRIC, E-PRE-DELIRIC, and more recent machine-learning approaches [7-10]. Some models have achieved strong discrimination in their development settings, but model accuracy alone does not establish clinical usefulness. Independent evaluation commonly reveals lower discrimination or miscalibration, and external validation remains uncommon among ICU artificial intelligence studies [11]. Transportability may be further compromised when the outcome is recorded only in hospitals that routinely perform structured delirium assessments. Under such informative observation, apparent external validity pertains to a selected care process as well as to a patient population.

We therefore aimed to: (1) develop an interpretable first-24-hour prediction model for late or persistent delirium in older ICU patients; (2) quantify the incremental value of nursing assessments and treatment exposures beyond a harmonized clinical baseline; (3) evaluate transportability from MIMIC-IV to eICU-CRD without model refitting; and (4) determine whether hospital-level delirium assessment practice explained external cohort selection and performance heterogeneity. A secondary exploratory objective was to characterize daily delirium trajectories while avoiding unsupported claims about latent subtypes.

## Methods

### Study Design and Data Sources

This retrospective prediction-model development and external evaluation study used two deidentified critical care databases available through PhysioNet. MIMIC-IV version 3.1 contains detailed hospital and ICU data from Beth Israel Deaconess Medical Center in Boston, Massachusetts [12]. eICU-CRD version 2.0 contains high-granularity data from more than 200 US hospitals participating in the Philips eICU program in 2014-2015 [13]. MIMIC-IV was used for model development and internal validation; eICU-CRD was reserved for external evaluation.

The analysis unit was one ICU stay. We retained the first eligible ICU stay per patient to avoid dependence from repeated admissions and included patients aged 65 years or older with an ICU stay longer than 24 hours. Database-specific identifiers were used only for linkage, grouping, and auditing and were excluded from prediction.

### Landmark, Eligibility, and Outcome

The prediction landmark was ICU hour 24. Predictors were measured during the half-open interval from ICU admission through, but not including, hour 24. Baseline delirium screening used the closed interval from admission through hour 24. Outcome ascertainment began strictly after hour 24 and was summarized by ICU day for days 2-5. Thus, a delirium assessment recorded exactly at hour 24 was used only for baseline exclusion and did not enter either the predictor or outcome window.

The strict primary cohort required at least one documented negative CAM-ICU assessment during the first 24 hours, no positive baseline assessment, and at least two days with a valid CAM-ICU result during ICU days 2-5. A daily outcome was positive when any valid CAM-ICU record on that day was positive; unassessable entries did not count as valid negative assessments.

The primary endpoint, operationally defined as late or persistent delirium, was positive when a patient had at least two delirium-positive observed days or when delirium was present on the last observed outcome day. The same executable rule was applied in both databases. This definition was chosen to distinguish clinically sustained or unresolved dysfunction from a single isolated positive record while retaining patients whose ICU observation ended after a final positive assessment.

### Predictor Extraction and Harmonization

Candidate predictors were selected a priori from information available during routine care in the first 24 ICU hours. They covered demographics and admission context, comorbidities, vital signs, laboratory results, organ-support treatments, neurologic and sedation assessments, and medication or treatment exposures. Minimum and maximum values were used for repeatedly measured physiologic and laboratory features when clinically appropriate.

The primary clinical model contained variables that were available in both databases and had no more than 40% missingness in either primary cohort. The nursing-assessment and treatment-enhanced model added exactly eight variables: minimum GCS, minimum RASS, maximum RASS, sedative exposure, benzodiazepine exposure, opioid exposure, antipsychotic exposure, and transfusion exposure. The term "enhanced" therefore refers to these eight assessment and treatment variables, not to all variables documented by nurses. Outcome times, post-24-hour assessment counts, ICU length of stay, mortality, first delirium time, and other post-landmark fields were excluded to prevent leakage.

Data harmonization used explicit category maps for sex, race, ICU type, and admission type. In eICU-CRD, "Caucasian" was mapped to White using an exact semantic rule rather than an "Asian" substring match. Values outside prespecified valid ranges were set to missing, including negative urine output, GCS outside 3-15, and sodium outside 100-200 mmol/L. The eICU APACHE urine value of -1 was treated as a missing-value sentinel; after this correction, urine output exceeded the 40% external missingness threshold and was excluded from the primary models. Temperature combined nurse-charted Celsius and Fahrenheit values with periodic monitor data. Unit conversion and cross-source agreement were audited separately.

Numeric variables were median-imputed using development data within each cross-validation fit. Categorical variables were imputed with the most frequent development category and one-hot encoded with unknown external categories ignored. The primary models did not include missingness indicators because such indicators can encode institution-specific documentation behavior. Missing-indicator models were evaluated only as sensitivity analyses.

### Model Development and Internal Validation

We fitted extreme gradient boosting classifiers (XGBoost) [14]. The clinical baseline and enhanced models used identical tuning procedures. Internal performance was estimated with five-fold stratified group cross-validation, grouping by patient. Within each outer training fold, hyperparameters were selected by three-fold stratified group cross-validation using eight randomized configurations and AUROC as the optimization metric. A final 20-configuration randomized search was performed on the complete MIMIC-IV development cohort, after which the selected model was refitted on all development observations.

The search space covered 200-700 trees, maximum depth 2-5, learning rate 0.02-0.10, minimum child weight 1-10, row and column subsampling, and L1/L2 regularization. The final enhanced model used {{FINAL_MODEL_PARAMETERS}}. The operating threshold was selected from pooled out-of-fold MIMIC-IV predictions using Youden's index and was transferred unchanged to eICU-CRD.

### External Evaluation and Performance Measures

No eICU observation was used for tuning, threshold selection, feature imputation, or model refitting. We reported AUROC, area under the precision-recall curve (AUPRC), Brier score, log loss, calibration-in-the-large, calibration slope, expected calibration error across 10 quantile groups, sensitivity, specificity, positive predictive value, and negative predictive value [15,16]. Ninety-five percent confidence intervals were estimated from 500 bootstrap samples; external resampling was clustered by patient. The difference in AUROC between the clinical and enhanced models used 1,000 paired bootstrap samples.

Decision-curve analysis compared model-guided intervention with treat-all and treat-none strategies across threshold probabilities of 0.01-0.50 [17]. Because external calibration and the simplified score were not adequate for implementation, decision curves were considered supportive rather than evidence for deployment.

### Explainability Analysis

SHapley Additive exPlanations (SHAP) were calculated for the enhanced XGBoost model [18]. Global importance was summarized by mean absolute SHAP value in a sample of up to 2,000 MIMIC-IV observations. Overall model importance and the importance of the eight incremental variables were reported separately. SHAP values were interpreted as model attribution, not as causal effects.

### Assessment-Selection Mechanism

Requiring documented baseline and follow-up CAM-ICU assessments may induce selection bias. We therefore modeled entry into the strict cohort among all otherwise eligible older first ICU stays longer than 24 hours. Patient-feature-only logistic models were fitted in both databases. In eICU-CRD, we additionally fitted a hospital-identity-only model and a combined patient-feature plus hospital-identity model. Five-fold cross-validation was grouped by patient, not held out by hospital, because this analysis was designed to quantify known hospitals' assessment policies rather than predict behavior in unseen hospitals.

Permutation importance measured the decrease in cross-validated AUROC after shuffling hospital identity or individual patient features. Stabilized inverse-probability-of-selection weights were truncated at the first and 99th percentiles. Effective sample size was calculated to assess positivity and weight stability. Weighted model performance was treated as a sensitivity analysis rather than a corrected primary estimate when effective sample size was severely reduced [19].

### Hospital-Level Transportability

External discrimination and calibration were summarized by eICU hospital. Hospitals with both outcome classes contributed point estimates. Bootstrap AUROC confidence intervals required at least five events and 20 non-events. Within-hospital calibration estimates required at least 10 events and 10 non-events. These thresholds were set to avoid presenting numerically unstable site estimates.

### Exploratory Trajectory Analysis

As a secondary analysis, MIMIC-IV daily delirium status during ICU days 2-5 was analyzed with latent class mixed models using a threshold link, quadratic time, and a random intercept. One- through four-class solutions were attempted with 30 random starts. Model choice considered convergence, Bayesian information criterion, minimum class size of 5%, posterior classification, and entropy. Reporting followed the Guidelines for Reporting on Latent Trajectory Studies (GRoLTS) [20]. The frozen MIMIC-IV trajectory model was applied to eICU-CRD without independent reclustering, but trajectory results were designated exploratory when classification quality was weak.

### Sensitivity Analyses

Sensitivity analyses removed first-24-hour antipsychotic exposure, added missingness indicators, expanded to less transportable variables with indicators, applied inverse-probability weighting, and treated unobserved post-baseline assessments as negative in a broad eICU cohort. Two post-hoc coding-harmonization analyses separately removed psychiatric disorder and ICU type, repeated the full patient-grouped nested validation procedure, and compared external AUROC with the primary enhanced model using 1,000 patient-clustered bootstrap samples. A simplified bedside score was evaluated but prespecified as non-deployable if external discrimination or calibration deteriorated materially.

### Software, Reporting, and Ethics

Data were processed in PostgreSQL {{POSTGRES_VERSION}}. Prediction analyses used Python {{PYTHON_VERSION}}, pandas {{PANDAS_VERSION}}, scikit-learn {{SKLEARN_VERSION}}, XGBoost {{XGBOOST_VERSION}}, and SHAP {{SHAP_VERSION}}. Trajectory models used R {{R_VERSION}} and lcmm {{LCMM_VERSION}}. A fixed random seed (20260726) was used. Reporting was structured according to TRIPOD+AI, with PROBAST+AI domains considered during design and interpretation [21,22].

Ethical approval was not required because this retrospective study used deidentified research databases available to credentialed users. MIMIC-IV and eICU-CRD were accessed and analyzed through PhysioNet after completion of the required training and under their respective data-use agreements. No identifiable data were accessed.

### Protocol Amendments

The final primary analysis used the same rule-based late or persistent delirium endpoint in MIMIC-IV and eICU-CRD. An earlier implementation compared a MIMIC latent-trajectory label with the rule-based eICU endpoint; those results were archived and are not reported as primary findings. Assessment-selection decomposition, temperature source validation, race-category correction, and invalid-sentinel handling were completed as post-hoc data-quality analyses before manuscript drafting. Coding-harmonization omission analyses were subsequently added during manuscript review and were retained as post-hoc sensitivity analyses rather than used to redefine the primary model. All primary results were regenerated after the data-quality corrections.

## Results

### Cohort Formation and Characteristics

Among 28,611 candidate MIMIC-IV stays, {{MIMIC_BASELINE_INELIGIBLE}} were baseline positive or otherwise ineligible for the strict incident cohort, {{MIMIC_NO_NEGATIVE}} had no documented negative baseline assessment, and {{MIMIC_INSUFFICIENT}} of the strictly baseline-eligible stays had fewer than two observed outcome days. The final MIMIC-IV cohort included {{MIMIC_N}} stays. Among 57,637 eICU candidates, {{EICU_BASELINE_INELIGIBLE}} were baseline positive or otherwise ineligible, {{EICU_NO_NEGATIVE}} had no documented negative baseline assessment, and {{EICU_INSUFFICIENT}} had insufficient observed outcome days, leaving {{EICU_N}} stays from {{STRICT_HOSPITALS}} hospitals (Figure 1).

Late or persistent delirium occurred in {{MIMIC_EVENTS}} MIMIC-IV stays ({{MIMIC_RATE}}%) and {{EICU_EVENTS}} eICU stays ({{EICU_RATE}}%). Median age was {{MIMIC_AGE}} years in MIMIC-IV and {{EICU_AGE}} years in eICU-CRD. The cohorts differed in ICU case mix, comorbidity coding, selected treatment exposures, and several physiologic distributions (Table 1). After correction of the eICU urine sentinel, external urine-output missingness was {{EICU_URINE_MISSING}}%; this variable was therefore excluded by the prespecified 40% threshold. The final clinical and enhanced models contained {{CLINICAL_FEATURE_COUNT}} and {{ENHANCED_FEATURE_COUNT}} raw features, respectively.

[[FIGURE1]]

[[TABLE1]]

### Primary Model Performance

The clinical baseline model achieved a MIMIC-IV out-of-fold AUROC of {{CLIN_INT_AUROC_CI}}, AUPRC of {{CLIN_INT_AUPRC_CI}}, and Brier score of {{CLIN_INT_BRIER_CI}}. In external evaluation, its AUROC was {{CLIN_EXT_AUROC_CI}}, AUPRC {{CLIN_EXT_AUPRC_CI}}, and Brier score {{CLIN_EXT_BRIER_CI}}.

Adding the eight nursing assessment and treatment variables increased MIMIC-IV AUROC to {{ENH_INT_AUROC_CI}} and external AUROC to {{ENH_EXT_AUROC_CI}}. The paired difference was {{DELTA_MIMIC_FULL}} internally and {{DELTA_EICU_FULL}} externally. External AUPRC was {{ENH_EXT_AUPRC_CI}}, compared with an event prevalence of {{EICU_RATE}}%. At the MIMIC-derived threshold of {{ENH_THRESHOLD}}, external sensitivity was {{ENH_EXT_SENSITIVITY}}, specificity {{ENH_EXT_SPECIFICITY}}, positive predictive value {{ENH_EXT_PPV}}, and negative predictive value {{ENH_EXT_NPV}}.

Calibration was near acceptable internally but deteriorated externally. For the enhanced model, the external calibration intercept was {{ENH_EXT_CAL_INTERCEPT}} and slope {{ENH_EXT_CAL_SLOPE}}, with an expected calibration error of {{ENH_EXT_ECE}}. The negative intercept indicated systematic overprediction in eICU-CRD, and a slope below 1 indicated predictions that were too extreme. Full performance estimates are shown in Table 2.

[[TABLE2]]

### Explainability and Incremental Variables

The leading overall SHAP attributions for the enhanced model were {{TOP_SHAP_FEATURES}} (Figure 2). These were overall model drivers and should not all be interpreted as newly added nursing information.

Among the eight incremental variables, minimum GCS had the largest mean absolute SHAP value ({{GCS_SHAP}}), followed by minimum RASS ({{RASS_MIN_SHAP}}) and maximum RASS ({{RASS_MAX_SHAP}}). Sedative exposure contributed less ({{SEDATIVE_SHAP}}), and opioid, antipsychotic, transfusion, and benzodiazepine exposures had smaller global attributions. This pattern indicates that the observed incremental discrimination was driven mainly by early consciousness and sedation assessments rather than by medication flags alone.

[[FIGURE2]]

### Assessment Selection and Positivity

The strict cohort represented {{MIMIC_SELECTION_RATE}}% of MIMIC-IV candidates and only {{EICU_SELECTION_RATE}}% of eICU candidates. In eICU-CRD, a patient-feature-only selection model achieved AUROC {{EICU_PATIENT_ONLY_AUC}}, whereas hospital identity alone achieved {{EICU_HOSPITAL_ONLY_AUC}} and the combined model achieved {{EICU_COMBINED_SELECTION_AUC}} (Table 3). Permuting hospital identity reduced AUROC by a mean of {{HOSPITAL_PERMUTATION_DROP}}; no individual patient feature reduced AUROC by more than {{MAX_PATIENT_PERMUTATION_DROP}} (Figure 3).

The effective sample size after inverse-probability weighting was {{MIMIC_IPW_ESS}} for MIMIC-IV but only {{EICU_IPW_ESS}} for eICU-CRD. The IPW external AUROC was {{EICU_IPW_AUC}}, but the severe reduction from {{EICU_N}} observed stays to an effective sample of approximately {{EICU_IPW_ESS_ROUNDED}} indicated poor positivity. The weighted result was therefore not interpreted as a recovered population-level validation estimate.

[[TABLE3]]

[[FIGURE3]]

### Hospital-Level Heterogeneity

Of {{CANDIDATE_HOSPITALS}} eICU hospitals represented in the candidate cohort, {{STRICT_HOSPITALS}} contributed at least one strict-cohort patient and {{BOTH_CLASS_HOSPITALS}} had both outcome classes. Only {{FOREST_HOSPITALS}} hospitals met the event and non-event threshold for bootstrap AUROC confidence intervals; these hospitals covered {{FOREST_PATIENT_SHARE}}% of strict-cohort patients and {{FOREST_EVENT_SHARE}}% of events (Figure 4). Within-hospital calibration could be estimated in only {{CALIBRATION_HOSPITALS}} hospitals. Thus, site-specific discrimination was evaluable for most patients but only a minority of candidate hospitals, and site-specific calibration evidence was narrower still.

[[FIGURE4]]

### Sensitivity and Exploratory Analyses

Removing antipsychotic exposure yielded an external AUROC of {{NO_ANTIPSYCHOTIC_AUC_CI}} and AUPRC of {{NO_ANTIPSYCHOTIC_AUPRC_CI}}, closely matching the primary enhanced model. Adding missingness indicators produced external AUROC {{MISSING_INDICATOR_AUC_CI}}; expanding to the full indicator model produced {{FULL_INDICATOR_AUC_CI}}. These findings did not support using documentation missingness as a primary predictive signal.

Psychiatric disorder was recorded in {{PSYCHIATRIC_MIMIC_RATE}}% of MIMIC-IV stays and {{PSYCHIATRIC_EICU_RATE}}% of eICU stays (standardized mean difference {{PSYCHIATRIC_SMD}}). Omitting it yielded external AUROC {{NO_PSYCHIATRIC_AUC_CI}}, a paired change of {{NO_PSYCHIATRIC_DELTA_FULL}} relative to the primary enhanced model. The external Brier score was {{NO_PSYCHIATRIC_BRIER}}, calibration intercept {{NO_PSYCHIATRIC_CAL_INTERCEPT}}, and calibration slope {{NO_PSYCHIATRIC_CAL_SLOPE}}. The mixed-or-other ICU category comprised {{MIMIC_MIXED_ICU}} MIMIC-IV stays and {{EICU_MIXED_ICU}} eICU stays. Omitting ICU type yielded external AUROC {{NO_ICU_TYPE_AUC_CI}}, a paired change of {{NO_ICU_TYPE_DELTA_FULL}}, Brier score {{NO_ICU_TYPE_BRIER}}, calibration intercept {{NO_ICU_TYPE_CAL_INTERCEPT}}, and calibration slope {{NO_ICU_TYPE_CAL_SLOPE}}. These post-hoc analyses indicated modest coding-harmonization sensitivity but did not replace the prespecified primary model (Supplementary Table S2).

When unobserved follow-up was treated as absence of delirium, the broad eICU cohort contained 56,394 stays but had an event rate of only 0.84%. AUROC was {{BROAD_AUC}}, while AUPRC fell to {{BROAD_AUPRC}} and the calibration intercept to {{BROAD_CAL_INTERCEPT}}. This analysis demonstrated how treating unmeasured outcomes as negatives changes the estimand and creates substantial outcome misclassification [23].

The simplified bedside score had external AUROC {{BEDSIDE_AUC}}, Brier score {{BEDSIDE_BRIER}}, and calibration slope {{BEDSIDE_SLOPE}}. It was therefore retained only as a negative translational experiment and not proposed for clinical use.

The two-class trajectory solution had the lowest BIC among converged solutions meeting minimum class-size criteria, but entropy was only {{TRAJECTORY_ENTROPY}}. The higher-risk class contained {{TRAJECTORY_HIGH_N}} MIMIC-IV stays ({{TRAJECTORY_HIGH_RATE}}%), while the four-class model did not converge. Frozen external trajectory discrimination was {{TRAJECTORY_EXT_AUC}}. These findings did not support stable three- or four-trajectory phenotypes and were treated as exploratory (Supplementary Figure S1).

## Discussion

### Principal Findings

This study produced four main findings. First, a harmonized first-24-hour model for operationally defined late or persistent delirium showed moderate internal discrimination and more limited, though non-random, external transportability. Second, adding three consciousness or sedation assessments and five treatment exposures improved discrimination in both databases, with a larger paired AUROC gain in eICU-CRD. Third, external calibration remained inadequate for bedside deployment. Fourth, and most importantly, entry into the eICU strict assessment cohort was determined predominantly by hospital identity: hospital alone predicted inclusion with AUROC {{EICU_HOSPITAL_ONLY_AUC}}, and shuffling hospital identity decreased AUROC by {{HOSPITAL_PERMUTATION_DROP}}. The external validation cohort therefore represents hospitals with compatible delirium assessment practices, not the full eICU population.

### Relation to Existing Prediction Models

PRE-DELIRIC and E-PRE-DELIRIC established that delirium risk can be estimated from early ICU information [7,8]. More recent machine-learning models have reported higher AUROCs, including models using detailed time-series data and broader delirium endpoints [10]. Direct numerical comparison is inappropriate because our cohort was restricted to older adults who were documented negative during the first 24 hours, our endpoint emphasized late or persistent patterns during days 2-5, and our external model was transferred across databases without recalibration. These choices make the task harder but align the prediction with an actionable landmark.

Our results are consistent with broader evidence that externally validated ICU artificial intelligence models often lose performance outside their development setting [11]. The external AUROC of {{ENH_EXT_AUROC_POINT}} should therefore not be reframed as a high-performing deployable tool. The more informative result is the decomposition of why apparent transportability is limited: case-mix differences, feature-definition differences, calibration drift, and especially institution-specific outcome observation.

### Value of Nursing Assessments and Treatment Exposures

The enhanced model improved AUROC by {{DELTA_MIMIC}} internally and {{DELTA_EICU}} externally. The strongest incremental attributions were minimum GCS and the RASS extrema, whereas medication and transfusion flags contributed less. This is clinically coherent. Consciousness and sedation assessments summarize neurologic vulnerability and treatment intensity that may not be captured by standard vital signs or laboratory values. However, these variables are not exclusively "nursing" constructs, and medication exposure is a multidisciplinary treatment decision. The label "nursing-assessment and treatment-enhanced" is therefore more accurate than "nursing-enhanced."

The result supports structured, timely bedside assessment as useful predictive information, but it does not establish that changing any attributed variable would change delirium risk. Antipsychotic exposure is particularly susceptible to reverse interpretation because it may be an early response to behavioral symptoms. Its removal did not materially reduce external performance, which reduces concern that the primary result depended on this potentially treatment-responsive marker.

### Coding Harmonization and Predictor Transportability

Two high-ranking overall predictors also showed marked cross-database category differences. Psychiatric disorder had the largest standardized mean difference among primary binary features ({{PSYCHIATRIC_SMD}}), with prevalence of {{PSYCHIATRIC_MIMIC_RATE}}% in MIMIC-IV and {{PSYCHIATRIC_EICU_RATE}}% in eICU-CRD. Mixed-or-other ICU type accounted for {{MIMIC_MIXED_ICU}} MIMIC-IV stays but {{EICU_MIXED_ICU}} eICU stays, consistent with different unit-label granularity. Because psychiatric disorder and cardiac ICU type were among the leading overall SHAP features, these discrepancies represented plausible sources of predictor-effect mismatch.

The omission analyses supported this interpretation without showing that either variable alone explained the transportability gap. Removing psychiatric disorder reduced internal AUROC from 0.730 to 0.720 but increased external AUROC by 0.005; the paired confidence interval excluded zero, although the external Brier score worsened slightly. Removing ICU type reduced internal AUROC to 0.718 and increased external AUROC by 0.007, but its paired confidence interval included zero; external calibration and Brier score improved modestly. Thus, internally useful coding signals did not transfer perfectly, but no single omission resolved external calibration. The prespecified model was retained, and these post-hoc results are evidence for harmonization fragility rather than a basis for model selection.

### Assessment Practice as a Transportability Mechanism

The assessment-selection analysis is the study's central methodological contribution. Only {{EICU_SELECTION_RATE}}% of eligible eICU candidates had the baseline-negative and longitudinal CAM-ICU pattern required for reliable labeling. Patient features predicted selection moderately, but hospital identity predicted it extremely well. This result is consistent with implementation studies showing that delirium assessment frequency depends on training, workflow integration, and local barriers [24,25]. In one structured implementation, CAM-ICU assessment increased from 38% to 95% per nursing shift after training and workflow changes [24].

The combined selection model used patient-grouped cross-validation intentionally. A leave-one-hospital-out design would answer whether assessment behavior can be predicted in a new hospital; our question was whether known hospital policy explained who entered the observed cohort. The very high AUROC and large hospital permutation effect quantify institutional measurement policy, not biological risk.

The IPW sensitivity result should also be interpreted cautiously. A nominal improvement in weighted external AUROC does not overcome an effective sample size of only {{EICU_IPW_ESS_ROUNDED}}. The weight instability indicates limited overlap: some hospitals or patient strata had near-zero probability of meeting the strict assessment definition. Under this positivity problem, statistical weighting cannot create outcome information that was never recorded.

### Calibration, Clinical Usefulness, and Site Heterogeneity

External calibration was more concerning than discrimination. A calibration intercept of {{ENH_EXT_CAL_INTERCEPT}} indicates systematic overprediction, while a slope of {{ENH_EXT_CAL_SLOPE}} indicates overfitting or predictor-effect mismatch in the external setting. A model may rank patients moderately well but still produce risk estimates unsuitable for treatment thresholds. Recalibration at a target hospital might improve numerical calibration, but it would require a sufficiently complete local assessment program and prospective evaluation.

Hospital-level analyses further narrowed the scope of inference. The AUROC forest plot covered {{FOREST_HOSPITALS}} hospitals and most strict-cohort patients and events, but calibration was estimable in only {{CALIBRATION_HOSPITALS}} of {{CANDIDATE_HOSPITALS}} candidate hospitals. Reporting a single pooled eICU estimate without these denominators would overstate the breadth of validation. Future multicenter delirium studies should measure assessment coverage as a site-level implementation variable and prospectively define minimum surveillance standards.

The simplified bedside score lost too much external performance and calibration to support deployment. We therefore do not present it as a clinical tool. A more responsible translation pathway would include local outcome-audit infrastructure, recalibration, prospective silent evaluation, and assessment of whether alerts improve delivery of preventive bundles without increasing burdensome monitoring or inappropriate medication use.

### Exploratory Trajectories

The data did not support the initially anticipated three or four clinically stable trajectory classes. Although a two-class model had the best BIC among acceptable fits, entropy was {{TRAJECTORY_ENTROPY}}, and the four-class solution failed to converge. Low entropy means that individual class assignments were uncertain. The trajectory result is therefore hypothesis-generating and should not serve as the primary prediction target or external-validation claim. This restraint is important because apparently distinct longitudinal patterns can be created by irregular observation, discharge, death, and changing assessment frequency.

### Strengths and Limitations

Strengths include a strict temporal landmark, an identical executable endpoint across databases, patient-grouped nested internal validation, external evaluation without refitting, paired assessment of incremental variables, SHAP analysis separated into overall and incremental contributions, and explicit quantification of assessment selection and hospital heterogeneity. Data-quality audits identified and corrected a race-category substring error, a negative urine-output sentinel, invalid GCS values, and temperature-source discrepancies before final result generation. The code and analysis manifests were retained for reproducibility.

Several limitations remain. First, delirium labels came from routine documentation rather than research-standard adjudication. Even in the strict cohort, CAM-ICU sensitivity depends on training, sedation state, and assessment frequency. Second, the strict design improves confidence in observed negatives but induces strong selection, especially in eICU-CRD. Third, the databases represent US practice from different periods and EHR systems. Psychiatric disorder prevalence differed from {{PSYCHIATRIC_MIMIC_RATE}}% to {{PSYCHIATRIC_EICU_RATE}}% (standardized mean difference {{PSYCHIATRIC_SMD}}), and mixed-or-other ICU labels differed from {{MIMIC_MIXED_ICU}} to {{EICU_MIXED_ICU}}; alcohol use and medication coding also were not identical. Post-hoc omission analyses quantified but could not eliminate this harmonization risk. Fourth, median imputation and a 40% missingness threshold are pragmatic choices, not a substitute for standardized collection. Fifth, the operational late or persistent endpoint has face validity but is not a universally established clinical phenotype. Sixth, the hospital forest plot and calibration analysis covered only selected sites, and hospital identities in eICU are anonymized, limiting explanation by teaching status or local protocol. Seventh, this retrospective analysis did not test clinical impact, fairness across protected groups, alert fatigue, or changes in care.

## Conclusions

An interpretable first-24-hour model incorporating early GCS, RASS, and treatment exposures improved prediction of late or persistent delirium in older ICU patients across MIMIC-IV and eICU-CRD, but external calibration and hospital-level heterogeneity preclude bedside deployment. The dominant transportability constraint was not patient physiology alone: hospital identity almost completely determined whether sufficiently structured delirium assessments were available. Future delirium prediction research should treat outcome-surveillance practice as part of the target setting, report site-level assessment coverage, and validate models only where the outcome can be measured consistently.

## Declarations

### Ethics Approval

Ethical approval was not required because this retrospective study used deidentified research databases available to credentialed users. MIMIC-IV and eICU-CRD were accessed and analyzed through PhysioNet after completion of the required training and under their respective data-use agreements. No identifiable data were accessed.

### Consent for Publication

Not applicable.

### Data Availability

MIMIC-IV version 3.1 and eICU-CRD version 2.0 are available to credentialed users through PhysioNet after completion of required training and data-use agreements. The data cannot be redistributed by the authors.

### Code Availability

SQL extraction, quality-assurance queries, model-development scripts, and manuscript-generation code are available in the study repository. Before submission, insert the public repository URL and archived release DOI: [repository URL/DOI].

### Funding

This research received no specific grant from any funding agency in the public, commercial, or not-for-profit sectors.

### Competing Interests

[Insert competing-interest declarations for all authors.]

### Author Contributions

Conceptualization: Jingzhuo Ren. Methodology: Jingzhuo Ren and Qiannan Zhang. Data curation: Jingzhuo Ren. Formal analysis: Jingzhuo Ren. Visualization: Jingzhuo Ren. Validation: Qiannan Zhang, Lixin Liu, and Zhaoping Xue. Writing - original draft: Jingzhuo Ren. Writing - review and editing: Qiannan Zhang, Lixin Liu, and Zhaoping Xue. Supervision: Zhaoping Xue. All authors approved the final manuscript and agree to be accountable for all aspects of the work.

### Patient and Public Involvement

Patients and the public were not involved in the design, conduct, reporting, or dissemination planning of this secondary analysis of deidentified data.

## References

1. Salluh JIF, Wang H, Schneider EB, et al. Outcome of delirium in critically ill patients: systematic review and meta-analysis. BMJ. 2015;350:h2538. doi:10.1136/bmj.h2538.
2. Pisani MA, Kong SYJ, Kasl SV, Murphy TE, Araujo KLB, Van Ness PH. Days of delirium are associated with 1-year mortality in an older intensive care unit population. Am J Respir Crit Care Med. 2009;180:1092-1097. doi:10.1164/rccm.200904-0537OC.
3. Pandharipande PP, Girard TD, Jackson JC, et al. Long-term cognitive impairment after critical illness. N Engl J Med. 2013;369:1306-1316. doi:10.1056/NEJMoa1301372.
4. Ely EW, Margolin R, Francis J, et al. Evaluation of delirium in critically ill patients: validation of the Confusion Assessment Method for the Intensive Care Unit (CAM-ICU). Crit Care Med. 2001;29:1370-1379. doi:10.1097/00003246-200107000-00012.
5. Devlin JW, Skrobik Y, Gelinas C, et al. Clinical practice guidelines for the prevention and management of pain, agitation/sedation, delirium, immobility, and sleep disruption in adult patients in the ICU. Crit Care Med. 2018;46:e825-e873. doi:10.1097/CCM.0000000000003299.
6. Pun BT, Balas MC, Barnes-Daly MA, et al. Caring for critically ill patients with the ABCDEF bundle: results of the ICU Liberation Collaborative in over 15,000 adults. Crit Care Med. 2019;47:3-14. doi:10.1097/CCM.0000000000003482.
7. van den Boogaard M, Pickkers P, Slooter AJC, et al. Development and validation of PRE-DELIRIC delirium prediction model for intensive care patients: observational multicentre study. BMJ. 2012;344:e420. doi:10.1136/bmj.e420.
8. Wassenaar A, van den Boogaard M, van Achterberg T, et al. Multinational development and validation of an early prediction model for delirium in ICU patients. Intensive Care Med. 2015;41:1048-1056. doi:10.1007/s00134-015-3777-2.
9. Wassenaar A, Schoonhoven L, Devlin JW, et al. External validation of two models to predict delirium in critically ill adults using either the CAM-ICU or the ICDSC for delirium assessment. Crit Care Med. 2019;47:e827-e835. doi:10.1097/CCM.0000000000003911.
10. Gong KD, Lu R, Bergamaschi TS, et al. Predicting intensive care delirium with machine learning: model development and external validation. Anesthesiology. 2023;138:299-311. doi:10.1097/ALN.0000000000004478.
11. Rockenschaub P, Hilbert A, Kossen T, et al. External validation of AI-based scoring systems in the ICU: a systematic review and meta-analysis. BMC Med Inform Decis Mak. 2025;25:9. doi:10.1186/s12911-024-02830-7.
12. Johnson AEW, Bulgarelli L, Shen L, et al. MIMIC-IV, a freely accessible electronic health record dataset. Sci Data. 2023;10:1. doi:10.1038/s41597-022-01899-x.
13. Pollard TJ, Johnson AEW, Raffa JD, Celi LA, Mark RG, Badawi O. The eICU Collaborative Research Database, a freely available multi-center database for critical care research. Sci Data. 2018;5:180178. doi:10.1038/sdata.2018.178.
14. Chen T, Guestrin C. XGBoost: a scalable tree boosting system. In: Proceedings of the 22nd ACM SIGKDD International Conference on Knowledge Discovery and Data Mining. 2016:785-794. doi:10.1145/2939672.2939785.
15. Steyerberg EW, Vergouwe Y. Towards better clinical prediction models: seven steps for development and an ABCD for validation. Eur Heart J. 2014;35:1925-1931. doi:10.1093/eurheartj/ehu207.
16. Van Calster B, McLernon DJ, van Smeden M, Wynants L, Steyerberg EW. Calibration: the Achilles heel of predictive analytics. BMC Med. 2019;17:230. doi:10.1186/s12916-019-1466-7.
17. Vickers AJ, Elkin EB. Decision curve analysis: a novel method for evaluating prediction models. Med Decis Making. 2006;26:565-574. doi:10.1177/0272989X06295361.
18. Lundberg SM, Lee SI. A unified approach to interpreting model predictions. Adv Neural Inf Process Syst. 2017;30:4765-4774.
19. Seaman SR, White IR. Review of inverse probability weighting for dealing with missing data. Stat Methods Med Res. 2013;22:278-295. doi:10.1177/0962280210395740.
20. van de Schoot R, Sijbrandij M, Winter SD, Depaoli S, Vermunt JK. The GRoLTS-checklist: guidelines for reporting on latent trajectory studies. Struct Equ Modeling. 2017;24:451-467. doi:10.1080/10705511.2016.1247646.
21. Collins GS, Moons KGM, Dhiman P, et al. TRIPOD+AI statement: updated guidance for reporting clinical prediction models that use regression or machine learning methods. BMJ. 2024;385:e078378. doi:10.1136/bmj-2023-078378.
22. Moons KGM, Damen JAA, Kaul T, et al. PROBAST+AI: an updated quality, risk of bias, and applicability assessment tool for prediction models using regression or artificial intelligence methods. BMJ. 2025;388:e082505. doi:10.1136/bmj-2024-082505.
23. Saha A, Beach MC, Cooper LA, et al. Evaluating risk-prediction models using data from electronic health records. Ann Appl Stat. 2016;10:286-304. doi:10.1214/15-AOAS891.
24. Riekerk B, Pen EJ, Hofhuis JGM, Rommes JH, Schultz MJ, Spronk PE. Limitations and practicalities of CAM-ICU implementation, a delirium scoring system, in a Dutch intensive care unit. Intensive Crit Care Nurs. 2009;25:242-249. doi:10.1016/j.iccn.2009.04.001.
25. dos Santos FCM, Rego AS, Montenegro WS, et al. Delirium in the intensive care unit: identifying difficulties in applying the CAM-ICU. BMC Nurs. 2022;21:323. doi:10.1186/s12912-022-01103-w.

[[PAGE_BREAK]]

## Figure Legends

**Figure 1. Cohort formation.** The strict primary cohort required a documented negative CAM-ICU assessment during ICU hours 0-24 and at least two observed daily outcome assessments during ICU days 2-5.

**Figure 2. SHAP summary for the nursing-assessment and treatment-enhanced model.** Each point represents one observation and one transformed model feature. Horizontal position is the SHAP contribution to the predicted log odds; color indicates the feature value where applicable. Importance reflects model attribution, not causality.

**Figure 3. Mechanism of selection into the eICU strict assessment cohort.** Cross-validated selection models separate patient-feature and hospital-identity contributions. Patient-grouped validation was used to quantify known hospital policies; it was not intended to estimate performance in unseen hospitals.

**Figure 4. Hospital-level external AUROC for the enhanced model.** Hospitals are displayed when they contained at least five events and 20 non-events, permitting a 300-sample bootstrap confidence interval. The plot covers {{FOREST_HOSPITALS}} hospitals, {{FOREST_PATIENT_SHARE}}% of strict-cohort patients, and {{FOREST_EVENT_SHARE}}% of events.

[[PAGE_BREAK]]

## Supplementary Methods and Results

### Supplementary Data-Quality Audit

The eICU temperature pipeline combined periodic monitor values with nurse-charted values. Periodic monitor temperature alone covered 207 of 2,609 strict-cohort stays (7.93%), whereas nurse-charted Celsius or Fahrenheit values covered 2,607 stays (99.92%); the combined feature covered 2,608 stays (99.96%). Among 23,656 paired Celsius and Fahrenheit records, the median absolute conversion difference was 0.011 C and 99.97% differed by no more than 0.06 C.

In 6,886 nurse-periodic pairs from 204 overlapping stays matched within 15 minutes, the median time difference was 1 minute. Nurse minus periodic temperature bias was 0.003 C, mean absolute error 0.030 C, Pearson correlation 0.982, and 95% limits of agreement -0.327 to 0.332 C. The most common rounded value, 36.7 C, represented 8.64% of observations and 37.0 C represented 4.70%, arguing against default-value filling.

The final audit also corrected two cross-database validity issues. First, eICU race values labeled "Caucasian" were mapped to White, avoiding a substring match to Asian. Second, `apacheApsVar.urine=-1` was treated as missing because urine output cannot be negative and the official table semantics specify a nonnegative 24-hour sum when present. This correction increased eICU urine-output missingness above the primary 40% feature threshold. Twelve eICU GCS values below 3 and one sodium value below 100 mmol/L were also set to missing.

### Supplementary Table S1

Supplementary Table S1 reports feature-level missingness in both strict cohorts, selection into the primary models, continuous-feature means, and standardized mean differences.

[[TABLES1]]

### Supplementary Coding-Harmonization Sensitivity Analysis

Psychiatric disorder and ICU type were omitted in separate post-hoc models because both were prominent overall SHAP features and showed marked cross-database distribution differences. Each model repeated the primary nested patient-grouped tuning and validation workflow. External confidence intervals used 500 patient-clustered bootstrap samples; paired AUROC differences versus the primary enhanced model used 1,000 patient-clustered bootstrap samples. These analyses were diagnostic and did not alter the prespecified primary feature set.

### Supplementary Table S2

[[TABLES2]]

### Supplementary Figure S1

[[FIGURES1]]

**Supplementary Figure S1. Exploratory MIMIC-IV daily delirium trajectories.** The two-class model was selected by BIC among converged solutions meeting minimum class-size criteria, but entropy was {{TRAJECTORY_ENTROPY}}. Class membership should therefore be interpreted as uncertain and exploratory.

[[PAGE_BREAK]]

### Supplementary Figure S2

[[FIGURES2]]

**Supplementary Figure S2. Decision-curve analysis for the enhanced model.** Net benefit is shown across threshold probabilities of 0.01-0.50. External curves are descriptive because the model was not recalibrated and is not proposed for deployment.
