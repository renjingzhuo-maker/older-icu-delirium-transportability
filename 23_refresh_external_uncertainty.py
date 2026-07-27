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
    model_dir = study_dir / "results" / "models"
    performance_path = model_dir / "all_harmonized_model_performance.csv"
    performance = pd.read_csv(performance_path)
    eicu = module.normalize_columns(
        pd.read_csv(study_dir / "data" / "eicu_features_outcomes.csv"),
        "eicu",
    )
    eicu = eicu[
        (eicu["trajectory_strict_eligible"] == 1)
        & (eicu["valid_outcome_days"] >= 2)
    ].copy()
    y = eicu["late_persistent_delirium"].astype(int).to_numpy()
    clusters = module.hospital_clusters(eicu)
    updated_rows = []
    for row in performance.to_dict(orient="records"):
        if not str(row["dataset"]).startswith("eICU external"):
            updated_rows.append(row)
            continue
        model_name = str(row["dataset"]).split(" - ", 1)[1]
        model_path = model_dir / f"{model_name}.joblib"
        if not model_path.exists():
            updated_rows.append(row)
            continue
        model = joblib.load(model_path)
        features = list(
            model.named_steps["preprocess"].feature_names_in_
        )
        probability = model.predict_proba(eicu[features])[:, 1]
        refreshed = module.metric_row(
            y,
            probability,
            float(row["threshold"]),
            str(row["dataset"]),
        )
        refreshed.update(module.bootstrap_metrics(
            y,
            probability,
            float(row["threshold"]),
            clusters=clusters,
        ))
        updated_rows.append(refreshed)
    updated = pd.DataFrame(updated_rows)
    primary_path = model_dir / "primary_harmonized_model_performance.csv"
    if primary_path.exists():
        primary = pd.read_csv(primary_path)
        primary_models = {
            "clinical_baseline_harmonized",
            "nursing_enhanced_harmonized",
        }
        keep = ~updated["dataset"].str.split(" - ").str[-1].isin(
            primary_models
        )
        updated = pd.concat(
            [updated.loc[keep], primary],
            ignore_index=True,
        )
    updated.to_csv(performance_path, index=False)


if __name__ == "__main__":
    main()
