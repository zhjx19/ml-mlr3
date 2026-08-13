# mlr3verse User Skills

面向 Claude Code 的 mlr3verse 表格数据机器学习 skills。核心目标不是复述 API，而是在生成 R 建模代码时强制执行正确的数据花费、重抽样、防泄露、调参和最终评估流程。

## 可用 skill

### `ml-mlr3`

入口：[`SKILL.md`](SKILL.md)

适用任务：

- 使用 R / mlr3verse 构建分类或回归模型
- 比较多个模型、调参、特征选择、特征工程
- 需要严格训练集 / 测试集隔离和样本外性能估计
- 用户提到 `mlr3`、`mlr3pipelines`、`mlr3tuning`、`mlr3fselect`、`GraphLearner`、`PipeOp`、`auto_tuner` 等关键词

核心覆盖：

- **数据花费**：训练 / 测试集分层划分；开发期测试集绝对隔离
- **重抽样验证**：holdout、CV、repeated CV、group CV、rolling origin
- **防数据泄露**：所有预处理进入 PipeOp / GraphLearner，在重抽样内拟合
- **特征工程**：`po()` / `ppl()` / `%>>%` / `as_learner()`，`ppl("robustify")` 默认预处理管线（14 个 PipeOp 的非线性 DAG）
- **调参**：`auto_tuner()`、分支路由调参、图超参数联合调优
- **特征选择**：`auto_fselector()`、特征选择与超参数联合调优
- **进阶工作流**：不平衡处理 + 调优联合、早停 + 混合调优、备选路径调参、调参器 + 基准测试
- **模型评估**：分类 / 回归指标、可视化、benchmark、嵌套重抽样、最终测试集评估授权

## 最重要红线

1. **测试集绝对隔离**：开发期禁止预测、汇总、可视化、调参或比较测试集。最终评估前必须询问用户并获得明确许可。
2. **R6 引用语义**：`task$select()`、`task$filter()` 等会原地修改 task；需要保留原对象时必须先 `$clone(deep = TRUE)`。
3. **特征工程防泄露**：禁止在 task 外先 `scale()`、插补、SMOTE、PCA、编码后再建模；必须封装进 PipeOp / GraphLearner。
4. **并行需授权**：不得自动启用 `future::plan()`；必须先检查核心数并询问用户。
5. **加密风格**：使用 `=`、`|>`、`\(x)`、`.by`；禁用 `<-`、`%>%`、`function(x)`、`group_by()`。
6. **嵌套重抽样用途**：仅用于无偏比较不同算法性能，而非执行超参数调优。调参用 `$train(task)`。

## 结构

```text
ml-mlr3/
├── SKILL.md                   # skill 入口：工作流、红线、最小代码骨架
└── references/                # 按需读取的详细参考
    ├── data-spending.md       # 数据划分与测试集隔离
    ├── resampling.md          # 重抽样策略
    ├── feature-engineering.md # PipeOp 与模型前处理（总览）
    ├── feature-engineering/   # 特征工程细分
    │   ├── categorical.md     # 分类变量处理
    │   ├── numeric.md         # 数值变换
    │   ├── missing-data.md    # 缺失值插补
    │   └── correlation.md     # 降维去相关
    ├── tuning.md              # 调参、特征选择、嵌套重抽样
    ├── evaluation.md          # 指标、可视化、benchmark、最终评估
    └── advanced-workflows.md  # 5 大进阶工作流（含完整代码）
```

### `advanced-workflows.md` 内容

| 章节 | 核心内容 |
|---|---|
| 自动调参器 + 基准测试 | SVM vs RF 的 auto_tuner + benchmark_grid |
| 图学习器调参 | 图超参数联合调参 + 分支路由调参（Branch Selection） |
| 不平衡处理 + 调优 | SMOTE + 决策树 + auto_tuner 的正确防泄露流程 |
| 特征选择 + 调优联合 | filter.nfeat + ranger 参数同步优化 |
| 早停 + 混合调优 | XGBoost early_stopping + `internal=TRUE` + auto_tuner |

## 与 Autos（aardio）版的关系

本 skill 从 Autos 版 `autos.skills.mlr3verse` 转换而来。转换内容：

- 元数据从 HTML 注释格式改为 YAML frontmatter
- `_.aardio` 主库已删除（Claude Code 不需要）
- `.res/skill.md` → `SKILL.md`
- `.res/knowledge/` → `references/`

两个版本的核心 R 代码和方法论完全一致，可互相同步。

## 与 tidymodels skills 的关系

二者服务相同建模目标，但对象模型不同：

- tidymodels：`recipe()` + `workflow()` + tune
- mlr3verse：R6 `Task` / `Learner` / `Resampling` + `PipeOp` 图学习器 + `auto_tuner()` / `auto_fselector()`

如果用户明确要求 mlr3verse，必须使用本 skill 的路线；不要混用 tidymodels 的 recipe / workflow 语法。
