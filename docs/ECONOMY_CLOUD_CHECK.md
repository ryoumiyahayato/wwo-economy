# WWO Economy Cloud Check

唯一云端入口是 `.github/workflows/economy-cloud-check.yml`。只支持手动
`workflow_dispatch`，固定 `sandbox/main`，在 GitHub 托管的 Ubuntu 24.04 上运行。
所有 Action 固定提交 SHA；Token 仅有 `contents: read`，checkout 不保留凭据。
同一时刻只允许一个验证任务；quick 最长 12 分钟，godot-import 最长 40 分钟。
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
  每个元数据附件最多 16 MiB，索引合计最多 64 MiB，不下载源码/资源/存档归档。
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
源码包 SHA256 固定为历史已验证的
`ae499943bd4a79c27086003d0b3b24b3acd030b50a508fb50c5557fa9d80102a`；
资源包逐项采用 Release 的 SHA256 digest 或小型 SHA256 校验清单。没有可信校验则拒绝下载。
不重新上传现有归档。包名、布局或校验格式不符合预期时明确失败，不猜测或替换输入。

所有解包与运行在临时目录，拒绝路径逃逸、链接和特殊文件；按压缩/解压大小检查磁盘。
必须找到唯一 `project.godot`、完整 `assets/ data/ shared/`，并逐文件确认恢复的
Gen23 源码与 checkout 一致。若 Release 实际使用分卷拼接或不同目录布局，须先依据
真实 `RESTORE.md` 调整基础设施；当前没有读取到该 Release，不能声称已验证恢复。

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
若 setup/取消/超时发生在报告生成前，Summary 明确标注检查未完成并保留 Actions 步骤日志。

个人工作台适配器仍锁定旧正式源 `b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`；
个人样本源是 `28cdc2dc37c68161dc7b3a3254692980cc75e972`。不关闭版本检查，
不将旧 Python 世界冒充 Gen23，也不把钱包原型写入 Formal Ledger。
以后适配 Gen23 应对照现有宿主的观察/命令接口和存档格式，保留原 GameClock、
Ledger、StockLots 权威，再另行授权实现与集成验证。

后续宏观冲击、30/365 日、网络性能、库存/运输/结算和人物宿主测试须单独授权；
本工作流不自动运行任何一项。
