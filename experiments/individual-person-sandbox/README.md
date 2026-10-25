# 独立人物经济沙盒：来源依赖快照（非正式运行入口）

这是按用户要求，从只读主仓库提取的**隔离研究资料**，不属于第23代正式市场运行链。存放于 `experiments/individual-person-sandbox/from-wwo/`，保留原相对目录结构，避免主仓库更动后找不到历史样本。

**源仓库（只读）**：`ryoumiyahayato/wwo`，分支 `canonical/current-world`，固定提交 `28cdc2dc37c68161dc7b3a3254692980cc75e972`。
**目标仓库（仅写这一库）**：`ryoumiyahayato/wwo-economy`，稳定默认分支 `sandbox/main`。
**复用边界**：仓库根目录的第23代正式候选已有 `FormalPersonalEconomyState`、`FormalWorldPopulationState`、`VNextNamedPersonOverlay` 等。本目录不替换它们，不挂载SceneTree，不向 `project.godot` 增加autoload，也不为经济世界创建第二份Ledger或人口权威。

## 来自主仓库的原件

| 原路径（`from-wwo/`之下） | 源Git Blob SHA |
|---|---|
| `scripts/vnext/economy/personal_wallet.gd` | `80c8db5e51c0c31873de2a0880034bfa39464345` |
| `tests/vnext/personal_economy_test.gd` | `cac2aba331b37d3bf174060e3e1788cf01cbf4dd` |
| `tests/vnext/named_person_overlay_test.gd` | `9f4c3f97de201dd406946a5d8263612b2c3bc096` |
| `data/v2_3/social_people.json` | `963835de2766d2fbbe944eea7048aec786123a98` |
| `data/v2_3/social_sandbox_rules.json` | `3b7247d4db04f95b9f7f5e10880250481f6df671` |
| `docs/V2_3_SOCIAL_SANDBOX_REUSE_AUDIT.md` | `a79b1da403e5f569af9c571ae607e59bffc42d87` |
| `docs/SOCIAL_SANDBOX_TEST_PROTOCOL.md` | `e8ec587bc34d101f3670634b5582403c33d72f27` |
| `docs/vnext/personal_economy.md` | `5270017eb96d404c08e4b514965f897758239e29` |

这8个文件在此仓库的Blob SHA逐项等于主仓库对应原件；原件不经改写。它们分别涵盖**单人钱包原型、个人钱包测试、具名人口叠加测试**，以及**较早V2.3里尔社会沙盒的示例人物、规则和隔离/测试说明**。

### 不可混用的两个历史体系

- 当前第23代 Formal 经济商号使用 `person:...` 等稳定ID、现有 GameClock、Ledger、StockLots及Formal恢复机制。第86日存档已经证明一名正式经营负责人和地方交易能够随原世界恢复，但这不是独立V2.3社会沙盒的测试通过。
- 旧 `social_people.json` 使用 `character_*`、`location_*` 等早期示例ID，**不能直接当作第23代具名人物源或余额账本导入**。配套规则也不能自动作用于Formal游戏。
- `VNextPersonalWallet` 只是旧单人资金**原型代码**，不是现有Formal Ledger的替代品。不能将它当成可支付账户，也不能把同一笔钱双重结算。

### 状态与恢复

本次只完成云端源码/资料转移及SHA核对，没有启动Godot、没有运行测试，也没有从主仓库修改任何分支或源码。此目录是**独立研究夹具快照**；实际编排单人沙盒、补齐其V2.3完整服务及测试入口需在用户许可的独立工作副本里进行，不能在此默认启动。注意 `tests/` 是旧/独立测试的来源文件，不是第23代的原生验收结果。

**第23代完整依赖保存于** [经济Release](https://github.com/ryoumiyahayato/wwo-economy/releases/tag/economy-gen23-closeout-20261024)：`01-source23.tar.gz`（509个源码文件）、`02-resources23-*.tar.gz`（场景所需资源和缓存）、`03-saves.tar.gz`（用户存档）。基线恢复索引含23,379个文件路径；本轮对509个源文件中的静态 `res://` 引用解析得274个不同引用路径，全部见于基线索引。此结果是**文件层静态核对**，不构成无缓存Godot启动通过。

**主项目与经济库只进行单向、经明确许可的复制，不建立自动同步或双向编辑。**
