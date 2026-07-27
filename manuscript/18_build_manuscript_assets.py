from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import FancyBboxPatch


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
RESULTS = ROOT / "results"
OUT = Path(__file__).resolve().parent / "assets"
OUT.mkdir(parents=True, exist_ok=True)

FEATURE_LABELS = {
    "age": "Age",
    "sex": "Sex",
    "race": "Race/ethnicity",
    "icu_type": "ICU type",
    "admission_type": "Admission type",
    "bmi": "Body mass index",
    "gcs_min": "Minimum GCS",
    "rass_min": "Minimum RASS",
    "rass_max": "Maximum RASS",
    "pain_mean": "Mean pain score",
    "mechvent_24h": "Mechanical ventilation",
    "vasoactive_24h": "Vasoactive medication",
    "rrt_24h": "Renal replacement therapy",
    "psychiatric_disorder": "Psychiatric disorder",
    "alcohol_use_disorder": "Alcohol use disorder",
    "urineoutput_24h": "Urine output",
    "glucose_lab_max": "Maximum glucose",
}


def feature_label(feature: str) -> str:
    if feature in FEATURE_LABELS:
        return FEATURE_LABELS[feature]
    label = feature
    for suffix, replacement in [
        ("_24h", " exposure"),
        ("_min", ", minimum"),
        ("_max", ", maximum"),
        ("_mean", ", mean"),
    ]:
        if label.endswith(suffix):
            label = label.removesuffix(suffix) + replacement
            break
    return label.replace("_", " ").capitalize()


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    sex = df["sex"].fillna("").astype(str).str.lower()
    df["sex_h"] = np.select(
        [sex.str.startswith("m"), sex.str.startswith("f")],
        ["Male", "Female"],
        default="Unknown",
    )

    race = df["race"].fillna("").astype(str).str.lower()
    df["race_h"] = np.select(
        [
            race.str.contains(r"white|caucasian", regex=True),
            race.str.contains("black|african", regex=True),
            race.str.contains("hispanic|latino", regex=True),
            race.str.contains(r"\basian\b", regex=True),
        ],
        ["White", "Black", "Hispanic", "Asian"],
        default="Other or unknown",
    )

    icu = df["icu_type"].fillna("").astype(str).str.lower()
    df["icu_type_h"] = np.select(
        [
            icu.str.contains("cardiac|coronary|cicu|ccu", regex=True),
            icu.str.contains("neuro"),
            icu.str.contains("surgical|sicu|csru|ct|cardiothoracic", regex=True),
            icu.str.contains("medical|micu"),
        ],
        ["Cardiac", "Neurologic", "Surgical", "Medical"],
        default="Mixed or other",
    )

    admission = df["admission_type"].fillna("").astype(str).str.lower()
    df["admission_type_h"] = np.select(
        [
            admission.str.contains("emerg|urgent|ew ", regex=True),
            admission.str.contains("elective|operating room|or/pacu", regex=True),
            admission.str.contains("floor|ward|other hospital|transfer", regex=True),
        ],
        ["Emergency or urgent", "Elective or operating room", "Transfer or ward"],
        default="Other or unknown",
    )
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


def strict_cohort(df: pd.DataFrame) -> pd.DataFrame:
    return df.loc[
        (df["trajectory_strict_eligible"] == 1)
        & (df["valid_outcome_days"] >= 2)
    ].copy()


def median_iqr(series: pd.Series, decimals: int = 1) -> str:
    x = pd.to_numeric(series, errors="coerce").dropna()
    if x.empty:
        return "NA"
    q1, median, q3 = x.quantile([0.25, 0.5, 0.75])
    return f"{median:.{decimals}f} [{q1:.{decimals}f}-{q3:.{decimals}f}]"


def n_percent(mask: pd.Series) -> str:
    x = mask.fillna(False).astype(bool)
    return f"{int(x.sum()):,} ({100 * x.mean():.1f})"


def row(
    label: str,
    mimic_value: str,
    eicu_value: str,
    section: str = "",
) -> dict[str, str]:
    return {
        "Section": section,
        "Characteristic": label,
        "MIMIC-IV": mimic_value,
        "eICU-CRD": eicu_value,
    }


def build_table1(mimic: pd.DataFrame, eicu: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, str]] = []

    rows.append(row("Age, years", median_iqr(mimic.age), median_iqr(eicu.age), "Demographics"))
    rows.append(row("Female sex", n_percent(mimic.sex_h == "Female"), n_percent(eicu.sex_h == "Female")))
    for category in ["White", "Black", "Hispanic", "Asian", "Other or unknown"]:
        rows.append(row(f"Race: {category}", n_percent(mimic.race_h == category), n_percent(eicu.race_h == category)))
    for category in ["Medical", "Surgical", "Cardiac", "Neurologic", "Mixed or other"]:
        rows.append(row(f"ICU type: {category}", n_percent(mimic.icu_type_h == category), n_percent(eicu.icu_type_h == category)))
    rows.append(
        row(
            "Emergency or urgent admission",
            n_percent(mimic.admission_type_h == "Emergency or urgent"),
            n_percent(eicu.admission_type_h == "Emergency or urgent"),
        )
    )

    comorbidities = [
        ("Dementia", "dementia"),
        ("Cerebrovascular disease", "cerebrovascular_disease"),
        ("Hypertension", "hypertension"),
        ("Diabetes", "diabetes"),
        ("Chronic kidney disease", "chronic_kidney_disease"),
        ("Chronic pulmonary disease", "chronic_pulmonary_disease"),
        ("Congestive heart failure", "congestive_heart_failure"),
        ("Liver disease", "liver_disease"),
        ("Cancer", "cancer"),
        ("Psychiatric disorder", "psychiatric_disorder"),
        ("Alcohol use disorder", "alcohol_use_disorder"),
    ]
    for index, (label, feature) in enumerate(comorbidities):
        rows.append(
            row(
                label,
                n_percent(pd.to_numeric(mimic[feature], errors="coerce") == 1),
                n_percent(pd.to_numeric(eicu[feature], errors="coerce") == 1),
                "Comorbidities" if index == 0 else "",
            )
        )

    assessments = [
        ("Minimum GCS", "gcs_min", 0),
        ("Minimum RASS", "rass_min", 0),
        ("Maximum RASS", "rass_max", 0),
    ]
    for index, (label, feature, decimals) in enumerate(assessments):
        rows.append(
            row(
                label,
                median_iqr(mimic[feature], decimals),
                median_iqr(eicu[feature], decimals),
                "First 24-hour assessments" if index == 0 else "",
            )
        )

    exposures = [
        ("Mechanical ventilation", "mechvent_24h"),
        ("Vasoactive medication", "vasoactive_24h"),
        ("Renal replacement therapy", "rrt_24h"),
        ("Sedative exposure", "sedative_24h"),
        ("Benzodiazepine exposure", "benzodiazepine_24h"),
        ("Opioid exposure", "opioid_24h"),
        ("Antipsychotic exposure", "antipsychotic_24h"),
        ("Transfusion exposure", "transfusion_24h"),
    ]
    for index, (label, feature) in enumerate(exposures):
        rows.append(
            row(
                label,
                n_percent(pd.to_numeric(mimic[feature], errors="coerce") == 1),
                n_percent(pd.to_numeric(eicu[feature], errors="coerce") == 1),
                "First 24-hour treatment exposures" if index == 0 else "",
            )
        )

    physiology = [
        ("Minimum heart rate, beats/min", "heart_rate_min", 0),
        ("Maximum heart rate, beats/min", "heart_rate_max", 0),
        ("Minimum mean arterial pressure, mm Hg", "mbp_min", 0),
        ("Maximum respiratory rate, breaths/min", "resp_rate_max", 0),
        ("Minimum temperature, degrees C", "temperature_min", 1),
        ("Maximum temperature, degrees C", "temperature_max", 1),
        ("Minimum SpO2, %", "spo2_min", 0),
        ("Maximum WBC, 10^9/L", "wbc_max", 1),
        ("Minimum hemoglobin, g/dL", "hemoglobin_min", 1),
        ("Minimum platelets, 10^9/L", "platelet_min", 0),
        ("Minimum sodium, mmol/L", "sodium_min", 0),
        ("Maximum sodium, mmol/L", "sodium_max", 0),
        ("Maximum BUN, mg/dL", "bun_max", 0),
        ("Maximum creatinine, mg/dL", "creatinine_max", 1),
        ("Maximum glucose, mg/dL", "glucose_lab_max", 0),
        ("Urine output, mL/24 h", "urineoutput_24h", 0),
    ]
    for index, (label, feature, decimals) in enumerate(physiology):
        rows.append(
            row(
                label,
                median_iqr(mimic[feature], decimals),
                median_iqr(eicu[feature], decimals),
                "First 24-hour physiology and laboratory values" if index == 0 else "",
            )
        )

    rows.append(
        row(
            "Late or persistent delirium",
            n_percent(pd.to_numeric(mimic.late_persistent_delirium, errors="coerce") == 1),
            n_percent(pd.to_numeric(eicu.late_persistent_delirium, errors="coerce") == 1),
            "Outcome",
        )
    )
    return pd.DataFrame(rows)


def flow_counts(df: pd.DataFrame, source: str) -> dict[str, int]:
    not_loose = int((df["trajectory_loose_eligible"] == 0).sum())
    no_negative = int(
        (
            (df["trajectory_loose_eligible"] == 1)
            & (df["trajectory_strict_eligible"] == 0)
        ).sum()
    )
    strict = int((df["trajectory_strict_eligible"] == 1).sum())
    insufficient = int(
        (
            (df["trajectory_strict_eligible"] == 1)
            & (df["valid_outcome_days"] < 2)
        ).sum()
    )
    final = int(
        (
            (df["trajectory_strict_eligible"] == 1)
            & (df["valid_outcome_days"] >= 2)
        ).sum()
    )
    return {
        "source": source,
        "candidate": len(df),
        "baseline_positive_or_other_ineligible": not_loose,
        "no_documented_negative_baseline": no_negative,
        "strict_baseline_eligible": strict,
        "fewer_than_2_observed_outcome_days": insufficient,
        "primary_cohort": final,
    }


def draw_flow(mimic: dict[str, int], eicu: dict[str, int]) -> None:
    fig, ax = plt.subplots(figsize=(12.6, 7.6), dpi=220)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    colors = {
        "mimic": "#2E74B5",
        "eicu": "#B5523B",
        "exclude": "#F1F3F5",
        "border": "#2F343B",
    }

    def box(x: float, y: float, width: float, height: float, text: str, face: str, color: str = "#FFFFFF", size: float = 10.5) -> None:
        patch = FancyBboxPatch(
            (x, y),
            width,
            height,
            boxstyle="round,pad=0.008,rounding_size=0.008",
            linewidth=1.1,
            edgecolor=colors["border"],
            facecolor=face,
        )
        ax.add_patch(patch)
        ax.text(x + width / 2, y + height / 2, text, ha="center", va="center", color=color, fontsize=size)

    def arrow(x: float, y1: float, y2: float) -> None:
        ax.annotate("", xy=(x, y2), xytext=(x, y1), arrowprops={"arrowstyle": "->", "lw": 1.3, "color": colors["border"]})

    columns = [(0.08, mimic, "MIMIC-IV development database", "mimic"), (0.55, eicu, "eICU-CRD external database", "eicu")]
    for x, counts, title, key in columns:
        width = 0.37
        box(x, 0.83, width, 0.09, f"{title}\nOlder first ICU stays >24 h: n={counts['candidate']:,}", colors[key])
        arrow(x + width / 2, 0.83, 0.77)
        box(
            x,
            0.65,
            width,
            0.12,
            "Excluded before strict baseline eligibility\n"
            f"Baseline positive/otherwise ineligible: n={counts['baseline_positive_or_other_ineligible']:,}\n"
            f"No documented negative baseline screen: n={counts['no_documented_negative_baseline']:,}",
            colors["exclude"],
            color="#20242A",
            size=9.4,
        )
        arrow(x + width / 2, 0.65, 0.59)
        box(x, 0.50, width, 0.09, f"Strict baseline-eligible cohort\nn={counts['strict_baseline_eligible']:,}", "#FFFFFF", color="#20242A")
        arrow(x + width / 2, 0.50, 0.44)
        box(
            x,
            0.34,
            width,
            0.10,
            "Excluded: fewer than 2 observed\noutcome days during ICU days 2-5\n"
            f"n={counts['fewer_than_2_observed_outcome_days']:,}",
            colors["exclude"],
            color="#20242A",
            size=9.6,
        )
        arrow(x + width / 2, 0.34, 0.28)
        box(
            x,
            0.15,
            width,
            0.13,
            f"Primary analysis cohort\nn={counts['primary_cohort']:,}\n"
            f"Late/persistent delirium: "
            f"{100 * (1005 if key == 'mimic' else 309) / counts['primary_cohort']:.2f}%",
            colors[key],
        )

    ax.text(
        0.5,
        0.055,
        "The strict cohort required a documented negative delirium assessment during ICU hours 0-24 "
        "and at least two observed daily CAM-ICU outcome assessments during ICU days 2-5.",
        ha="center",
        va="center",
        fontsize=9.2,
        color="#3B4148",
        wrap=True,
    )
    fig.savefig(OUT / "figure_1_cohort_flow.png", bbox_inches="tight", facecolor="white")
    plt.close(fig)


def draw_dca() -> None:
    path = RESULTS / "models" / "nursing_enhanced_harmonized_decision_curve.csv"
    dca = pd.read_csv(path)
    fig, axes = plt.subplots(1, 2, figsize=(11.8, 4.5), dpi=220, sharey=False)
    for ax, dataset in zip(axes, dca["dataset"].unique()):
        frame = dca.loc[dca["dataset"] == dataset]
        ax.plot(frame.threshold_probability, frame.model_net_benefit, color="#2E74B5", lw=2.2, label="Enhanced model")
        ax.plot(frame.threshold_probability, frame.treat_all_net_benefit, color="#B5523B", lw=1.7, ls="--", label="Treat all")
        ax.axhline(0, color="#4D535A", lw=1.3, label="Treat none")
        ax.set_xlim(0.01, 0.50)
        ax.set_xlabel("Threshold probability")
        ax.set_ylabel("Net benefit")
        ax.set_title(dataset.replace(" - nursing_enhanced_harmonized", ""), fontsize=10.5)
        ax.grid(axis="y", color="#D9DEE3", lw=0.7)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=3, frameon=False)
    fig.subplots_adjust(bottom=0.20, wspace=0.24)
    fig.savefig(OUT / "figure_s2_decision_curve.png", bbox_inches="tight", facecolor="white")
    plt.close(fig)


def draw_calibration() -> None:
    path = (
        RESULTS
        / "models"
        / "nursing_enhanced_harmonized_calibration_bins.csv"
    )
    bins = pd.read_csv(path)
    datasets = ["MIMIC internal OOF", "eICU external"]
    colors = ["#2E74B5", "#B5523B"]
    upper = min(
        1.0,
        max(
            0.35,
            float(
                bins[["mean_predicted", "observed_rate"]]
                .max()
                .max()
            )
            * 1.12,
        ),
    )
    fig, axes = plt.subplots(1, 2, figsize=(10.8, 4.7), dpi=220)
    for ax, dataset, color in zip(axes, datasets, colors):
        frame = bins[bins["dataset"] == dataset].sort_values(
            "mean_predicted"
        )
        ax.plot([0, 1], [0, 1], color="#6C757D", ls="--", lw=1.2)
        ax.plot(
            frame["mean_predicted"],
            frame["observed_rate"],
            marker="o",
            ms=5,
            color=color,
            lw=2,
        )
        ax.set_xlim(0, upper)
        ax.set_ylim(0, upper)
        ax.set_xlabel("Mean predicted probability")
        ax.set_ylabel("Observed event proportion")
        ax.set_title(dataset)
        ax.grid(color="#D9DEE3", lw=0.7)
    fig.tight_layout()
    fig.savefig(
        OUT / "figure_3_calibration.png",
        bbox_inches="tight",
        facecolor="white",
    )
    plt.close(fig)


def build_table2() -> pd.DataFrame:
    primary = RESULTS / "models" / "primary_harmonized_model_performance.csv"
    performance = pd.read_csv(
        primary
        if primary.exists()
        else RESULTS / "models" / "all_harmonized_model_performance.csv"
    )
    keep = performance.loc[
        performance["dataset"].str.contains("clinical_baseline_harmonized|nursing_enhanced_harmonized", regex=True)
        & ~performance["dataset"].str.contains("without|missing", case=False, regex=True)
    ].copy()
    keep["Model"] = np.where(
        keep["dataset"].str.contains("clinical_baseline"),
        "Clinical baseline",
        "Nursing-assessment and treatment-enhanced",
    )
    keep["Validation"] = np.where(keep["dataset"].str.startswith("MIMIC"), "MIMIC-IV internal OOF", "eICU-CRD external")

    def ci(metric: str, digits: int = 3) -> list[str]:
        return [
            f"{v:.{digits}f} ({lo:.{digits}f}-{hi:.{digits}f})"
            for v, lo, hi in zip(
                keep[metric],
                keep[f"{metric}_ci_low"],
                keep[f"{metric}_ci_high"],
            )
        ]

    table = pd.DataFrame(
        {
            "Model": keep["Model"],
            "Validation": keep["Validation"],
            "AUROC (95% CI)": ci("auroc"),
            "AUPRC (95% CI)": ci("auprc"),
            "Brier score (95% CI)": ci("brier"),
            "Calibration intercept (95% CI)": ci("calibration_intercept"),
            "Calibration slope (95% CI)": ci("calibration_slope"),
        }
    )
    return table


def build_table3() -> pd.DataFrame:
    ablation = pd.read_csv(RESULTS / "models" / "assessment_selection_model_ablation.csv")
    diagnostics = pd.read_csv(RESULTS / "models" / "assessment_selection_diagnostics.csv")
    table = ablation.merge(
        diagnostics[["dataset", "effective_sample_size"]],
        on="dataset",
        how="left",
    )
    labels = {
        ("mimic", "patient_features_only"): "MIMIC-IV: patient features",
        ("eicu", "patient_features_only"): "eICU: patient features",
        ("eicu", "hospital_attributes_only"): "eICU: measured hospital attributes",
        ("eicu", "hospital_only"): "eICU: hospital identity",
        (
            "eicu",
            "patient_features_plus_hospital_attributes",
        ): "eICU: patient features + measured hospital attributes",
        ("eicu", "patient_features_plus_hospital"): "eICU: patient features + hospital identity",
    }
    table["Selection model"] = [
        labels[(dataset, variant)]
        for dataset, variant in zip(table.dataset, table.model_variant)
    ]
    table["Candidate n"] = table.candidate_n if "candidate_n" in table else table.n
    table["Selected n (%)"] = [
        f"{selected:,} ({100 * rate:.2f})"
        for selected, rate in zip(table.selected, table.selection_rate)
    ]
    table["AUROC"] = table.auroc.map(lambda x: f"{x:.3f}")
    table["AUPRC"] = table.auprc.map(lambda x: f"{x:.3f}")
    table["IPW effective sample size"] = [
        f"{ess:.1f}" if variant in {"patient_features_only", "patient_features_plus_hospital"} else "NA"
        for ess, variant in zip(table.effective_sample_size, table.model_variant)
    ]
    return table[
        [
            "Selection model",
            "Candidate n",
            "Selected n (%)",
            "AUROC",
            "AUPRC",
            "IPW effective sample size",
        ]
    ]


def build_table_s2() -> pd.DataFrame:
    performance = pd.read_csv(
        RESULTS / "models" / "coding_harmonization_sensitivity_performance.csv"
    )
    paired = pd.read_csv(
        RESULTS / "models" / "coding_harmonization_sensitivity_paired_bootstrap.csv"
    ).set_index("omitted_feature")
    labels = {
        "psychiatric_disorder": "Omit psychiatric disorder",
        "icu_type": "Omit ICU type",
        "race": "Omit race",
    }

    def ci(row: pd.Series, metric: str) -> str:
        return (
            f"{row[metric]:.3f} "
            f"({row[f'{metric}_ci_low']:.3f}-{row[f'{metric}_ci_high']:.3f})"
        )

    rows = []
    for _, row in performance.iterrows():
        omitted = row["omitted_feature"]
        external = row["dataset"].startswith("eICU")
        delta = paired.loc[omitted]
        rows.append({
            "Analysis": labels[omitted],
            "Validation": (
                "eICU-CRD external" if external else "MIMIC-IV internal OOF"
            ),
            "AUROC (95% CI)": ci(row, "auroc"),
            "AUPRC (95% CI)": ci(row, "auprc"),
            "Brier score": f"{row['brier']:.3f}",
            "Calibration intercept / slope": (
                f"{row['calibration_intercept']:.3f} / "
                f"{row['calibration_slope']:.3f}"
            ),
            "External AUROC difference vs primary (95% CI)": (
                f"{delta['auroc_difference']:.3f} "
                f"({delta['difference_ci_low']:.3f} to "
                f"{delta['difference_ci_high']:.3f})"
                if external else "NA"
            ),
        })
    return pd.DataFrame(rows)


def build_table_s1() -> pd.DataFrame:
    profile = pd.read_csv(
        RESULTS / "models" / "harmonized_feature_profile.csv"
    )
    rows = []
    for row in profile.itertuples():
        rows.append({
            "Predictor": feature_label(row.feature),
            "MIMIC-IV missing, %": f"{100 * row.mimic_missing:.1f}",
            "eICU-CRD missing, %": f"{100 * row.eicu_missing:.1f}",
            "Included in primary enhanced model": (
                "Yes" if row.selected_primary == 1 else "No"
            ),
            "MIMIC-IV mean": (
                f"{row.mimic_mean:.2f}"
                if hasattr(row, "mimic_mean") and pd.notna(row.mimic_mean)
                else "NA"
            ),
            "eICU-CRD mean": (
                f"{row.eicu_mean:.2f}"
                if hasattr(row, "eicu_mean") and pd.notna(row.eicu_mean)
                else "NA"
            ),
            "Standardized mean difference": (
                f"{row.standardized_mean_difference:.3f}"
                if hasattr(row, "standardized_mean_difference")
                and pd.notna(row.standardized_mean_difference)
                else "NA"
            ),
        })
    return pd.DataFrame(rows)


def build_table_s3() -> pd.DataFrame:
    endpoint = pd.read_csv(
        RESULTS / "models" / "alternative_endpoint_performance.csv"
    )
    logistic = pd.read_csv(
        RESULTS / "models" / "regularized_logistic_benchmark_performance.csv"
    )
    frames = []
    for analysis, frame in [
        ("Alternative endpoint", endpoint),
        ("Regularized logistic benchmark", logistic),
    ]:
        temp = frame.copy()
        temp.insert(0, "Analysis group", analysis)
        frames.append(temp)
    combined = pd.concat(frames, ignore_index=True)
    return pd.DataFrame({
        "Analysis group": combined["Analysis group"],
        "Model / dataset": combined["dataset"],
        "Endpoint": combined.get(
            "endpoint",
            pd.Series(["Primary"] * len(combined)),
        ).fillna("Primary"),
        "AUROC (95% CI)": [
            f"{row.auroc:.3f} ({row.auroc_ci_low:.3f}-{row.auroc_ci_high:.3f})"
            for row in combined.itertuples()
        ],
        "AUPRC (95% CI)": [
            f"{row.auprc:.3f} ({row.auprc_ci_low:.3f}-{row.auprc_ci_high:.3f})"
            for row in combined.itertuples()
        ],
        "Brier score (95% CI)": [
            f"{row.brier:.3f} ({row.brier_ci_low:.3f}-{row.brier_ci_high:.3f})"
            for row in combined.itertuples()
        ],
    })


def build_table_s4() -> pd.DataFrame:
    subgroup = pd.read_csv(
        RESULTS / "models" / "primary_model_subgroup_performance.csv"
    )
    rows = []
    for row in subgroup.itertuples():
        estimable = row.estimable == 1
        rows.append({
            "Dataset": row.dataset,
            "Subgroup variable": feature_label(row.subgroup_variable),
            "Subgroup": row.subgroup,
            "n": row.n,
            "Events": row.events,
            "AUROC (95% CI)": (
                f"{row.auroc:.3f} ({row.auroc_ci_low:.3f}-"
                f"{row.auroc_ci_high:.3f})"
                if estimable else "Not estimated"
            ),
            "Calibration slope (95% CI)": (
                f"{row.calibration_slope:.3f} "
                f"({row.calibration_slope_ci_low:.3f}-"
                f"{row.calibration_slope_ci_high:.3f})"
                if estimable else "Not estimated"
            ),
        })
    return pd.DataFrame(rows)


def main() -> None:
    mimic_all = normalize_columns(pd.read_csv(DATA / "mimic_features_outcomes.csv", low_memory=False))
    eicu_all = normalize_columns(pd.read_csv(DATA / "eicu_features_outcomes.csv", low_memory=False))
    mimic = strict_cohort(mimic_all)
    eicu = strict_cohort(eicu_all)

    m_flow = flow_counts(mimic_all, "MIMIC-IV")
    e_flow = flow_counts(eicu_all, "eICU-CRD")
    pd.DataFrame([m_flow, e_flow]).to_csv(OUT / "cohort_flow_counts.csv", index=False)
    build_table1(mimic, eicu).to_csv(OUT / "table_1_baseline_characteristics.csv", index=False)
    build_table2().to_csv(OUT / "table_2_model_performance.csv", index=False)
    build_table3().to_csv(OUT / "table_3_assessment_selection.csv", index=False)
    build_table_s2().to_csv(
        OUT / "table_s2_coding_harmonization_sensitivity.csv", index=False
    )
    build_table_s1().to_csv(
        OUT / "table_s1_feature_missingness.csv", index=False
    )
    build_table_s3().to_csv(
        OUT / "table_s3_endpoint_and_logistic_sensitivity.csv", index=False
    )
    build_table_s4().to_csv(
        OUT / "table_s4_subgroup_performance.csv", index=False
    )

    draw_flow(m_flow, e_flow)
    draw_calibration()
    draw_dca()
    print(f"Created manuscript assets in {OUT}")
    print(pd.DataFrame([m_flow, e_flow]).to_string(index=False))


if __name__ == "__main__":
    main()
