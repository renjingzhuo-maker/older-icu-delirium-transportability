from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import joblib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import shap
from sklearn.base import clone
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    confusion_matrix,
    log_loss,
    roc_auc_score,
    roc_curve,
)
from sklearn.model_selection import (
    RandomizedSearchCV,
    StratifiedGroupKFold,
    cross_val_predict,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from xgboost import XGBClassifier

SEED = 20260726

ID_COLUMNS = {
    "subject_id", "hadm_id", "stay_id", "patientunitstayid",
    "patienthealthsystemstayid", "uniquepid", "hospitalid",
}

LEAKAGE_COLUMNS = {
    "icu_intime", "icu_outtime", "los_icu", "admittime", "dischtime",
    "los_hospital", "hospital_expire_flag", "unitdischargestatus",
    "baseline_delirium_24h", "baseline_cam_assessment_count",
    "post24_cam_assessment_count", "has_post24_delirium_assessment",
    "first_delirium_time", "delirium", "trajectory_strict_eligible",
    "trajectory_loose_eligible", "valid_outcome_days",
    "delirium_positive_days", "first_positive_day", "last_positive_day",
    "any_delirium_day2_5", "late_persistent_delirium",
    "valid_any_screen_days", "any_screen_delirium_day2_5",
    "trajectory_class", "high_risk_trajectory",
}

CATEGORICAL_FEATURES = [
    "sex", "race", "icu_type", "admission_type",
]

CLINICAL_FEATURES = [
    "age", "sex", "race", "icu_type", "admission_type", "bmi",
    "dementia", "cerebrovascular_disease", "hypertension", "diabetes",
    "chronic_kidney_disease", "chronic_pulmonary_disease",
    "congestive_heart_failure", "liver_disease", "cancer",
    "psychiatric_disorder", "alcohol_use_disorder",
    "heart_rate_min", "heart_rate_max", "sbp_min", "mbp_min",
    "resp_rate_max", "temperature_min", "temperature_max", "spo2_min",
    "wbc_max", "hemoglobin_min", "platelet_min",
    "sodium_min", "sodium_max", "potassium_min", "potassium_max",
    "bun_max", "creatinine_max", "albumin_min", "lactate_max",
    "glucose_lab_max", "urineoutput_24h", "mechvent_24h",
    "vasoactive_24h", "rrt_24h",
]

NURSING_FEATURES = [
    "gcs_min", "rass_min", "rass_max", "pain_mean",
    "sedative_24h", "benzodiazepine_24h", "opioid_24h",
    "antipsychotic_24h", "restraint_24h", "transfusion_24h",
]


def normalize_columns(df: pd.DataFrame, source: str) -> pd.DataFrame:
    df = df.copy()
    if source == "mimic":
        df = df.rename(columns={
            "blood_gas_bicarbonate_min": "bicarbonate_min",
            "blood_gas_bicarbonate_max": "bicarbonate_max",
        })
    if "sex" in df:
        sex = df["sex"].fillna("").astype(str).str.lower()
        df["sex"] = np.select(
            [sex.str.startswith("m"), sex.str.startswith("f")],
            ["Male", "Female"], default="Unknown",
        )
    if "race" in df:
        race = df["race"].fillna("").astype(str).str.lower()
        df["race"] = np.select(
            [
                race.str.contains(r"white|caucasian", regex=True),
                race.str.contains("black|african", regex=True),
                race.str.contains("hispanic|latino", regex=True),
                race.str.contains(r"\basian\b", regex=True),
            ],
            ["White", "Black", "Hispanic", "Asian"],
            default="Other_or_unknown",
        )
    if "icu_type" in df:
        icu = df["icu_type"].fillna("").astype(str).str.lower()
        df["icu_type"] = np.select(
            [
                icu.str.contains("cardiac|coronary|cicu|ccu", regex=True),
                icu.str.contains("neuro"),
                icu.str.contains("surgical|sicu|csru|ct|cardiothoracic", regex=True),
                icu.str.contains("medical|micu"),
            ],
            ["Cardiac", "Neurologic", "Surgical", "Medical"],
            default="Mixed_or_other",
        )
    if "admission_type" in df:
        admission = df["admission_type"].fillna("").astype(str).str.lower()
        df["admission_type"] = np.select(
            [
                admission.str.contains("emerg|urgent|ew ", regex=True),
                admission.str.contains("elective|operating room|or/pacu", regex=True),
                admission.str.contains("floor|ward|other hospital|transfer", regex=True),
            ],
            ["Emergency_or_urgent", "Elective_or_operating_room", "Transfer_or_ward"],
            default="Other_or_unknown",
        )
    if "urineoutput_24h" in df:
        urine = pd.to_numeric(df["urineoutput_24h"], errors="coerce")
        df["urineoutput_24h"] = urine.where(urine >= 0)
    for column in ("gcs_min", "gcs_max", "gcs_mean"):
        if column in df:
            gcs = pd.to_numeric(df[column], errors="coerce")
            df[column] = gcs.where(gcs.between(3, 15))
    for column in ("sodium_min", "sodium_max"):
        if column in df:
            sodium = pd.to_numeric(df[column], errors="coerce")
            df[column] = sodium.where(sodium.between(100, 200))
    return df


def available_features(
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    requested: list[str],
    max_missing: float | None = None,
) -> list[str]:
    features = [
        col for col in requested
        if col in mimic.columns and col in eicu.columns
        and col not in LEAKAGE_COLUMNS and col not in ID_COLUMNS
    ]
    for col in ("restraint_24h", "transfusion_24h"):
        if col not in features:
            continue
        mimic_rate = pd.to_numeric(mimic[col], errors="coerce").fillna(0).mean()
        eicu_rate = pd.to_numeric(eicu[col], errors="coerce").fillna(0).mean()
        if min(mimic_rate, eicu_rate) < 0.005 or max(mimic_rate, eicu_rate) > 0.995:
            features.remove(col)
    if max_missing is not None:
        features = [
            col for col in features
            if max(mimic[col].isna().mean(), eicu[col].isna().mean()) <= max_missing
        ]
    return features


def feature_profile(
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    requested: list[str],
    selected: list[str],
) -> pd.DataFrame:
    rows = []
    for col in requested:
        if col not in mimic or col not in eicu:
            continue
        row = {
            "feature": col,
            "mimic_missing": float(mimic[col].isna().mean()),
            "eicu_missing": float(eicu[col].isna().mean()),
            "selected_primary": int(col in selected),
        }
        if col not in CATEGORICAL_FEATURES:
            m = pd.to_numeric(mimic[col], errors="coerce")
            e = pd.to_numeric(eicu[col], errors="coerce")
            pooled_sd = np.sqrt((m.var(skipna=True) + e.var(skipna=True)) / 2)
            row.update({
                "mimic_mean": float(m.mean()),
                "eicu_mean": float(e.mean()),
                "standardized_mean_difference": (
                    float((m.mean() - e.mean()) / pooled_sd)
                    if pd.notna(pooled_sd) and pooled_sd > 0 else math.nan
                ),
            })
        rows.append(row)
    return pd.DataFrame(rows)


def make_preprocessor(
    df: pd.DataFrame,
    features: list[str],
    scale: bool = False,
    add_indicator: bool = True,
) -> ColumnTransformer:
    categorical = [c for c in features if c in CATEGORICAL_FEATURES]
    numeric = [c for c in features if c not in categorical]
    numeric_steps = [(
        "imputer",
        SimpleImputer(strategy="median", add_indicator=add_indicator),
    )]
    if scale:
        numeric_steps.append(("scaler", StandardScaler()))
    return ColumnTransformer(
        transformers=[
            ("numeric", Pipeline(numeric_steps), numeric),
            ("categorical", Pipeline([
                ("imputer", SimpleImputer(strategy="most_frequent")),
                ("onehot", OneHotEncoder(handle_unknown="ignore", sparse_output=True)),
            ]), categorical),
        ],
        remainder="drop",
        sparse_threshold=0.3,
        verbose_feature_names_out=False,
    )


def metric_row(y: np.ndarray, p: np.ndarray, threshold: float, label: str) -> dict:
    y = np.asarray(y, dtype=int)
    p = np.clip(np.asarray(p, dtype=float), 1e-6, 1 - 1e-6)
    pred = (p >= threshold).astype(int)
    tn, fp, fn, tp = confusion_matrix(y, pred, labels=[0, 1]).ravel()
    logit = np.log(p / (1 - p)).reshape(-1, 1)
    cal = LogisticRegression(C=1e12, solver="lbfgs", max_iter=1000)
    cal.fit(logit, y)
    bins = pd.qcut(p, q=min(10, len(np.unique(p))), duplicates="drop")
    cal_df = pd.DataFrame({"y": y, "p": p, "bin": bins})
    ece = (
        cal_df.groupby("bin", observed=True)
        .apply(lambda x: len(x) * abs(x.y.mean() - x.p.mean()), include_groups=False)
        .sum() / len(cal_df)
    )
    return {
        "dataset": label,
        "n": len(y),
        "events": int(y.sum()),
        "event_rate": float(y.mean()),
        "auroc": float(roc_auc_score(y, p)),
        "auprc": float(average_precision_score(y, p)),
        "brier": float(brier_score_loss(y, p)),
        "log_loss": float(log_loss(y, p)),
        "calibration_intercept": float(cal.intercept_[0]),
        "calibration_slope": float(cal.coef_[0, 0]),
        "ece_10": float(ece),
        "threshold": float(threshold),
        "sensitivity": float(tp / (tp + fn)) if tp + fn else math.nan,
        "specificity": float(tn / (tn + fp)) if tn + fp else math.nan,
        "ppv": float(tp / (tp + fp)) if tp + fp else math.nan,
        "npv": float(tn / (tn + fn)) if tn + fn else math.nan,
    }


def bootstrap_metrics(
    y: np.ndarray,
    p: np.ndarray,
    threshold: float,
    repetitions: int = 500,
    clusters: np.ndarray | None = None,
) -> dict:
    rng = np.random.default_rng(SEED)
    y = np.asarray(y)
    p = np.asarray(p)
    values: dict[str, list[float]] = {"auroc": [], "auprc": [], "brier": []}
    if clusters is not None:
        clusters = np.asarray(clusters)
        unique_clusters = np.unique(clusters)
    for _ in range(repetitions):
        if clusters is None:
            idx = rng.integers(0, len(y), len(y))
        else:
            sampled = rng.choice(unique_clusters, size=len(unique_clusters), replace=True)
            idx = np.concatenate([np.flatnonzero(clusters == cluster) for cluster in sampled])
        if np.unique(y[idx]).size < 2:
            continue
        values["auroc"].append(roc_auc_score(y[idx], p[idx]))
        values["auprc"].append(average_precision_score(y[idx], p[idx]))
        values["brier"].append(brier_score_loss(y[idx], p[idx]))
    result = {}
    for name, vals in values.items():
        result[f"{name}_ci_low"] = float(np.quantile(vals, 0.025))
        result[f"{name}_ci_high"] = float(np.quantile(vals, 0.975))
    return result


def paired_auc_difference(
    y: np.ndarray,
    reference_p: np.ndarray,
    enhanced_p: np.ndarray,
    label: str,
    repetitions: int = 1000,
    clusters: np.ndarray | None = None,
) -> dict:
    y = np.asarray(y)
    reference_p = np.asarray(reference_p)
    enhanced_p = np.asarray(enhanced_p)
    rng = np.random.default_rng(SEED)
    differences = []
    if clusters is not None:
        clusters = np.asarray(clusters)
        unique_clusters = np.unique(clusters)
    for _ in range(repetitions):
        if clusters is None:
            idx = rng.integers(0, len(y), len(y))
        else:
            sampled = rng.choice(
                unique_clusters, size=len(unique_clusters), replace=True
            )
            idx = np.concatenate([
                np.flatnonzero(clusters == cluster)
                for cluster in sampled
            ])
        if np.unique(y[idx]).size < 2:
            continue
        differences.append(
            roc_auc_score(y[idx], enhanced_p[idx])
            - roc_auc_score(y[idx], reference_p[idx])
        )
    return {
        "dataset": label,
        "reference_auroc": float(roc_auc_score(y, reference_p)),
        "enhanced_auroc": float(roc_auc_score(y, enhanced_p)),
        "auroc_difference": float(
            roc_auc_score(y, enhanced_p)
            - roc_auc_score(y, reference_p)
        ),
        "difference_ci_low": float(np.quantile(differences, 0.025)),
        "difference_ci_high": float(np.quantile(differences, 0.975)),
    }


def youden_threshold(y: np.ndarray, p: np.ndarray) -> float:
    fpr, tpr, thresholds = roc_curve(y, p)
    finite = np.isfinite(thresholds)
    idx = np.argmax((tpr - fpr)[finite])
    return float(thresholds[finite][idx])


def decision_curve(y: np.ndarray, p: np.ndarray, label: str) -> pd.DataFrame:
    y = np.asarray(y, dtype=int)
    rows = []
    n = len(y)
    prevalence = y.mean()
    for pt in np.arange(0.01, 0.51, 0.01):
        pred = p >= pt
        tp = np.sum(pred & (y == 1))
        fp = np.sum(pred & (y == 0))
        weight = pt / (1 - pt)
        rows.append({
            "dataset": label,
            "threshold_probability": pt,
            "model_net_benefit": tp / n - fp / n * weight,
            "treat_all_net_benefit": prevalence - (1 - prevalence) * weight,
            "treat_none_net_benefit": 0.0,
        })
    return pd.DataFrame(rows)


def fit_binary_model(
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    features: list[str],
    result_dir: Path,
    model_name: str,
    mimic_target: str = "late_persistent_delirium",
    external_target: str = "late_persistent_delirium",
    add_indicator: bool = False,
) -> tuple[Pipeline, pd.DataFrame, np.ndarray, np.ndarray]:
    x = mimic[features]
    y = mimic[mimic_target].astype(int).to_numpy()
    groups = mimic["subject_id"].to_numpy()
    x_external = eicu[features]
    y_external = eicu[external_target].astype(int).to_numpy()

    preprocessor = make_preprocessor(
        mimic, features, add_indicator=add_indicator
    )
    classifier = XGBClassifier(
        objective="binary:logistic",
        eval_metric="logloss",
        tree_method="hist",
        random_state=SEED,
        n_jobs=max(1, (joblib.cpu_count() or 2) - 1),
    )
    pipeline = Pipeline([("preprocess", preprocessor), ("model", classifier)])
    parameter_space = {
        "model__n_estimators": [200, 350, 500, 700],
        "model__max_depth": [2, 3, 4, 5],
        "model__learning_rate": [0.02, 0.04, 0.06, 0.1],
        "model__min_child_weight": [1, 3, 5, 10],
        "model__subsample": [0.7, 0.85, 1.0],
        "model__colsample_bytree": [0.6, 0.8, 1.0],
        "model__reg_lambda": [1.0, 3.0, 10.0],
        "model__reg_alpha": [0.0, 0.1, 0.5],
    }
    outer_cv = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=SEED)
    oof = np.full(len(y), np.nan)
    nested_tuning_rows = []
    for fold, (train_idx, test_idx) in enumerate(
        outer_cv.split(x, y, groups=groups), start=1
    ):
        inner_cv = StratifiedGroupKFold(
            n_splits=3, shuffle=True, random_state=SEED + fold
        )
        fold_search = RandomizedSearchCV(
            clone(pipeline),
            param_distributions=parameter_space,
            n_iter=8,
            scoring="roc_auc",
            cv=inner_cv,
            random_state=SEED + fold,
            n_jobs=1,
            verbose=0,
            refit=True,
        )
        fold_search.fit(
            x.iloc[train_idx], y[train_idx],
            groups=groups[train_idx],
        )
        oof[test_idx] = fold_search.best_estimator_.predict_proba(
            x.iloc[test_idx]
        )[:, 1]
        nested_tuning_rows.append({
            "outer_fold": fold,
            "inner_best_auroc": fold_search.best_score_,
            "best_parameters": json.dumps(fold_search.best_params_, sort_keys=True),
        })
    if np.isnan(oof).any():
        raise RuntimeError("Nested cross-validation did not predict every MIMIC row.")

    final_search = RandomizedSearchCV(
        clone(pipeline),
        param_distributions=parameter_space,
        n_iter=20,
        scoring="roc_auc",
        cv=outer_cv,
        random_state=SEED,
        n_jobs=1,
        verbose=1,
        refit=True,
    )
    final_search.fit(x, y, groups=groups)
    best = final_search.best_estimator_
    threshold = youden_threshold(y, oof)
    best.fit(x, y)
    external_p = best.predict_proba(x_external)[:, 1]

    internal_row = metric_row(y, oof, threshold, f"MIMIC internal OOF - {model_name}")
    internal_row.update(bootstrap_metrics(y, oof, threshold))
    external_row = metric_row(
        y_external, external_p, threshold, f"eICU external - {model_name}"
    )
    external_clusters = None
    if "uniquepid" in eicu:
        external_clusters = eicu["uniquepid"].fillna(
            eicu["patientunitstayid"].astype(str)
        ).to_numpy()
    external_row.update(bootstrap_metrics(
        y_external, external_p, threshold, clusters=external_clusters
    ))
    metrics = pd.DataFrame([internal_row, external_row])
    metrics.to_csv(result_dir / f"{model_name}_performance.csv", index=False)

    pd.DataFrame(nested_tuning_rows).to_csv(
        result_dir / f"{model_name}_nested_tuning.csv", index=False
    )
    pd.DataFrame(final_search.cv_results_).sort_values("rank_test_score").head(25).to_csv(
        result_dir / f"{model_name}_tuning.csv", index=False
    )
    with open(result_dir / f"{model_name}_best_parameters.json", "w", encoding="utf-8") as f:
        json.dump(final_search.best_params_, f, indent=2)
    joblib.dump(best, result_dir / f"{model_name}.joblib")

    dca = pd.concat([
        decision_curve(y, oof, f"MIMIC internal OOF - {model_name}"),
        decision_curve(y_external, external_p, f"eICU external - {model_name}"),
    ])
    dca.to_csv(result_dir / f"{model_name}_decision_curve.csv", index=False)
    return best, metrics, oof, external_p


def run_coding_harmonization_sensitivity(
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    nursing_features: list[str],
    result_dir: Path,
) -> None:
    primary_model_path = result_dir / "nursing_enhanced_harmonized.joblib"
    if not primary_model_path.exists():
        raise FileNotFoundError(
            "Primary enhanced model is required before coding sensitivity analyses."
        )
    primary_model = joblib.load(primary_model_path)
    primary_external_p = primary_model.predict_proba(
        eicu[nursing_features]
    )[:, 1]
    y_external = eicu["late_persistent_delirium"].astype(int).to_numpy()
    external_clusters = eicu["uniquepid"].fillna(
        eicu["patientunitstayid"].astype(str)
    ).to_numpy()

    variants = [
        (
            "psychiatric_disorder",
            "nursing_without_psychiatric_disorder_harmonized",
        ),
        ("icu_type", "nursing_without_icu_type_harmonized"),
    ]
    metric_frames = []
    paired_rows = []
    prediction_frames = []
    for omitted_feature, model_name in variants:
        sensitivity_features = [
            feature for feature in nursing_features
            if feature != omitted_feature
        ]
        _, metrics, internal_oof, external_p = fit_binary_model(
            mimic,
            eicu,
            sensitivity_features,
            result_dir,
            model_name,
            add_indicator=False,
        )
        metrics.insert(0, "omitted_feature", omitted_feature)
        metric_frames.append(metrics)
        paired = paired_auc_difference(
            y_external,
            primary_external_p,
            external_p,
            f"eICU external - omit {omitted_feature}",
            clusters=external_clusters,
        )
        paired["omitted_feature"] = omitted_feature
        paired_rows.append(paired)
        prediction_frames.extend([
            pd.DataFrame({
                "model": model_name,
                "dataset": "MIMIC internal OOF",
                "row_id": mimic["stay_id"].astype(str).to_numpy(),
                "target": mimic["late_persistent_delirium"].astype(int).to_numpy(),
                "predicted_probability": internal_oof,
            }),
            pd.DataFrame({
                "model": model_name,
                "dataset": "eICU external",
                "row_id": eicu["patientunitstayid"].astype(str).to_numpy(),
                "target": y_external,
                "predicted_probability": external_p,
            }),
        ])

    pd.concat(metric_frames, ignore_index=True).to_csv(
        result_dir / "coding_harmonization_sensitivity_performance.csv",
        index=False,
    )
    pd.DataFrame(paired_rows).to_csv(
        result_dir / "coding_harmonization_sensitivity_paired_bootstrap.csv",
        index=False,
    )
    pd.concat(prediction_frames, ignore_index=True).to_csv(
        result_dir / "coding_harmonization_sensitivity_predictions.csv",
        index=False,
    )


def shap_outputs(
    model: Pipeline,
    mimic: pd.DataFrame,
    features: list[str],
    result_dir: Path,
    model_name: str = "nursing_enhanced",
) -> list[str]:
    sample = mimic[features].sample(min(2000, len(mimic)), random_state=SEED)
    transformed = model.named_steps["preprocess"].transform(sample)
    feature_names = model.named_steps["preprocess"].get_feature_names_out()
    explainer = shap.TreeExplainer(model.named_steps["model"])
    values = explainer.shap_values(transformed)
    if hasattr(transformed, "toarray"):
        transformed_plot = transformed.toarray()
    else:
        transformed_plot = transformed
    mean_abs = np.abs(values).mean(axis=0)
    importance = pd.DataFrame({
        "feature": feature_names,
        "mean_abs_shap": mean_abs,
    }).sort_values("mean_abs_shap", ascending=False)
    importance.to_csv(
        result_dir / f"{model_name}_shap_importance.csv", index=False
    )
    shap.summary_plot(
        values, transformed_plot, feature_names=feature_names,
        max_display=20, show=False,
    )
    plt.tight_layout()
    plt.savefig(
        result_dir / f"{model_name}_shap_summary.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close()
    raw_top = []
    for name in importance["feature"]:
        for raw in features:
            if name == raw or name.startswith(raw + "_") or name.startswith(raw + "_missingindicator"):
                if raw not in raw_top:
                    raw_top.append(raw)
                break
        if len(raw_top) >= 12:
            break
    return raw_top


def fit_bedside_score(
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    top_features: list[str],
    result_dir: Path,
    model_name: str = "bedside_score",
) -> pd.DataFrame:
    numeric_binary = [
        c for c in top_features
        if c not in CATEGORICAL_FEATURES and c in mimic.columns and c in eicu.columns
    ][:10]
    x = mimic[numeric_binary]
    y = mimic["late_persistent_delirium"].astype(int).to_numpy()
    groups = mimic["subject_id"].to_numpy()
    score = Pipeline([
        ("preprocess", make_preprocessor(
            mimic, numeric_binary, scale=True, add_indicator=False
        )),
        ("model", LogisticRegression(
            l1_ratio=1.0, solver="liblinear", C=0.2,
            class_weight="balanced", random_state=SEED,
        )),
    ])
    cv = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=SEED)
    oof = cross_val_predict(
        score, x, y, groups=groups, cv=cv, method="predict_proba", n_jobs=1
    )[:, 1]
    threshold = youden_threshold(y, oof)
    score.fit(x, y)
    external_p = score.predict_proba(eicu[numeric_binary])[:, 1]
    y_external = eicu["late_persistent_delirium"].astype(int).to_numpy()
    metrics = pd.DataFrame([
        metric_row(y, oof, threshold, f"MIMIC internal OOF - {model_name}"),
        metric_row(y_external, external_p, threshold, f"eICU external - {model_name}"),
    ])
    metrics.to_csv(result_dir / f"{model_name}_performance.csv", index=False)
    joblib.dump(score, result_dir / f"{model_name}.joblib")

    imputer = score.named_steps["preprocess"].named_transformers_["numeric"].named_steps["imputer"]
    scaler = score.named_steps["preprocess"].named_transformers_["numeric"].named_steps["scaler"]
    coefficients = score.named_steps["model"].coef_[0][:len(numeric_binary)]
    nonzero = np.abs(coefficients[np.abs(coefficients) > 1e-8])
    point_unit = max(0.25, float(np.min(nonzero))) if len(nonzero) else 1.0
    table = pd.DataFrame({
        "feature": numeric_binary,
        "imputation_median": imputer.statistics_[:len(numeric_binary)],
        "standard_deviation": scaler.scale_[:len(numeric_binary)],
        "log_odds_per_1_sd": coefficients,
        "integer_points_per_1_sd": np.rint(coefficients / point_unit).astype(int),
    })
    table.to_csv(result_dir / f"{model_name}_table.csv", index=False)
    with open(
        result_dir / f"{model_name}_metadata.json", "w", encoding="utf-8"
    ) as f:
        json.dump({
            "intercept": float(score.named_steps["model"].intercept_[0]),
            "point_unit": point_unit,
            "mimic_probability_threshold": threshold,
            "features": numeric_binary,
        }, f, indent=2)
    return metrics


def weighted_metric_row(
    y: np.ndarray,
    p: np.ndarray,
    weights: np.ndarray,
    label: str,
) -> dict:
    y = np.asarray(y, dtype=int)
    p = np.clip(np.asarray(p, dtype=float), 1e-6, 1 - 1e-6)
    weights = np.asarray(weights, dtype=float)
    logit = np.log(p / (1 - p)).reshape(-1, 1)
    cal = LogisticRegression(C=1e12, solver="lbfgs", max_iter=1000)
    cal.fit(logit, y, sample_weight=weights)
    return {
        "dataset": label,
        "n": len(y),
        "events": int(y.sum()),
        "weighted_event_rate": float(np.average(y, weights=weights)),
        "effective_sample_size": float(
            weights.sum() ** 2 / np.square(weights).sum()
        ),
        "auroc": float(roc_auc_score(y, p, sample_weight=weights)),
        "auprc": float(
            average_precision_score(y, p, sample_weight=weights)
        ),
        "brier": float(
            brier_score_loss(y, p, sample_weight=weights)
        ),
        "log_loss": float(log_loss(y, p, sample_weight=weights)),
        "calibration_intercept": float(cal.intercept_[0]),
        "calibration_slope": float(cal.coef_[0, 0]),
    }


def estimate_assessment_weights(
    all_rows: pd.DataFrame,
    selected_rows: pd.DataFrame,
    features: list[str],
    source: str,
    result_dir: Path,
) -> tuple[np.ndarray, dict]:
    data = all_rows.copy()
    data["assessment_selected"] = (
        (data["trajectory_strict_eligible"] == 1)
        & (data["valid_outcome_days"] >= 2)
    ).astype(int)
    local_features = list(features)
    categorical = [c for c in local_features if c in CATEGORICAL_FEATURES]
    if source == "eicu":
        data["selection_site"] = (
            data["hospitalid"].fillna(-1).astype(int).astype(str)
        )
        local_features.append("selection_site")
        categorical.append("selection_site")
    numeric = [c for c in local_features if c not in categorical]
    preprocessor = ColumnTransformer(
        transformers=[
            ("numeric", Pipeline([
                ("imputer", SimpleImputer(
                    strategy="median", add_indicator=True
                )),
                ("scaler", StandardScaler()),
            ]), numeric),
            ("categorical", Pipeline([
                ("imputer", SimpleImputer(strategy="most_frequent")),
                ("onehot", OneHotEncoder(
                    handle_unknown="ignore", sparse_output=True
                )),
            ]), categorical),
        ],
        remainder="drop",
        sparse_threshold=0.3,
    )
    model = Pipeline([
        ("preprocess", preprocessor),
        ("model", LogisticRegression(
            C=1.0, solver="liblinear", max_iter=1000,
            random_state=SEED,
        )),
    ])
    target = data["assessment_selected"].to_numpy()
    if source == "mimic":
        groups = data["subject_id"].to_numpy()
        id_column = "stay_id"
    else:
        groups = data["uniquepid"].fillna(
            data["patientunitstayid"].astype(str)
        ).to_numpy()
        id_column = "patientunitstayid"
    cv = StratifiedGroupKFold(
        n_splits=5, shuffle=True, random_state=SEED
    )
    propensity = cross_val_predict(
        model,
        data[local_features],
        target,
        groups=groups,
        cv=cv,
        method="predict_proba",
        n_jobs=1,
    )[:, 1]
    propensity = np.clip(propensity, 1e-4, 1 - 1e-4)
    prevalence = target.mean()
    raw_weights = prevalence / propensity[target == 1]
    lower, upper = np.quantile(raw_weights, [0.01, 0.99])
    clipped_weights = np.clip(raw_weights, lower, upper)
    selected_ids = data.loc[target == 1, id_column].to_numpy()
    weight_map = pd.Series(clipped_weights, index=selected_ids)
    selected_weights = (
        selected_rows[id_column].map(weight_map).astype(float).to_numpy()
    )
    if np.isnan(selected_weights).any():
        raise RuntimeError(
            f"{source} assessment weights did not match all selected rows."
        )
    diagnostics = {
        "dataset": source,
        "candidate_n": len(data),
        "selected_n": int(target.sum()),
        "selection_rate": float(prevalence),
        "selection_model_auroc": float(roc_auc_score(target, propensity)),
        "propensity_selected_p01": float(
            np.quantile(propensity[target == 1], 0.01)
        ),
        "propensity_selected_median": float(
            np.median(propensity[target == 1])
        ),
        "propensity_selected_p99": float(
            np.quantile(propensity[target == 1], 0.99)
        ),
        "raw_weight_p99": float(np.quantile(raw_weights, 0.99)),
        "clipped_weight_max": float(clipped_weights.max()),
        "effective_sample_size": float(
            clipped_weights.sum() ** 2
            / np.square(clipped_weights).sum()
        ),
    }
    joblib.dump(
        model.fit(data[local_features], target),
        result_dir / f"{source}_assessment_selection_model.joblib",
    )
    return selected_weights, diagnostics


def hospital_sensitivity(
    eicu: pd.DataFrame,
    eicu_all: pd.DataFrame,
    probabilities: np.ndarray,
    result_dir: Path,
    model_name: str,
) -> None:
    temp = eicu[["hospitalid", "late_persistent_delirium"]].copy()
    temp["probability"] = probabilities
    candidate_counts = eicu_all.groupby("hospitalid").size().to_dict()
    rows = []
    hospitals = sorted(set(candidate_counts) | set(temp["hospitalid"].dropna()))
    for hospital in hospitals:
        group = temp[temp["hospitalid"] == hospital]
        y = group["late_persistent_delirium"].to_numpy(dtype=int)
        row = {
            "hospitalid": hospital,
            "candidate_n": int(candidate_counts.get(hospital, 0)),
            "n": len(y),
            "selection_rate": (
                len(y) / candidate_counts[hospital]
                if candidate_counts.get(hospital, 0) else math.nan
            ),
            "events": int(y.sum()) if len(y) else 0,
            "event_rate": float(y.mean()) if len(y) else math.nan,
            "mean_prediction": (
                float(group["probability"].mean()) if len(y) else math.nan
            ),
            "auroc": math.nan,
            "auprc": math.nan,
            "brier": math.nan,
            "auroc_ci_low": math.nan,
            "auroc_ci_high": math.nan,
            "calibration_intercept": math.nan,
            "calibration_slope": math.nan,
        }
        if len(y) and np.unique(y).size == 2:
            p = group["probability"].to_numpy()
            row["auroc"] = float(roc_auc_score(y, p))
            row["auprc"] = float(average_precision_score(y, p))
            row["brier"] = float(brier_score_loss(y, p))
            if y.sum() >= 5 and (len(y) - y.sum()) >= 20:
                ci = bootstrap_metrics(y, p, 0.5, repetitions=300)
                row["auroc_ci_low"] = ci["auroc_ci_low"]
                row["auroc_ci_high"] = ci["auroc_ci_high"]
            if y.sum() >= 10 and (len(y) - y.sum()) >= 10:
                calibration = metric_row(y, p, 0.5, "hospital")
                row["calibration_intercept"] = calibration["calibration_intercept"]
                row["calibration_slope"] = calibration["calibration_slope"]
        rows.append(row)
    output = pd.DataFrame(rows).sort_values(
        ["n", "candidate_n"], ascending=False
    )
    output.to_csv(
        result_dir / f"{model_name}_eicu_hospital_transportability.csv",
        index=False,
    )

    forest = output.dropna(subset=["auroc_ci_low", "auroc_ci_high"]).copy()
    if not forest.empty:
        forest = forest.sort_values("auroc")
        fig_height = max(4.5, 0.35 * len(forest) + 1.5)
        fig, ax = plt.subplots(figsize=(7, fig_height))
        positions = np.arange(len(forest))
        ax.errorbar(
            forest["auroc"], positions,
            xerr=[
                forest["auroc"] - forest["auroc_ci_low"],
                forest["auroc_ci_high"] - forest["auroc"],
            ],
            fmt="o", color="#176B87", ecolor="#7A8B99", capsize=3,
        )
        ax.axvline(0.5, color="#A33A3A", linestyle="--", linewidth=1)
        ax.set_yticks(positions)
        ax.set_yticklabels(
            [
                f"Hospital {int(row.hospitalid)} (n={int(row.n)})"
                for row in forest.itertuples()
            ]
        )
        ax.set_xlim(0, 1)
        ax.set_xlabel("AUROC with 95% bootstrap CI")
        ax.set_ylabel("")
        fig.tight_layout()
        fig.savefig(
            result_dir / f"{model_name}_eicu_hospital_auroc_forest.png",
            dpi=300,
            bbox_inches="tight",
        )
        plt.close(fig)


def fit_multiclass_trajectory_model(
    mimic: pd.DataFrame,
    eicu: pd.DataFrame,
    features: list[str],
    study_dir: Path,
    result_dir: Path,
) -> None:
    external_path = study_dir / "results" / "gbtm" / "eicu_frozen_trajectory_membership.csv"
    if not external_path.exists():
        return
    external_membership = pd.read_csv(external_path).rename(
        columns={"stay_id": "patientunitstayid"}
    )
    eicu_multi = eicu.merge(
        external_membership[["patientunitstayid", "trajectory_class"]],
        on="patientunitstayid", how="inner", validate="one_to_one",
        suffixes=("", "_frozen"),
    )
    if "trajectory_class_frozen" in eicu_multi:
        eicu_multi["trajectory_class"] = eicu_multi["trajectory_class_frozen"]

    classes = sorted(mimic["trajectory_class"].dropna().astype(int).unique())
    mapping = {value: index for index, value in enumerate(classes)}
    y = mimic["trajectory_class"].astype(int).map(mapping).to_numpy()
    y_external = eicu_multi["trajectory_class"].astype(int).map(mapping)
    keep = y_external.notna()
    eicu_multi = eicu_multi.loc[keep].copy()
    y_external = y_external.loc[keep].astype(int).to_numpy()
    if len(np.unique(y_external)) != len(classes):
        return

    preprocessor = make_preprocessor(mimic, features)
    model = Pipeline([
        ("preprocess", preprocessor),
        ("model", XGBClassifier(
            objective="multi:softprob",
            num_class=len(classes),
            n_estimators=450,
            max_depth=3,
            learning_rate=0.04,
            min_child_weight=3,
            subsample=0.85,
            colsample_bytree=0.8,
            reg_lambda=3.0,
            eval_metric="mlogloss",
            tree_method="hist",
            random_state=SEED,
            n_jobs=max(1, (joblib.cpu_count() or 2) - 1),
        )),
    ])
    cv = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=SEED)
    oof = cross_val_predict(
        model, mimic[features], y, groups=mimic["subject_id"],
        cv=cv, method="predict_proba", n_jobs=1,
    )
    model.fit(mimic[features], y)
    external_p = model.predict_proba(eicu_multi[features])

    def multi_metrics(target: np.ndarray, probability: np.ndarray, label: str) -> dict:
        onehot = np.eye(len(classes))[target]
        if len(classes) == 2:
            macro_auroc = weighted_auroc = float(
                roc_auc_score(target, probability[:, 1])
            )
        else:
            macro_auroc = float(roc_auc_score(
                target, probability, multi_class="ovr", average="macro"
            ))
            weighted_auroc = float(roc_auc_score(
                target, probability, multi_class="ovr", average="weighted"
            ))
        return {
            "dataset": label,
            "n": len(target),
            "class_count": len(classes),
            "macro_ovr_auroc": macro_auroc,
            "weighted_ovr_auroc": weighted_auroc,
            "multiclass_log_loss": float(log_loss(target, probability)),
            "multiclass_brier": float(np.mean(np.sum((probability - onehot) ** 2, axis=1))),
            "accuracy": float(np.mean(np.argmax(probability, axis=1) == target)),
        }

    pd.DataFrame([
        multi_metrics(y, oof, "MIMIC internal OOF"),
        multi_metrics(y_external, external_p, "eICU frozen-trajectory external"),
    ]).to_csv(result_dir / "multiclass_trajectory_performance.csv", index=False)
    joblib.dump(model, result_dir / "multiclass_trajectory_model.joblib")


def main(study_dir: Path, stage: str = "all") -> None:
    data_dir = study_dir / "data"
    result_dir = study_dir / "results" / "models"
    result_dir.mkdir(parents=True, exist_ok=True)

    mimic_all = normalize_columns(
        pd.read_csv(data_dir / "mimic_features_outcomes.csv"), "mimic"
    )
    eicu_all = normalize_columns(
        pd.read_csv(data_dir / "eicu_features_outcomes.csv"), "eicu"
    )
    mimic = mimic_all[
        (mimic_all["trajectory_strict_eligible"] == 1)
        & (mimic_all["valid_outcome_days"] >= 2)
    ].copy()
    eicu = eicu_all[
        (eicu_all["trajectory_strict_eligible"] == 1)
        & (eicu_all["valid_outcome_days"] >= 2)
    ].copy()

    for source, frame in (("MIMIC", mimic), ("eICU", eicu)):
        if frame["late_persistent_delirium"].nunique() != 2:
            raise RuntimeError(
                f"The strict {source} late/persistent target is not binary."
            )

    clinical = available_features(
        mimic, eicu, CLINICAL_FEATURES, max_missing=0.40
    )
    nursing = available_features(
        mimic, eicu, CLINICAL_FEATURES + NURSING_FEATURES,
        max_missing=0.40,
    )
    nursing_full = available_features(
        mimic, eicu, CLINICAL_FEATURES + NURSING_FEATURES,
        max_missing=None,
    )
    if stage == "coding-sensitivity-only":
        run_coding_harmonization_sensitivity(
            mimic, eicu, nursing, result_dir
        )
        return
    if set(nursing) & LEAKAGE_COLUMNS:
        raise RuntimeError("Leakage feature detected.")
    requested = list(dict.fromkeys(CLINICAL_FEATURES + NURSING_FEATURES))
    profile = feature_profile(mimic, eicu, requested, nursing)
    profile.to_csv(
        result_dir / "harmonized_feature_profile.csv", index=False
    )
    pd.DataFrame({
        "feature": nursing,
        "model_group": [
            "nursing" if x in NURSING_FEATURES else "clinical"
            for x in nursing
        ],
    }).to_csv(
        result_dir / "harmonized_transportable_feature_manifest.csv",
        index=False,
    )

    if stage != "multiclass-only":
        _, clinical_metrics, clinical_oof, clinical_external_p = fit_binary_model(
            mimic, eicu, clinical, result_dir,
            "clinical_baseline_harmonized",
            add_indicator=False,
        )
        enhanced_model, enhanced_metrics, enhanced_oof, external_p = (
            fit_binary_model(
                mimic, eicu, nursing, result_dir,
                "nursing_enhanced_harmonized",
                add_indicator=False,
            )
        )
        _, indicator_metrics, _, _ = fit_binary_model(
            mimic, eicu, nursing, result_dir,
            "nursing_with_missing_indicators",
            add_indicator=True,
        )
        _, full_indicator_metrics, _, _ = fit_binary_model(
            mimic, eicu, nursing_full, result_dir,
            "nursing_full_with_missing_indicators_harmonized",
            add_indicator=True,
        )
        no_antipsychotic = [
            c for c in nursing if c != "antipsychotic_24h"
        ]
        _, no_antipsychotic_metrics, _, _ = fit_binary_model(
            mimic, eicu, no_antipsychotic, result_dir,
            "nursing_without_antipsychotic_harmonized",
            add_indicator=False,
        )
        run_coding_harmonization_sensitivity(
            mimic, eicu, nursing, result_dir
        )
        top_features = shap_outputs(
            enhanced_model, mimic, nursing, result_dir,
            model_name="nursing_enhanced_harmonized",
        )
        bedside_metrics = fit_bedside_score(
            mimic, eicu, top_features, result_dir,
            model_name="bedside_score_harmonized",
        )
        hospital_sensitivity(
            eicu, eicu_all, external_p, result_dir,
            model_name="nursing_enhanced_harmonized",
        )
        paired_differences = pd.DataFrame([
            paired_auc_difference(
                mimic["late_persistent_delirium"].to_numpy(),
                clinical_oof,
                enhanced_oof,
                "MIMIC internal OOF",
            ),
            paired_auc_difference(
                eicu["late_persistent_delirium"].to_numpy(),
                clinical_external_p,
                external_p,
                "eICU external",
                clusters=eicu["uniquepid"].fillna(
                    eicu["patientunitstayid"].astype(str)
                ).to_numpy(),
            ),
        ])
        paired_differences.to_csv(
            result_dir / "nursing_increment_paired_bootstrap.csv",
            index=False,
        )

        mimic_weights, mimic_selection = estimate_assessment_weights(
            mimic_all, mimic, clinical, "mimic", result_dir
        )
        eicu_weights, eicu_selection = estimate_assessment_weights(
            eicu_all, eicu, clinical, "eicu", result_dir
        )
        pd.DataFrame([
            mimic_selection, eicu_selection
        ]).to_csv(
            result_dir / "assessment_selection_diagnostics.csv",
            index=False,
        )
        weighted_performance = pd.DataFrame([
            weighted_metric_row(
                mimic["late_persistent_delirium"].to_numpy(),
                enhanced_oof,
                mimic_weights,
                "MIMIC internal OOF - IPW assessment sensitivity",
            ),
            weighted_metric_row(
                eicu["late_persistent_delirium"].to_numpy(),
                external_p,
                eicu_weights,
                "eICU external - IPW assessment sensitivity",
            ),
        ])
        weighted_performance.to_csv(
            result_dir / "assessment_ipw_performance.csv", index=False
        )

        eicu_broad = eicu_all[
            eicu_all["trajectory_loose_eligible"] == 1
        ].copy()
        broad_p = enhanced_model.predict_proba(
            eicu_broad[nursing]
        )[:, 1]
        broad_metrics = pd.DataFrame([
            metric_row(
                eicu_broad["late_persistent_delirium"].to_numpy(),
                broad_p,
                0.5,
                "eICU broad sensitivity - insufficient assessment as negative",
            )
        ])
        broad_metrics.to_csv(
            result_dir / "broad_missing_as_negative_performance.csv",
            index=False,
        )

        pd.concat([
            clinical_metrics,
            enhanced_metrics,
            indicator_metrics,
            full_indicator_metrics,
            no_antipsychotic_metrics,
            bedside_metrics,
        ], ignore_index=True).to_csv(
            result_dir / "all_harmonized_model_performance.csv",
            index=False,
        )

    membership = pd.read_csv(
        study_dir / "results" / "gbtm" / "mimic_trajectory_membership.csv"
    )
    if "trajectory_class" not in membership and "class" in membership:
        membership = membership.rename(columns={"class": "trajectory_class"})
    mimic_trajectory = mimic.merge(
        membership[["stay_id", "trajectory_class", "high_risk_trajectory"]],
        on="stay_id", how="inner", validate="one_to_one",
    )

    fit_multiclass_trajectory_model(
        mimic_trajectory, eicu, nursing, study_dir, result_dir
    )

    with open(result_dir / "analysis_counts.json", "w", encoding="utf-8") as f:
        json.dump({
            "mimic_n": len(mimic),
            "mimic_late_persistent_events": int(
                mimic["late_persistent_delirium"].sum()
            ),
            "eicu_n": len(eicu),
            "eicu_late_persistent_events": int(
                eicu["late_persistent_delirium"].sum()
            ),
            "clinical_feature_count": len(clinical),
            "nursing_feature_count": len(nursing),
            "nursing_full_sensitivity_feature_count": len(nursing_full),
            "primary_missing_indicator_policy": "disabled",
            "primary_max_missing_fraction": 0.40,
        }, f, indent=2)


if __name__ == "__main__":
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    requested_stage = sys.argv[2] if len(sys.argv) > 2 else "all"
    main(root, requested_stage)
