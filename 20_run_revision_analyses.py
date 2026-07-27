from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV, StratifiedGroupKFold
from sklearn.pipeline import Pipeline


def load_modeling_module(study_dir: Path):
    path = study_dir / "09_train_validate_models.py"
    spec = importlib.util.spec_from_file_location("delirium_models", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def fit_regularized_logistic(
    module,
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    features: list[str],
    result_dir: Path,
    model_name: str,
) -> tuple[np.ndarray, np.ndarray, pd.DataFrame]:
    x = mimic[features]
    y = mimic["late_persistent_delirium"].astype(int).to_numpy()
    groups = mimic["subject_id"].to_numpy()
    external_x = eicu[features]
    external_y = eicu["late_persistent_delirium"].astype(int).to_numpy()
    pipeline = Pipeline([
        (
            "preprocess",
            module.make_preprocessor(
                mimic,
                features,
                scale=True,
                add_indicator=False,
            ),
        ),
        (
            "model",
            LogisticRegression(
                solver="liblinear",
                max_iter=2000,
                random_state=module.SEED,
            ),
        ),
    ])
    parameter_grid = {
        "model__C": np.logspace(-3, 2, 10).tolist(),
    }
    outer_cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=module.SEED,
    )
    oof = np.full(len(y), np.nan)
    tuning_rows = []
    for fold, (train_index, test_index) in enumerate(
        outer_cv.split(x, y, groups=groups),
        start=1,
    ):
        inner_cv = StratifiedGroupKFold(
            n_splits=3,
            shuffle=True,
            random_state=module.SEED + fold,
        )
        search = GridSearchCV(
            clone(pipeline),
            parameter_grid,
            scoring="roc_auc",
            cv=inner_cv,
            n_jobs=1,
            refit=True,
        )
        search.fit(
            x.iloc[train_index],
            y[train_index],
            groups=groups[train_index],
        )
        oof[test_index] = search.best_estimator_.predict_proba(
            x.iloc[test_index]
        )[:, 1]
        tuning_rows.append({
            "outer_fold": fold,
            "inner_best_auroc": search.best_score_,
            "best_C": search.best_params_["model__C"],
        })
    final_search = GridSearchCV(
        clone(pipeline),
        parameter_grid,
        scoring="roc_auc",
        cv=outer_cv,
        n_jobs=1,
        refit=True,
    )
    final_search.fit(x, y, groups=groups)
    model = final_search.best_estimator_
    external_probability = model.predict_proba(external_x)[:, 1]
    threshold = module.youden_threshold(y, oof)
    internal = module.metric_row(
        y,
        oof,
        threshold,
        f"MIMIC internal OOF - {model_name}",
    )
    internal.update(module.bootstrap_metrics(y, oof, threshold))
    external = module.metric_row(
        external_y,
        external_probability,
        threshold,
        f"eICU external - {model_name}",
    )
    external.update(module.bootstrap_metrics(
        external_y,
        external_probability,
        threshold,
        clusters=module.hospital_clusters(eicu),
    ))
    metrics = pd.DataFrame([internal, external])
    metrics.to_csv(
        result_dir / f"{model_name}_performance.csv",
        index=False,
    )
    pd.DataFrame(tuning_rows).to_csv(
        result_dir / f"{model_name}_nested_tuning.csv",
        index=False,
    )
    with open(
        result_dir / f"{model_name}_best_parameters.json",
        "w",
        encoding="utf-8",
    ) as handle:
        json.dump(final_search.best_params_, handle, indent=2)
    joblib.dump(model, result_dir / f"{model_name}.joblib")
    pd.concat([
        pd.DataFrame({
            "model": model_name,
            "dataset": "MIMIC internal OOF",
            "row_id": mimic["stay_id"].astype(str),
            "hospitalid": np.nan,
            "target": y,
            "predicted_probability": oof,
        }),
        pd.DataFrame({
            "model": model_name,
            "dataset": "eICU external",
            "row_id": eicu["patientunitstayid"].astype(str),
            "hospitalid": eicu["hospitalid"],
            "target": external_y,
            "predicted_probability": external_probability,
        }),
    ], ignore_index=True).to_csv(
        result_dir / f"{model_name}_predictions.csv",
        index=False,
    )
    return oof, external_probability, metrics


def subgroup_rows(
    module,
    frame: pd.DataFrame,
    probability: np.ndarray,
    dataset: str,
    threshold: float,
) -> pd.DataFrame:
    data = frame.copy()
    data["predicted_probability"] = probability
    data["age_group"] = pd.cut(
        data["age"],
        bins=[64, 74, 84, np.inf],
        labels=["65-74", "75-84", "85+"],
    )
    definitions = {
        "sex": data["sex"],
        "age_group": data["age_group"],
        "race": data["race"],
    }
    rows = []
    for variable, groups in definitions.items():
        for level in pd.Series(groups).dropna().unique():
            subset = data[groups == level]
            y = subset["late_persistent_delirium"].astype(int).to_numpy()
            p = subset["predicted_probability"].to_numpy()
            events = int(y.sum())
            non_events = int(len(y) - events)
            row = {
                "dataset": dataset,
                "subgroup_variable": variable,
                "subgroup": str(level),
                "n": len(y),
                "events": events,
                "non_events": non_events,
                "estimable": int(events >= 20 and non_events >= 20),
            }
            if row["estimable"]:
                metrics = module.metric_row(
                    y,
                    p,
                    threshold,
                    f"{dataset} - {variable}: {level}",
                )
                row.update({
                    key: metrics[key]
                    for key in [
                        "event_rate", "auroc", "auprc", "brier",
                        "calibration_intercept", "calibration_slope",
                        "sensitivity", "specificity",
                    ]
                })
                clusters = (
                    module.hospital_clusters(subset)
                    if dataset == "eICU external" else None
                )
                row.update(module.bootstrap_metrics(
                    y,
                    p,
                    threshold,
                    repetitions=500,
                    clusters=clusters,
                ))
            rows.append(row)
    return pd.DataFrame(rows)


def main() -> None:
    study_dir = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent
    )
    module = load_modeling_module(study_dir)
    result_dir = study_dir / "results" / "models"
    result_dir.mkdir(parents=True, exist_ok=True)
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
    for frame in (mimic, eicu):
        frame["strict_two_positive_days"] = (
            frame["delirium_positive_days"] >= 2
        ).astype(int)
        frame["any_post24_delirium"] = (
            frame["any_delirium_day2_5"] == 1
        ).astype(int)
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

    logistic_frames = []
    logistic_predictions = {}
    for features, name in [
        (clinical, "clinical_logistic_harmonized"),
        (enhanced, "nursing_enhanced_logistic_harmonized"),
    ]:
        internal_p, external_p, metrics = fit_regularized_logistic(
            module,
            mimic,
            eicu,
            features,
            result_dir,
            name,
        )
        logistic_frames.append(metrics)
        logistic_predictions[name] = (internal_p, external_p)
    pd.concat(logistic_frames, ignore_index=True).to_csv(
        result_dir / "regularized_logistic_benchmark_performance.csv",
        index=False,
    )

    endpoint_frames = []
    endpoint_counts = []
    for target, label in [
        ("strict_two_positive_days", "strict_two_positive_days"),
        ("any_post24_delirium", "any_post24_delirium"),
    ]:
        endpoint_counts.extend([
            {
                "endpoint": target,
                "dataset": "MIMIC",
                "n": len(mimic),
                "events": int(mimic[target].sum()),
                "event_rate": float(mimic[target].mean()),
            },
            {
                "endpoint": target,
                "dataset": "eICU",
                "n": len(eicu),
                "events": int(eicu[target].sum()),
                "event_rate": float(eicu[target].mean()),
            },
        ])
        for features, model_prefix in [
            (clinical, "clinical"),
            (enhanced, "nursing_enhanced"),
        ]:
            _, metrics, _, _ = module.fit_binary_model(
                mimic,
                eicu,
                features,
                result_dir,
                f"{model_prefix}_{label}_harmonized",
                mimic_target=target,
                external_target=target,
                add_indicator=False,
            )
            metrics.insert(0, "endpoint", target)
            endpoint_frames.append(metrics)
    pd.DataFrame(endpoint_counts).to_csv(
        result_dir / "alternative_endpoint_counts.csv",
        index=False,
    )
    pd.concat(endpoint_frames, ignore_index=True).to_csv(
        result_dir / "alternative_endpoint_performance.csv",
        index=False,
    )

    primary_prediction_path = (
        result_dir / "nursing_enhanced_harmonized_predictions.csv"
    )
    if not primary_prediction_path.exists():
        raise FileNotFoundError(
            "Primary enhanced predictions are required for subgroup analyses."
        )
    predictions = pd.read_csv(
        primary_prediction_path,
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
    threshold = module.youden_threshold(
        mimic["late_persistent_delirium"].astype(int).to_numpy(),
        mimic_probability,
    )
    pd.concat([
        subgroup_rows(
            module,
            mimic,
            mimic_probability,
            "MIMIC internal OOF",
            threshold,
        ),
        subgroup_rows(
            module,
            eicu,
            eicu_probability,
            "eICU external",
            threshold,
        ),
    ], ignore_index=True).to_csv(
        result_dir / "primary_model_subgroup_performance.csv",
        index=False,
    )


if __name__ == "__main__":
    main()
