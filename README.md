# WWO经济实验室｜第23代接续基线

## 第二轮云端研究候选（2026-10-25）

当前源码已包含第二轮候选增量；原Gen23 Release保持不变。
[综合报告、准确提交与云端运行](docs/research/ROUND2_REPORT_20261025.md)记录了Godot 4.6.3无缓存导入、
365日指标、Formal同起点对照、Gen23人物HTTP链、有限煤铁—钢材生产和一笔跨国实物交付。
完整产业与全球指数促成实际改价的闭环仍为CONDITIONAL。
唯一入口仍是手动工作流 `economy-cloud-check.yml`，本轮综合模式为 `round2-full`。
本轮一次性授权已完成，不自动开启下一轮；以下Gen23归档说明保留其历史范围。

本仓库是 **WWO经济研究的独立仓库**，不管理、不写入也不清理 `ryoumiyahayato/wwo` 主游戏仓库的分支。

## 独立人物经济沙盒与依赖位置（2026-10-25核对）

- **[独立人物/个人经济可视化工作台（86文件原样迁入）](experiments/algorithm-workbench/)**：来源于本仓库PR #11既有分支，可使用Node.js/npm/Python启动原创演示；其PRIVATE正式经济观察适配器仍锁定主WWO历史正式经济提交 `b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`，**没有验证与当前第23代自动兼容**，不能把原沙盒成功当成Gen23通过。启动与依赖见 [状态记录](experiments/algorithm-workbench/INTEGRATION_STATUS_20261025.md)。
- **[个人钱包/具名人口测试与早期V2.3人物样本（8原件）](experiments/individual-person-sandbox/)**：已从主WWO固定提交 `28cdc2dc37c68161dc7b3a3254692980cc75e972` 只读复制，并核对全部8个Git Blob SHA相同；它们是隔离的研究夹具，不会替代正式人口或Ledger。
- 第23代完整Godot工程的**509个源码文件**在本仓库根目录；大型地图/地理数据、共享目录、Godot导入缓存、保存世界及历史试验在 [Gen23私有Release](https://github.com/ryoumiyahayato/wwo-economy/releases/tag/economy-gen23-closeout-20261024)。不能仅凭clone默认分支宣称可直接运行。
- 第23代档案的23,379个恢复基线文件记录中，已找到509份源码静态引用到的274个不同 `res://` 路径。未做无缓存引擎导入、独立人物工作台到Gen23的兼容性测试。
- 当前仓库保留6个活动分支是因为4个旧PR还未关闭：`main`与若干PR head/base仍被依赖。固定默认分支是 `sandbox/main`，其他分支不代表额外最新版。只处理本经济库，不修改主WWO分支。

## 唯一当前入口

**固定默认分支：`sandbox/main`。** 它不随日期或实验代数更名，也不因新研究完成而切换默认分支。

- [第23代最新源码根目录](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/sandbox/main)：`project.godot`、`merchant/`、`scripts/`、`shaders/`，共509个归档来源文件。
- [第23代完整私有归档 Release](https://github.com/ryoumiyahayato/wwo-economy-lab/releases/tag/economy-gen23-closeout-20261024)：完整源码原包、地图/地理数据/导入缓存、存档、历史研究及恢复校验。
- [恢复操作与依赖说明](https://github.com/ryoumiyahayato/wwo-economy-lab/releases/download/economy-gen23-closeout-20261024/RESTORE.md)。
- [经济研究分支归档索引](docs/BRANCH_CONSOLIDATION_20261025.md)。

这里的509个文件是**第23代研究候选的代码快照**，包括复用的原正式世界接口，并不表示这些代码全部归经济线独立所有；它也不是可脱离资源直接启动的完整Godot工程。运行需要按Release恢复 `assets/`、`data/`、`shared/`、`.godot/imported/` 等依赖和指定slot7存档。**不要用GitHub自动生成的 Source code ZIP 代替包含依赖的Release。**

## 已验证的能力和边界

- 第23代全球指标：50经济聚合区域、16商品、120稀疏联系，具有供需、价格和运输冲击传导。50×16规模一年指标运行的旧记录约8.58秒，**不含完整R1微观运行成本**。
- 第84日 `minute119520`：在独立GUI验证副本中冷恢复、接手商号、查看延迟公开行情和地图往返。
- 第86日 `minute122400`：巴黎地方订单 `order:299` 完成交付、付款并在二次冷启动后留存。
- **尚未验证或实现**：实际跨国Formal交付、全球指数驱动地方真实改价、完整产业链产能约束、整张经济地图的信息布局完成，以及无缓存引擎重新导入。

全球聚合估计调配不是可提取的实体库存，研究价格指数也不是所有企业的正式成交价。

## 历史与版本管理

旧 `main` 和 `research/*` 分支属于早期Python经济数量模型、供应商及生产计划实验，**不是第23代当前Godot源码**。其历史通过既有标签、指定的归档标签和Git提交保存。未完成PR关联的分支不会在未确认关闭PR之前删除。

**版本约定：** 研发始终沿用 `sandbox/main` 作为稳定入口；有明确需要时才使用短期PR分支，完成后清理。里程碑用Git标签和Release归档；不再按每个小实验自动创建永久分支，也不自动改默认分支。完整的重大历史候选放Release，不把数GB地图、玩家存档、缓存提交Git树。

任何经济研究结果都不能自动同步或覆盖主WWO。只在用户另行明确授权后，才由主WWO的相应负责人决定正式集成。

**当前状态：第23代经济线停止开发；本次仓库整顿不启动Godot，不推进经济世界时间。**
