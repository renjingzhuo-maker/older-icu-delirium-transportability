# 老年 ICU 谵妄研究：最终修订结果（2026-07-27）

本文件汇总投稿前最终分析。所有 XGBoost 主模型和敏感性模型均使用相同的患者分组嵌套交叉验证与 20 组参数搜索预算；eICU 外部置信区间使用医院和患者两阶段 bootstrap。

## 1. 队列与结局

| 队列 | 样本量 | 迟发/持续性谵妄 | 发生率 |
|---|---:|---:|---:|
| MIMIC-IV 开发队列 | 5,753 | 1,005 | 17.47% |
| eICU-CRD 外部验证队列 | 2,609 | 309 | 11.84% |

两个数据库使用完全相同的 `late_persistent_delirium` 规则。预测窗口为 ICU 入科后 `0 <= t < 24 h`，结局从严格大于 24 小时开始，覆盖 ICU 第 2-5 天。临床基线模型含 37 个原始特征，护理评估与治疗增强模型含 45 个。

## 2. 主模型性能

| 模型 | MIMIC OOF AUROC（95% CI） | eICU AUROC（95% CI） | eICU AUPRC（95% CI） | eICU Brier（95% CI） | eICU 校准截距（95% CI） | eICU 校准斜率（95% CI） |
|---|---:|---:|---:|---:|---:|---:|
| 临床基线 | 0.696（0.677-0.715） | 0.598（0.546-0.662） | 0.157（0.119-0.221） | 0.115（0.096-0.136） | -1.322（-1.830 至 -0.817） | 0.460（0.191-0.800） |
| 护理评估与治疗增强 | 0.730（0.710-0.746） | 0.665（0.613-0.712） | 0.189（0.141-0.258） | 0.115（0.097-0.137） | -1.157（-1.593 至 -0.753） | 0.581（0.379-0.800） |

护理评估与治疗增强模型相对临床基线的配对 AUROC 增量：

- MIMIC-IV：+0.034（95% CI 0.023-0.045）
- eICU-CRD：+0.068（医院层级 95% CI 0.027-0.095）

增强模型的外部判别力有稳定增量，但校准不足，不可作为可部署床旁工具。外部表观截距重校准将 Brier 降至 0.105，截距与斜率重校准降至 0.101；两者均为同一外部数据上的诊断性结果，不是独立验证。

## 3. 替代结局与算法基准

| 分析 | MIMIC 事件 | eICU 事件 | 增强模型 eICU AUROC |
|---|---:|---:|---:|
| 至少 2 个阳性观察日 | 766 | 202 | 0.691 |
| 任一 24 h 后阳性日 | 1,500 | 428 | 0.678 |

全特征 L2 正则化 Logistic 回归的外部 AUROC 为：

- 临床基线：0.583
- 护理评估与治疗增强：0.620

护理评估与治疗变量的增量并非完全依赖 XGBoost，但树模型在外部数据上仍提供额外判别力。

## 4. 评估选择机制

eICU 严格队列仅占 57,637 名候选患者的 4.53%。

| eICU 选择模型 | AUROC | AUPRC |
|---|---:|---:|
| 仅患者特征 | 0.717 | 0.132 |
| 仅教学状态、床位规模、地区 | 0.755 | 0.102 |
| 患者特征 + 可观测医院属性 | 0.815 | 0.196 |
| 仅医院身份 | 0.936 | 0.312 |
| 患者特征 + 医院身份 | 0.944 | 0.377 |

置换医院身份使 AUROC 平均下降 0.365，而任何单个患者特征的平均下降均不超过 0.004。该结果说明医院身份与是否具有充分 CAM-ICU 记录高度相关，但不能证明医院评估制度导致模型性能下降。

IPW 后 eICU 有效样本量仅 390.5，提示严重 positivity violation；加权结果仅作敏感性分析。

## 5. 编码、缺失与治疗敏感性

- 删除精神疾病：外部 AUROC 0.670（0.617-0.715），相对主模型 +0.0047（0.0004-0.0089）。
- 删除 ICU 类型：外部 AUROC 0.672（0.617-0.714），相对主模型 +0.0067（-0.0137-0.0206）。
- 删除种族：外部 AUROC 0.665（0.612-0.710），相对主模型 -0.0002（-0.0041-0.0038）。
- 删除抗精神病药：外部 AUROC 0.666（0.613-0.712）。
- 完整变量加缺失指示：外部 AUROC 0.648（0.596-0.694）。
- 简化床旁评分：外部 AUROC 0.601，Brier 0.219，校准斜率 0.436；不建议部署。

没有任何单一编码变量可以解释迁移差距或外部校准不足。

## 6. 亚组与医院代表性

外部 AUROC 在女性和男性中分别为 0.661 和 0.670；65-74、75-84 和至少 85 岁组分别为 0.674、0.677 和 0.616。eICU 中仅 White 和 Black 组满足至少 20 个事件和 20 个非事件的估计门槛；较小种族组不报告不稳定估计。

206 家候选医院中，40 家进入严格队列，34 家同时具有阳性和阴性结局。17 家满足 AUROC 置信区间门槛，覆盖 80.34% 患者和 87.38% 事件；仅 10 家满足院内校准门槛。

## 7. 最终论文定位

推荐题目：

> Explainable Prediction of Late or Persistent Delirium in Serially Assessed Older ICU Patients: Development in MIMIC-IV and Multicenter Transportability Assessment in eICU-CRD

核心结论是：前 24 小时 GCS、RASS 和治疗暴露提供了可重复的增量预测信息，但外部校准和医院层面表现不足以支持部署；医院身份强烈预测是否有足够的序贯谵妄评估，限制了外部队列代表性和可推广结论的范围。

## 8. 正式结果文件

- `results/models/primary_harmonized_model_performance.csv`
- `results/models/nursing_increment_paired_bootstrap.csv`
- `results/models/nursing_enhanced_harmonized_calibration_bins.csv`
- `results/models/nursing_enhanced_harmonized_recalibration_diagnostics.csv`
- `results/models/alternative_endpoint_performance.csv`
- `results/models/regularized_logistic_benchmark_performance.csv`
- `results/models/primary_model_subgroup_performance.csv`
- `results/models/coding_harmonization_sensitivity_performance.csv`
- `results/models/assessment_selection_model_ablation.csv`
- `results/models/eicu_assessment_selection_permutation_importance.csv`
- `results/models/nursing_enhanced_harmonized_eicu_hospital_transportability.csv`
