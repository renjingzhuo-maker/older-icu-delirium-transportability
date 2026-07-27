from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

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
    profile = module.feature_profile(
        mimic,
        eicu,
        list(dict.fromkeys(module.CLINICAL_FEATURES + module.NURSING_FEATURES)),
        enhanced,
    )
    profile.to_csv(
        result_dir / "harmonized_feature_profile.csv",
        index=False,
    )
    pd.DataFrame({
        "feature": enhanced,
        "model_group": [
            "nursing" if feature in module.NURSING_FEATURES else "clinical"
            for feature in enhanced
        ],
    }).to_csv(
        result_dir / "harmonized_transportable_feature_manifest.csv",
        index=False,
    )

    _, clinical_metrics, clinical_oof, clinical_external = (
        module.fit_binary_model(
            mimic,
            eicu,
            clinical,
            result_dir,
            "clinical_baseline_harmonized",
            add_indicator=False,
        )
    )
    enhanced_model, enhanced_metrics, enhanced_oof, enhanced_external = (
        module.fit_binary_model(
            mimic,
            eicu,
            enhanced,
            result_dir,
            "nursing_enhanced_harmonized",
            add_indicator=False,
        )
    )
    module.shap_outputs(
        enhanced_model,
        mimic,
        enhanced,
        result_dir,
        model_name="nursing_enhanced_harmonized",
    )
    module.hospital_sensitivity(
        eicu,
        eicu_all,
        enhanced_external,
        result_dir,
        model_name="nursing_enhanced_harmonized",
    )
    pd.DataFrame([
        module.paired_auc_difference(
            mimic["late_persistent_delirium"].to_numpy(),
            clinical_oof,
            enhanced_oof,
            "MIMIC internal OOF",
        ),
        module.paired_auc_difference(
            eicu["late_persistent_delirium"].to_numpy(),
            clinical_external,
            enhanced_external,
            "eICU external",
            clusters=module.hospital_clusters(eicu),
        ),
    ]).to_csv(
        result_dir / "nursing_increment_paired_bootstrap.csv",
        index=False,
    )
    pd.concat(
        [clinical_metrics, enhanced_metrics],
        ignore_index=True,
    ).to_csv(
        result_dir / "primary_harmonized_model_performance.csv",
        index=False,
    )


if __name__ == "__main__":
    main()
