from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pandas as pd


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
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
    model = load(study_dir / "09_train_validate_models.py", "models")
    revision = load(study_dir / "20_run_revision_analyses.py", "revision")
    mimic = model.normalize_columns(
        pd.read_csv(study_dir / "data" / "mimic_features_outcomes.csv"),
        "mimic",
    )
    eicu = model.normalize_columns(
        pd.read_csv(study_dir / "data" / "eicu_features_outcomes.csv"),
        "eicu",
    )
    mimic = mimic[
        (mimic["trajectory_strict_eligible"] == 1)
        & (mimic["valid_outcome_days"] >= 2)
    ].copy()
    eicu = eicu[
        (eicu["trajectory_strict_eligible"] == 1)
        & (eicu["valid_outcome_days"] >= 2)
    ].copy()
    predictions = pd.read_csv(
        study_dir
        / "results"
        / "models"
        / "nursing_enhanced_harmonized_predictions.csv",
        dtype={"row_id": "string"},
    )
    mimic_probability = (
        predictions[predictions["dataset"] == "MIMIC internal OOF"]
        .set_index("row_id")
        .loc[mimic["stay_id"].astype(str), "predicted_probability"]
        .to_numpy()
    )
    eicu_probability = (
        predictions[predictions["dataset"] == "eICU external"]
        .set_index("row_id")
        .loc[
            eicu["patientunitstayid"].astype(str),
            "predicted_probability",
        ]
        .to_numpy()
    )
    threshold = model.youden_threshold(
        mimic["late_persistent_delirium"].astype(int).to_numpy(),
        mimic_probability,
    )
    pd.concat([
        revision.subgroup_rows(
            model,
            mimic,
            mimic_probability,
            "MIMIC internal OOF",
            threshold,
        ),
        revision.subgroup_rows(
            model,
            eicu,
            eicu_probability,
            "eICU external",
            threshold,
        ),
    ], ignore_index=True).to_csv(
        study_dir
        / "results"
        / "models"
        / "primary_model_subgroup_performance.csv",
        index=False,
    )


if __name__ == "__main__":
    main()
