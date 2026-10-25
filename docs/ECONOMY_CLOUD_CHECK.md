# WWO Economy Cloud Check

唯一云端入口是 `.github/workflows/economy-cloud-check.yml`。只支持手动
`workflow_dispatch`，固定 `sandbox/main`，在 GitHub 托管的 Ubuntu 24.04 上运行。
所有 Action 固定提交 SHA；Token 仅有 `contents: read`，checkout 不保留凭据。
同一时刻只允许一个验证任务；quick 最长 12 分钟，Godot 模式最长 55 分钟。
不建立轮询、定时任务或后续实验。Gen23 开发仍为 STOP。

## 手动选择

在本仓库 Actions → **WWO Economy Cloud Check** → **Run workflow**：

1. 分支保持 `sandbox/main`。
2. `mode` 默认 `quick`。首次仅运行该模式。
3. 只有以后收到明确许可，才选择 `godot-import`，它可能下载数 GB。

CLI 等价操作（只执行一次，不创建自动重试）：

```sh
gh workflow run economy-cloud-check.yml --repo ryoumiyahayato/wwo-economy --ref sandbox/main -f mode=quick
```

Actions 权限、组织策略、工作流写入权限或计费限制由用户处理；该工作流不修改这些设置。
运行者执行 dispatch 需要相应权限；工作流自身的只读 Token 不用于 dispatch。

## quick 的验收边界

- 记录精确 HEAD、ref、Gen23 build 23 来源、运行链接、工具与资源统计。
- 只读取已有 Release 的附件清单、`RESTORE.md` 和小型恢复索引/校验清单。
  每个元数据附件最多 16 MiB，不下载源码/资源/存档归档。
  已读取真实 `RESTORE.md`：文件路径在 `07-restore-index.tar.gz`（3,113,196 字节）
  内的 `archive-index/CONTENTS.json`（75,531,691 字节，读取上限 128 MiB）。
  核对压缩包固定 SHA256 后，只读取该文件；不解包或读取存档。
  198,076 条总记录中，仅 23,379 条 `baseline23/` 记录可用于覆盖 Gen23 引用。
- 扫描根目录 Gen23 源码、场景、shader、配置及全局类缓存中的静态 `res://` 路径，
  检查 checkout 或恢复索引中的完整相对路径；动态路径单列，不冒充静态验证通过。
  恢复索引不可获取时结果为 `UNVERIFIED`，整个必需检查不报告 PASS。
- Node 24、Python 3.12；工作台 `npm ci`、TypeScript/生产构建、既有 Node 测试。
- Python AST 语法检查、既有 6 项 counter 桥接测试，以及
  `test_formal_economy.ObservationTests`、`test_wwo_current.MissingSourceTests`。
  不收集依赖外部原工程、Godot 或军事工程的整合测试。
- 新基础设施的测试仅验证索引解析、校验失败和安全解包等约束。

quick 不启动 Godot，不读取玩家存档，不调用 `merchant/run_global_market.gd`。
该现有脚本的 `benchmark` 包含 365 日指标运行，`coupled` 包含 30 日 Formal 推进，
均超出本轮授权。Node 示例算法的单元测试不代表 Gen23 通过。

在云环境本地复现（输出目录必须尚不存在）：

```sh
python3 -B -m unittest discover -s tools -p 'test_economy_cloud_check.py' -v
python3 -B tools/economy_cloud_check.py --mode quick --output .local/economy-check
```

缺少 Release API 访问时，会继续构建和测试，并以非零退出、保留 `UNVERIFIED`
的索引结果；不能把本地报告当作 GitHub Actions 的实际运行结果。

## godot-import 的验收边界（本轮不执行）

先通过来源、Release 清单、恢复索引和静态引用检查，才允许下载实际清单中的
`01-source23.tar.gz` 及 `02-resources23-*.tar.gz`。不下载 `03-saves.tar.gz`。
恢复索引 SHA256 固定为
`e5acd5af8324d1fd5a16cbb3309b1e4391356efb1612b35ef79ecc528d89cc58`。
源码包 SHA256 固定为历史已验证的
`ae499943bd4a79c27086003d0b3b24b3acd030b50a508fb50c5557fa9d80102a`；
资源包逐项采用 Release 的 SHA256 digest 或小型 SHA256 校验清单。没有可信校验则拒绝下载。
不重新上传现有归档。包名、布局或校验格式不符合预期时明确失败，不猜测或替换输入。

所有解包与运行在临时目录，拒绝路径逃逸、链接和特殊文件；按压缩/解压大小检查磁盘。
必须找到唯一 `project.godot`、完整 `assets/ data/ shared/`，并逐文件确认恢复的
Gen23 原始源码经归档校验后，应用当前 checkout 的受控覆盖层并记录逐文件 SHA256 差异。
第二轮以后不要求候选源码与不可变旧归档相同；旧归档、引擎版本和适配器版本检查仍保留。
若 Release 实际使用分卷拼接或不同目录布局，须先依据
真实 `RESTORE.md` 调整基础设施；现已核对恢复说明的 `baseline23/` 布局，
但本轮不下载大型资源，不能声称已完成资源恢复或引擎验证。

只从官方 Godot 4.6.3 release 下载固定 Linux x86_64 包，核对官方 SHA512，
核对实际版本 `4.6.3.stable.official.*`；绝不回退到其他版本。
使用隔离 XDG 目录，执行有时限的 headless editor import；即使退出码为零，
日志出现 `SCRIPT ERROR`、`ERROR` 或解析错误也判失败。
随后启动 headless 引擎并仅加载真实 `merchant/main.tscn` PackedScene 资源，
不实例化玩法场景、不创建世界、不推进 GameClock、不调用交易或加载第84/86日存档。
这个有限启动检查不能证明人工 GUI、完整玩法或保存世界可运行。

## 报告及后续条件

每次将 `PASS / FAILED / UNVERIFIED`、耗时、错误、工具版本及 Linux 子进程 CPU/RSS
写入 Actions Summary 和 JSON。RSS 是子进程统计，不是整台 runner 峰值或账单。
只上传小型报告和截断日志，默认保留 7 天；不上传下载包、存档、密钥、缓存或完整环境。
Artifact 上传为可选；上传失败的实际 outcome 会写入最终 Summary，不把存储故障冒充测试故障。
2026-10-25 首次运行遇到账户 Artifact storage quota 已满：保留失败记录，
不删除历史 Artifact、不改计费、不自动重试上传；Summary 和 Actions 步骤日志仍可用。
若 setup/取消/超时发生在报告生成前，Summary 明确标注检查未完成并保留 Actions 步骤日志。

个人工作台适配器仍锁定旧正式源 `b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`；
个人样本源是 `28cdc2dc37c68161dc7b3a3254692980cc75e972`。不关闭版本检查，
不将旧 Python 世界冒充 Gen23，也不把钱包原型写入 Formal Ledger。
以后适配 Gen23 应对照现有宿主的观察/命令接口和存档格式，保留原 GameClock、
Ledger、StockLots 权威，再另行授权实现与集成验证。

后续宏观冲击、30/365 日、网络性能、库存/运输/结算和人物宿主测试须单独授权；
本工作流不自动运行任何一项。

第二轮已另行获综合授权并新增 `round2-full`；结果和边界见
[第二轮综合报告](research/ROUND2_REPORT_20261025.md)。它仍只手动启动，
所有阶段复用同次资源恢复。因已知配额问题，该模式跳过 Artifact 上传。
