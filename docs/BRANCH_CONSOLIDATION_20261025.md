# Economic Lab分支整理记录（2026-10-25）

这份记录**只涉及**私有仓库 `ryoumiyahayato/wwo-economy-lab`；不涉及 `ryoumiyahayato/wwo` 主游戏仓库。保持固定默认分支 `sandbox/main`，未创建新的开发分支，也未重写提交历史。

## 当前源码入口

- [默认分支 `sandbox/main`](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/sandbox/main) 已直接保存第23代候选 `project.godot`、`merchant/`、`scripts/`、`shaders/` 等**509个源码归档文件**。原重复51文件镜像已清除。
- [第23代已校验私有Release](https://github.com/ryoumiyahayato/wwo-economy-lab/releases/tag/economy-gen23-closeout-20261024) 保留完整源码原包、地图及地理资源、缓存、存档、历史证据。默认分支不提交数GB二进制依赖。
- 仅GitHub源码层迁移，不代表无缓存Godot导入通过；未启动本机Godot，未推进存档，未合并主WWO。

## 历史分支清理

原17个分支，已减少到6个。清理前每个要删除的分支均核对了原始SHA，并先创建且验证了 **指向同一提交SHA的历史标签**；未以强制推送重写历史。

| 旧分支 | 删除前提交 | 永久归档标签 | 结果 |
|---|---|---|---|
| `archive/controlled-workbench-before-sandbox-20261014` | [`dab110e89a4f`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/dab110e89a4ffabc2e844fcd14b31cb2008df391) | `history/economy-lab-20261025/archive/controlled-workbench-before-sandbox-20261014` | 已删分支，保留归档标签 |
| `archive/economy-goal-cycle02-20261014` | [`fd557efe1b83`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/fd557efe1b837ddde7b456651c568bb31718d10b) | `history/economy-lab-20261025/archive/economy-goal-cycle02-20261014` | 已删分支，保留归档标签 |
| `archive/economy-lab-before-sandbox-20261014` | [`48b280a37be8`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/48b280a37be8f5fd72f0c277f4ae435e675efa1f) | `history/economy-lab-20261025/archive/economy-lab-before-sandbox-20261014` | 已删分支，保留归档标签 |
| `bootstrap/economy-lab-round2` | [`95f95a7ff125`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/95f95a7ff12527c0e257854e5c79b56a3f6878a0) | `history/economy-lab-20261025/bootstrap/economy-lab-round2` | 已删分支，保留归档标签 |
| `research/demand-planning-round5` | [`0e4f529e5287`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/0e4f529e52872ee0402e91771651152ceebfe49b) | `history/economy-lab-20261025/research/demand-planning-round5` | 已删分支，保留归档标签 |
| `research/economy-goal-cycle-01` | [`c43d697ca7a1`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/c43d697ca7a1f6c90f03787fb0252fe215641514) | `history/economy-lab-20261025/research/economy-goal-cycle-01` | 已删分支，保留归档标签 |
| `research/executable-planning-round5b` | [`8550b5a5d4c1`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/8550b5a5d4c11edbe8af70f51b469d59a4c323bf) | `history/economy-lab-20261025/research/executable-planning-round5b` | 已删分支，保留归档标签 |
| `research/multi-supplier-round4b` | [`e82e7ac7fc07`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/e82e7ac7fc07389183a03137830c52d30a445bb4) | `history/economy-lab-20261025/research/multi-supplier-round4b` | 已删分支，保留归档标签 |
| `research/order-commitment-round3` | [`421249250889`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/4212492508895eff89076d661af0d926af45911b) | `history/economy-lab-20261025/research/order-commitment-round3` | 已删分支，保留归档标签 |
| `research/supplier-admission-round4a` | [`a40f3ede565f`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/a40f3ede565f0b920abc1a3a7ce23618be433654) | `history/economy-lab-20261025/research/supplier-admission-round4a` | 已删分支，保留归档标签 |
| `research/supplier-search-round4c` | [`02e654f82a76`](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/02e654f82a764589cb5b9cd4847f9b821789f2e1) | `history/economy-lab-20261025/research/supplier-search-round4c` | 已删分支，保留归档标签 |

上述标签可在 [GitHub标签页](https://github.com/ryoumiyahayato/wwo-economy-lab/tags) 浏览；每个标签仍指向原分支最后的提交，保留其可达祖先历史，不以当前第23代覆盖旧算法成果。

## 保留的6个分支及原因

| 分支 | 暂时保留的原因 |
|---|---|
| `sandbox/main` | **唯一固定默认分支和第23代当前源码** |
| `main` | 仍被未关闭PR #8、#10用作基准；旧Python数量经济线 |
| `research/multi-firm-network-round6` | PR #8提交分支、PR #9基准 |
| `research/economy-goal-cycle-02` | PR #9提交分支 |
| `sandbox/controlled-workbench-delivery` | PR #10提交分支 |
| `sandbox/algorithm-workbench-20261014` | PR #11提交分支；包含其他领域研究，不能按纯经济冗余删掉 |

未关闭PR #8、#9、#10、#11 **没有被擅自关闭或合并**，因此关联分支暂时保留；等各自原负责人明确处置PR之后，再根据用户指令归档或删除这些剩余分支。剩余6个分支不是“六个最新版”，当前最新版只有 `sandbox/main`。

## 后续管理规则

1. 不改变默认分支的名字或指向；新成果在已有 `sandbox/main` 审查和更新，不自动创建永久实验分支。
2. 需要隔离开发时允许有明确目的、短期、结束后清理的PR分支；Release和标签用于里程碑与历史归档。
3. 旧提交、标签、原实验和失败记录不删除；不使用 `force push`，不批量关闭未知来源PR。
4. Economic Lab不改主WWO分支，正式接入主游戏需用户另行明确授权。
5. 第23代目前是停工存档状态；本次操作仅为GitHub仓库整理，不代表经济线恢复开发。
