# WWO经济实验室：当前项目入口

**第23代全球商品市场（2026-10-24最新独立研究版本）**

- [直接查看第23代经济算法源码（51个GDScript、场景和配置文件）](experiments/global-commodity-gen23/) — 从经校验的最新候选提取，保留原相对路径；只读研究镜像，不是可单独运行的Godot项目。
- [下载完整第23代候选工程、地图资源、存档和历史材料](https://github.com/ryoumiyahayato/wwo-economy-lab/releases/tag/economy-gen23-closeout-20261024) — 通过Release附件 `01-source23.tar.gz` 取得完整509文件的接续源码；不要把GitHub自动生成的“Source code”当成最新候选。
- [正式WWO主仓库](https://github.com/ryoumiyahayato/wwo/tree/canonical/current-world) — 实际游戏主线，不因本归档被自动替换。
- 本仓库旧 `main`、`research/*` 等为此前独立Python算法研究，**不是**当前第23代GDScript工程；现有分支及历史提交均未删除。
- 第23代已完成50区域×16商品×120联系的宏观市场观察、GUI冷恢复及巴黎单笔真实经营续存；正式跨国实物贸易与全球指数驱动真实改价仍未验证。

**位置约定：以后独立经济研究优先归入本经济实验室；只有明确批准的正式集成代码才进入WWO主仓库。** 本次整理不新建分支、不合并主WWO、不覆盖经济存档。

---

# WWO Economy Sandbox

此仓库的日常入口为 `sandbox/main`，用于独立经济实验。正式 WWO 构建和运行不依赖本仓库。

长期维护位置：

- [正式游戏经济源码](https://github.com/ryoumiyahayato/wwo/tree/integration/formal-economy-20261014/scripts/world)。本次整合提交 [409199f1](https://github.com/ryoumiyahayato/wwo/commit/409199f1e60f0d042ed61357f1c2b67aa46d2eca)。
- [十五算法研究源码](https://github.com/ryoumiyahayato/wwo/tree/integration/formal-economy-20261014/research/economy/fifteen-algorithms)。与正式 GDScript 分开，不自动接入游戏。
- [迁移与来源说明](https://github.com/ryoumiyahayato/wwo/blob/integration/formal-economy-20261014/docs/research/economy/REPOSITORY_MIGRATION.md)。

旧研究完整保留：

- [旧 main 归档](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/archive/economy-lab-before-sandbox-20261014)：`48b280a37be8f5fd72f0c277f4ae435e675efa1f`，包含原源码、已跟踪结果及祖先历史。
- [Cycle02 归档](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/archive/economy-goal-cycle02-20261014)：`fd557efe1b837ddde7b456651c568bb31718d10b`，包含 Round6、Cycle01、Cycle02 分支历史。
- [受控工作台归档](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/archive/controlled-workbench-before-sandbox-20261014)：`dab110e89a4ffabc2e844fcd14b31cb2008df391`。

旧 main、其他 research 分支及原标签没有删除或重写。沙盒通过旧 main 之后的一次普通提交整理当前树，不建立孤立 Git 历史。默认分支切换只改变默认 clone、浏览和未指定 ref 的 API 入口；旧分支引用保持有效。已有 PR 的目标分支不自动改写。

未来实验放在 `experiments/<实验名>/`，用独立分支维护。每项实验说明输入、人工假设、运行方式和限制。源码与最小配置可以跟踪，输出放在忽略的 `.local/` 或 `artifacts/`。不预装旧经济产品，不创建免费资金或隐含历史参数。

沙盒结果不会自动覆盖 WWO。只有经明确选择和实际接入后，才把选定规则迁入 WWO；不建立双向同步脚本或 submodule 运行依赖。
