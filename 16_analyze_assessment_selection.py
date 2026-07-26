import importlib.util
import sys
from pathlib import Path

import joblib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import sparse
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    roc_auc_score,
)
from sklearn.model_selection import StratifiedGroupKFold, cross_val_predict
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


def load_modeling_module(study_dir: Path):
    path = study_dir / "09_train_validate_models.py"
    spec = importlib.util.spec_from_file_location("delirium_models", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def make_selection_pipeline(
    features: list[str],
    categorical_features: list[str],
    seed: int,
) -> Pipeline:
    numeric_features = [
        feature for feature in features if feature not in categorical_features
    ]
    preprocessor = ColumnTransformer(
        transformers=[
            (
                "numeric",
                Pipeline([
                    (
                        "imputer",
                        SimpleImputer(strategy="median", add_indicator=True),
                    ),
                    ("scaler", StandardScaler()),
                ]),
                numeric_features,
            ),
            (
                "categorical",
                Pipeline([
                    ("imputer", SimpleImputer(strategy="most_frequent")),
                    (
                        "onehot",
                        OneHotEncoder(
                            handle_unknown="ignore",
                            sparse_output=True,
                        ),
                    ),
                ]),
                categorical_features,
            ),
        ],
        remainder="drop",
        sparse_threshold=0.3,
        verbose_feature_names_out=False,
    )
    return Pipeline([
        ("preprocess", preprocessor),
        (
            "model",
            LogisticRegression(
                C=1.0,
                solver="liblinear",
                max_iter=1000,
                random_state=seed,
            ),
        ),
    ])


def fit_selection_variant(
    data: pd.DataFrame,
    target: np.ndarray,
    groups: np.ndarray,
    features: list[str],
    categorical_features: list[str],
    dataset: str,
    variant: str,
    seed: int,
) -> tuple[dict, Pipeline]:
    model = make_selection_pipeline(features, categorical_features, seed)
    cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=seed,
    )
    probability = cross_val_predict(
        model,
        data[features],
        target,
        groups=groups,
        cv=cv,
        method="predict_proba",
        n_jobs=1,
    )[:, 1]
    fitted = model.fit(data[features], target)
    row = {
        "dataset": dataset,
        "model_variant": variant,
        "n": len(target),
        "selected": int(target.sum()),
        "selection_rate": float(target.mean()),
        "auroc": float(roc_auc_score(target, probability)),
        "auprc": float(average_precision_score(target, probability)),
        "brier": float(brier_score_loss(target, probability)),
    }
    return row, fitted


def raw_feature_name(
    transformed_name: str,
    raw_features: list[str],
) -> tuple[str, str]:
    if transformed_name.startswith("missingindicator_"):
        return transformed_name.removeprefix("missingindicator_"), "missing_indicator"
    for feature in sorted(raw_features, key=len, reverse=True):
        if transformed_name == feature or transformed_name.startswith(f"{feature}_"):
            label = "hospital_site" if feature == "selection_site" else feature
            component = "hospital_fixed_effect" if feature == "selection_site" else "feature"
            return label, component
    return transformed_name, "feature"


def selection_importance(
    model: Pipeline,
    data: pd.DataFrame,
    features: list[str],
    result_dir: Path,
    source: str,
) -> pd.DataFrame:
    transformed = model.named_steps["preprocess"].transform(data[features])
    coefficients = model.named_steps["model"].coef_[0]
    if sparse.issparse(transformed):
        contribution = transformed.multiply(coefficients)
        mean_absolute = np.asarray(abs(contribution).mean(axis=0)).ravel()
    else:
        mean_absolute = np.mean(
            np.abs(np.asarray(transformed) * coefficients),
            axis=0,
        )
    transformed_names = (
        model.named_steps["preprocess"].get_feature_names_out().tolist()
    )
    rows = []
    for name, coefficient, importance in zip(
        transformed_names,
        coefficients,
        mean_absolute,
        strict=True,
    ):
        raw_feature, component = raw_feature_name(name, features)
        rows.append({
            "transformed_feature": name,
            "raw_feature": raw_feature,
            "component": component,
            "coefficient": float(coefficient),
            "mean_absolute_logit_contribution": float(importance),
        })
    individual = pd.DataFrame(rows).sort_values(
        "mean_absolute_logit_contribution",
        ascending=False,
    )
    individual.to_csv(
        result_dir / f"{source}_assessment_selection_coefficients.csv",
        index=False,
    )
    grouped = (
        individual.groupby(["raw_feature", "component"], as_index=False)
        ["mean_absolute_logit_contribution"]
        .sum()
        .sort_values("mean_absolute_logit_contribution", ascending=False)
    )
    grouped["proportion_of_total"] = (
        grouped["mean_absolute_logit_contribution"]
        / grouped["mean_absolute_logit_contribution"].sum()
    )
    grouped.to_csv(
        result_dir / f"{source}_assessment_selection_grouped_importance.csv",
        index=False,
    )
    return grouped


def cross_validated_permutation_importance(
    data: pd.DataFrame,
    target: np.ndarray,
    groups: np.ndarray,
    features: list[str],
    categorical_features: list[str],
    seed: int,
) -> pd.DataFrame:
    cv = StratifiedGroupKFold(
        n_splits=5,
        shuffle=True,
        random_state=seed,
    )
    rows = []
    for fold, (train_index, test_index) in enumerate(
        cv.split(data[features], target, groups=groups),
        start=1,
    ):
        model = make_selection_pipeline(features, categorical_features, seed)
        model.fit(data.iloc[train_index][features], target[train_index])
        test_data = data.iloc[test_index][features]
        test_target = target[test_index]
        baseline_probability = model.predict_proba(test_data)[:, 1]
        baseline_auroc = roc_auc_score(test_target, baseline_probability)
        for feature_index, feature in enumerate(features):
            permuted = test_data.copy()
            rng = np.random.default_rng(
                seed + fold * 1000 + feature_index
            )
            permuted[feature] = rng.permutation(
                permuted[feature].to_numpy()
            )
            permuted_probability = model.predict_proba(permuted)[:, 1]
            permuted_auroc = roc_auc_score(
                test_target,
                permuted_probability,
            )
            rows.append({
                "fold": fold,
                "feature": (
                    "hospital_site"
                    if feature == "selection_site"
                    else feature
                ),
                "test_n": len(test_index),
                "baseline_auroc": baseline_auroc,
                "permuted_auroc": permuted_auroc,
                "auroc_decrease": baseline_auroc - permuted_auroc,
            })
    fold_results = pd.DataFrame(rows)
    summary = (
        fold_results.groupby("feature", as_index=False)
        .agg(
            mean_auroc_decrease=("auroc_decrease", "mean"),
            sd_auroc_decrease=("auroc_decrease", "std"),
            minimum_auroc_decrease=("auroc_decrease", "min"),
            maximum_auroc_decrease=("auroc_decrease", "max"),
        )
        .sort_values("mean_auroc_decrease", ascending=False)
    )
    return summary


def make_eicu_figure(
    ablation: pd.DataFrame,
    permutation_importance: pd.DataFrame,
    hospitals: pd.DataFrame,
    output_path: Path,
) -> None:
    top = permutation_importance.head(10).sort_values(
        "mean_auroc_decrease",
        ascending=True,
    )
    colors = [
        "#C44E52" if feature == "hospital_site" else "#287D8E"
        for feature in top["feature"]
    ]
    fig, axes = plt.subplots(1, 3, figsize=(17, 5.8))

    eicu_ablation = ablation[ablation["dataset"] == "eicu"].copy()
    labels = {
        "patient_features_only": "Patient features",
        "hospital_only": "Hospital only",
        "patient_features_plus_hospital": "Hospital + patient",
    }
    eicu_ablation["label"] = eicu_ablation["model_variant"].map(labels)
    axes[0].bar(
        eicu_ablation["label"],
        eicu_ablation["auroc"],
        color=["#287D8E", "#C44E52", "#4C72B0"],
    )
    axes[0].axhline(0.5, color="#555555", linestyle=":", linewidth=1)
    axes[0].set_ylim(0.5, 1.0)
    axes[0].set_ylabel("Cross-validated AUROC")
    axes[0].set_title("Selection-model ablation")
    axes[0].tick_params(axis="x", rotation=20)
    for index, value in enumerate(eicu_ablation["auroc"]):
        axes[0].text(index, value + 0.01, f"{value:.3f}", ha="center")

    axes[1].barh(
        top["feature"],
        top["mean_auroc_decrease"],
        color=colors,
        xerr=top["sd_auroc_decrease"].fillna(0),
        error_kw={"elinewidth": 1, "capsize": 2},
    )
    axes[1].set_xlabel("Decrease in selection AUROC after permutation")
    axes[1].set_title("Cross-validated selection drivers")
    axes[1].grid(axis="x", linestyle=":", alpha=0.35)

    hospital_rows = hospitals[hospitals["candidate_n"] > 0].copy()
    has_selected = hospital_rows["n"] > 0
    point_sizes = 20 + 60 * np.sqrt(
        hospital_rows["candidate_n"] / hospital_rows["candidate_n"].max()
    )
    axes[2].scatter(
        hospital_rows.loc[~has_selected, "candidate_n"],
        hospital_rows.loc[~has_selected, "selection_rate"],
        s=point_sizes.loc[~has_selected],
        color="#A7A9AC",
        alpha=0.65,
        label="No strict-cohort patients",
    )
    axes[2].scatter(
        hospital_rows.loc[has_selected, "candidate_n"],
        hospital_rows.loc[has_selected, "selection_rate"],
        s=point_sizes.loc[has_selected],
        color="#287D8E",
        alpha=0.75,
        label="At least one strict-cohort patient",
    )
    overall_rate = hospital_rows["n"].sum() / hospital_rows["candidate_n"].sum()
    axes[2].axhline(
        overall_rate,
        color="#C44E52",
        linestyle="--",
        linewidth=1.3,
        label=f"Overall selection rate: {overall_rate:.1%}",
    )
    axes[2].set_xscale("log")
    axes[2].set_ylim(-0.02, 1.02)
    axes[2].set_xlabel("Candidate patients per hospital (log scale)")
    axes[2].set_ylabel("Proportion entering strict external cohort")
    axes[2].set_title("Hospital-level assessment coverage")
    axes[2].grid(linestyle=":", alpha=0.35)
    axes[2].legend(frameon=False, fontsize=8, loc="upper right")
    fig.tight_layout()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def hospital_representation_summary(hospitals: pd.DataFrame) -> pd.DataFrame:
    strict = hospitals[hospitals["n"] > 0]
    ci_rows = strict[strict["auroc_ci_low"].notna()]
    calibration_rows = strict[strict["calibration_slope"].notna()]
    total_n = strict["n"].sum()
    total_events = strict["events"].sum()
    return pd.DataFrame([{
        "candidate_hospitals": int(len(hospitals)),
        "strict_cohort_hospitals": int(len(strict)),
        "hospitals_with_both_outcome_classes": int(strict["auroc"].notna().sum()),
        "forest_plot_hospitals": int(len(ci_rows)),
        "forest_plot_patients": int(ci_rows["n"].sum()),
        "forest_plot_patient_share": float(ci_rows["n"].sum() / total_n),
        "forest_plot_events": int(ci_rows["events"].sum()),
        "forest_plot_event_share": float(
            ci_rows["events"].sum() / total_events
        ),
        "calibration_hospitals": int(len(calibration_rows)),
    }])


def main() -> None:
    study_dir = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent
    )
    result_dir = study_dir / "results" / "models"
    module = load_modeling_module(study_dir)
    mimic = module.normalize_columns(
        pd.read_csv(study_dir / "data" / "mimic_features_outcomes.csv"),
        "mimic",
    )
    eicu = module.normalize_columns(
        pd.read_csv(study_dir / "data" / "eicu_features_outcomes.csv"),
        "eicu",
    )
    mimic_strict = mimic[
        (mimic["trajectory_strict_eligible"] == 1)
        & (mimic["valid_outcome_days"] >= 2)
    ]
    eicu_strict = eicu[
        (eicu["trajectory_strict_eligible"] == 1)
        & (eicu["valid_outcome_days"] >= 2)
    ]
    clinical = module.available_features(
        mimic_strict,
        eicu_strict,
        module.CLINICAL_FEATURES,
        max_missing=0.40,
    )
    nursing = module.available_features(
        mimic_strict,
        eicu_strict,
        module.CLINICAL_FEATURES + module.NURSING_FEATURES,
        max_missing=0.40,
    )

    increment = [feature for feature in nursing if feature not in clinical]
    increment_manifest = pd.DataFrame({
        "feature": increment,
        "incremental_group": [
            (
                "consciousness_or_sedation_assessment"
                if feature in {"gcs_min", "rass_min", "rass_max"}
                else "medication_or_treatment_exposure"
            )
            for feature in increment
        ],
    })
    increment_manifest.to_csv(
        result_dir / "nursing_increment_feature_manifest.csv",
        index=False,
    )
    increment_manifest.to_csv(
        result_dir
        / "nursing_assessment_treatment_increment_feature_manifest.csv",
        index=False,
    )
    shap_path = (
        result_dir / "nursing_enhanced_harmonized_shap_importance.csv"
    )
    if shap_path.exists():
        increment_shap = (
            pd.read_csv(shap_path)
            .merge(increment_manifest, on="feature", how="inner")
            .sort_values("mean_abs_shap", ascending=False)
        )
        increment_shap.to_csv(
            result_dir
            / "nursing_assessment_treatment_increment_shap.csv",
            index=False,
        )

    rows = []
    fitted_models = {}
    for source, data, group_column, id_column in [
        ("mimic", mimic, "subject_id", "stay_id"),
        ("eicu", eicu, "uniquepid", "patientunitstayid"),
    ]:
        data = data.copy()
        data["assessment_selected"] = (
            (data["trajectory_strict_eligible"] == 1)
            & (data["valid_outcome_days"] >= 2)
        ).astype(int)
        groups = data[group_column].fillna(
            data[id_column].astype(str)
        ).to_numpy()
        target = data["assessment_selected"].to_numpy()
        categorical = [
            feature
            for feature in clinical
            if feature in module.CATEGORICAL_FEATURES
        ]
        row, model = fit_selection_variant(
            data,
            target,
            groups,
            clinical,
            categorical,
            source,
            "patient_features_only",
            module.SEED,
        )
        rows.append(row)
        fitted_models[(source, "patient_features_only")] = model

        if source == "eicu":
            data["selection_site"] = (
                data["hospitalid"].fillna(-1).astype(int).astype(str)
            )
            row, model = fit_selection_variant(
                data,
                target,
                groups,
                ["selection_site"],
                ["selection_site"],
                source,
                "hospital_only",
                module.SEED,
            )
            rows.append(row)
            fitted_models[(source, "hospital_only")] = model

            combined = clinical + ["selection_site"]
            combined_categorical = categorical + ["selection_site"]
            row, model = fit_selection_variant(
                data,
                target,
                groups,
                combined,
                combined_categorical,
                source,
                "patient_features_plus_hospital",
                module.SEED,
            )
            rows.append(row)
            fitted_models[(source, "patient_features_plus_hospital")] = model
            joblib.dump(
                model,
                result_dir / "eicu_assessment_selection_explanation_model.joblib",
            )
            grouped = selection_importance(
                model,
                data,
                combined,
                result_dir,
                source,
            )
        else:
            selection_importance(
                model,
                data,
                clinical,
                result_dir,
                source,
            )

    ablation = pd.DataFrame(rows)
    ablation.to_csv(
        result_dir / "assessment_selection_model_ablation.csv",
        index=False,
    )
    hospitals = pd.read_csv(
        result_dir
        / "nursing_enhanced_harmonized_eicu_hospital_transportability.csv"
    )
    hospital_representation_summary(hospitals).to_csv(
        result_dir / "eicu_hospital_representation_summary.csv",
        index=False,
    )
    eicu_data = eicu.copy()
    eicu_data["assessment_selected"] = (
        (eicu_data["trajectory_strict_eligible"] == 1)
        & (eicu_data["valid_outcome_days"] >= 2)
    ).astype(int)
    eicu_data["selection_site"] = (
        eicu_data["hospitalid"].fillna(-1).astype(int).astype(str)
    )
    eicu_groups = eicu_data["uniquepid"].fillna(
        eicu_data["patientunitstayid"].astype(str)
    ).to_numpy()
    eicu_categorical = [
        feature
        for feature in clinical
        if feature in module.CATEGORICAL_FEATURES
    ] + ["selection_site"]
    permutation_importance = cross_validated_permutation_importance(
        eicu_data,
        eicu_data["assessment_selected"].to_numpy(),
        eicu_groups,
        clinical + ["selection_site"],
        eicu_categorical,
        module.SEED,
    )
    permutation_importance.to_csv(
        result_dir / "eicu_assessment_selection_permutation_importance.csv",
        index=False,
    )
    make_eicu_figure(
        ablation,
        permutation_importance,
        hospitals,
        result_dir / "eicu_assessment_selection_mechanism.png",
    )


if __name__ == "__main__":
    main()
