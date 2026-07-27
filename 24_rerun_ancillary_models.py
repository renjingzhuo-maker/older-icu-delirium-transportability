from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import joblib
import pandas as pd


def load_module(study_dir: Path):
    path = study_dir / "09_train_validate_models.py"
    spec = importlib.util.spec_from_file_location("delirium_models", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main() -> None:
    study_dir = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent
    )
    module = load_module(study_dir)
    result_dir = study_dir / "results" / "models"
    mimic_all = module.normalize_columns(
        pd.read_csv(study_dir / "data" / "mimic_features_outcomes.csv"),
        "mimic",
    )
    eicu_all = module.normalize_columns(
        pd.read_csv(study_dir / "data" / "eicu_features_outcomes.csv"),
        "eicu",
    )
    mimic = mimic_all[
        (mimic_all["trajectory_strict_eligible"] == 1)
        & (mimic_all["valid_outcome_days"] >= 2)
    ].copy()
    eicu = eicu_all[
        (eicu_all["trajectory_strict_eligible"] == 1)
        & (eicu_all["valid_outcome_days"] >= 2)
    ].copy()
    clinical = module.available_features(
        mimic,
        eicu,
        module.CLINICAL_FEATURES,
        max_missing=0.40,
    )
    enhanced = module.available_features(
        mimic,
        eicu,
        module.CLINICAL_FEATURES + module.NURSING_FEATURES,
        max_missing=0.40,
    )
    enhanced_full = module.available_features(
        mimic,
        eicu,
        module.CLINICAL_FEATURES + module.NURSING_FEATURES,
        max_missing=None,
    )
    frames = []
    for features, model_name, indicators in [
        (
            enhanced,
            "nursing_with_missing_indicators",
            True,
        ),
        (
            enhanced_full,
            "nursing_full_with_missing_indicators_harmonized",
            True,
        ),
        (
            [x for x in enhanced if x != "antipsychotic_24h"],
            "nursing_without_antipsychotic_harmonized",
            False,
        ),
    ]:
        _, metrics, _, _ = module.fit_binary_model(
            mimic,
            eicu,
            features,
            result_dir,
            model_name,
            add_indicator=indicators,
        )
        frames.append(metrics)

    enhanced_model = joblib.load(
        result_dir / "nursing_enhanced_harmonized.joblib"
    )
    top_features = module.shap_outputs(
        enhanced_model,
        mimic,
        enhanced,
        result_dir,
        model_name="nursing_enhanced_harmonized",
    )
    bedside = module.fit_bedside_score(
        mimic,
        eicu,
        top_features,
        result_dir,
        model_name="bedside_score_harmonized",
    )
    primary = pd.read_csv(
        result_dir / "primary_harmonized_model_performance.csv"
    )
    pd.concat(
        [primary, *frames, bedside],
        ignore_index=True,
    ).to_csv(
        result_dir / "all_harmonized_model_performance.csv",
        index=False,
    )

    mimic_weights, mimic_selection = module.estimate_assessment_weights(
        mimic_all,
        mimic,
        clinical,
        "mimic",
        result_dir,
    )
    eicu_weights, eicu_selection = module.estimate_assessment_weights(
        eicu_all,
        eicu,
        clinical,
        "eicu",
        result_dir,
    )
    pd.DataFrame([mimic_selection, eicu_selection]).to_csv(
        result_dir / "assessment_selection_diagnostics.csv",
        index=False,
    )
    enhanced_predictions = pd.read_csv(
        result_dir / "nursing_enhanced_harmonized_predictions.csv",
        dtype={"row_id": "string"},
    )
    mimic_probability = (
        enhanced_predictions[
            enhanced_predictions["dataset"] == "MIMIC internal OOF"
        ]["predicted_probability"].to_numpy()
    )
    eicu_probability = (
        enhanced_predictions[
            enhanced_predictions["dataset"] == "eICU external"
        ]["predicted_probability"].to_numpy()
    )
    pd.DataFrame([
        module.weighted_metric_row(
            mimic["late_persistent_delirium"].to_numpy(),
            mimic_probability,
            mimic_weights,
            "MIMIC internal OOF - IPW assessment sensitivity",
        ),
        module.weighted_metric_row(
            eicu["late_persistent_delirium"].to_numpy(),
            eicu_probability,
            eicu_weights,
            "eICU external - IPW assessment sensitivity",
        ),
    ]).to_csv(
        result_dir / "assessment_ipw_performance.csv",
        index=False,
    )
    broad = eicu_all[
        eicu_all["trajectory_loose_eligible"] == 1
    ].copy()
    broad_probability = enhanced_model.predict_proba(
        broad[enhanced]
    )[:, 1]
    pd.DataFrame([
        module.metric_row(
            broad["late_persistent_delirium"].to_numpy(),
            broad_probability,
            0.5,
            "eICU broad sensitivity - insufficient assessment as negative",
        )
    ]).to_csv(
        result_dir / "broad_missing_as_negative_performance.csv",
        index=False,
    )


if __name__ == "__main__":
    main()
