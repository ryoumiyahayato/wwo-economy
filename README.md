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
