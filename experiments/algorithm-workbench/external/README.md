# External WWO adapters

This directory contains input/call/observation wrappers only. It contains no
real simulation implementation, private fixture, historical result or data set.
The sandbox itself remains runnable without WWO using explicitly labelled demos.

## 已接通的最小真实入口

- 经济 `private.wwo.programme.v1`：外部 WWO `integration/formal-economy-20261014`，固定 `b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`。直接调用 `research/economy/fifteen-algorithms/economy_quantity_lab/algorithm_completion/world.py` 的 `ProgrammeWorld.step()` / `snapshot()`。依赖 Python 3.12 标准库和原相对模块布局。
- 军事 `private.wwo.military.v5`：外部 WWO `backup/military-person-attachment-20261014-v1`，固定 `04ab3cc9ffb2233fa0ab5290e0ec0a952f229630`。原 `interactive_observer/client.py` 的 `Connection` 调用原 Godot `attachment_continuity/server.gd`。依赖 Python 标准库、Godot 4.6.3 和该外部 WWO 项目。

经济是十五算法 **Python 研究世界**；没有因此接通正式 GDScript，也未验证新增50日贷款/拖欠/劳动退出/清算场景。军事是云端 **v5** 最小人物入口，不是本机未提交 v6，也不代表全功能验证。接入前读取 WWO 默认分支为 `0e965225cc0632024348b38fb1152124534903aa`，最终读取已由其他工作推进到 `788b99d2e717a65f2922a78226a334f998922f64`。两个实际接入源提交均未变化；本实验没有修改或合并 WWO 分支。

## 两个真实源的启动

不要切换或覆盖已有未提交工作树。使用两个版本匹配的外部检出。从 `experiments/algorithm-workbench/`：

```sh
npm ci
npm run build
WWO_ECONOMY_REPO_PATH=/absolute/path/to/wwo-at-b5bfcdd \
WWO_MILITARY_REPO_PATH=/absolute/path/to/wwo-at-04ab3cc \
WWO_GODOT_BIN=/usr/local/bin/godot \
SANDBOX_ADAPTER_PATH="$PWD/external/wwo_current.py" \
python3 bridge/server.py
# http://127.0.0.1:8787
```

点击“加载 / 刷新真实算法”，选择 PRIVATE 和正常/故意不符模板，再应用并重置。未配路径、缺入口、版本不符、源未提交修改或引擎错误会显示未就绪/错误，不回退 demo；一个源缺失不会阻止登记另一适配器。调整路径后重启桥接并刷新。JSON 场景不能指定任意源码路径。

每项实验拥有独立 Python 工作进程和真实实例。军事进程的 Godot 数据/配置/缓存放在沙盒根部 `.local/algorithm-workbench/godot/`，解决云端用户目录不可写的问题；原 WWO 源码不变，工作进程只终止自己的子进程。

## 最小输入和反例

经济初始条件二选一：`{"fixture":"J1_normal"}`、`{"fixture":"J3_shortage"}`，或 `{"case":完整用户研究配置}`。fixture 从外部源码读取，没有复制配置进沙盒。`maxTicks` 控制研究日数；状态读取原 needs、现金账、库存、在途和订单。满足量是原食物满意度单位；余额合计未换算多币种，解释时看源现金分类。模型未暴露 RNG，种子只是实验记录，界面明确说明。

正常与短缺例保留同一预期：第3日累计满足量至少18、未满足量0。短缺仍先消耗初始储备，检查器到第3日检出不足。没有把输出反写为预期，也没有替原算法制造消费。

军事当前仅接通 A3 / squad。默认 `{"scene":"A3","actor":"squad","commands":[]}` 等待玩家下令；另保留带 `intent sandbox_move node_unit_000 advance B AB` 的自动正例和无意图反例。初始 commands 是最多8条原 intent 命令。运行中前进/驻守/撤回/取消通过原 `Connection.send("intent", request)`，目标和路径来自 PERSON_VISIBLE。原权限、机会、冷却、送达和执行规则不变；界面显示原回执、拒绝原因和推进后的实际后果，受理不等于完成。每步游戏秒1–300，配额只能0/1/7/31，总时间不超过原86400秒上限。反例保留人物应前进的预期；原位置不变时检查器报不符。

市场入口没有提供本实验可调用的玩家交易 API，因此只读展示原日循环。订单、在途、收货、库存、消费和付款取自源观察；不造一个沙盒交易来冒充原算法。

一个 tick 是完整请求区间；原 PENDING 保留上次提交状态，后续单步/定时调用续接同一目标。位置和健康来自原 PERSON_VISIBLE；事件、回执和报告仅用原合法视图。精确弹药、全军伤亡和守恒量未上报时保持缺失。事件页最多20条，页游标和截断信息保留在源 JSON，不宣称完整战争日志。原坐标为抽象道路世界的 km，没有地理投影声明，不放入法国地块。

两种 PRIVATE 闭环均未注入理想替身；目标依赖锁定为原约束，不创造资金、满足需求、瞬移、结算伤害或制造成功。demo 单独标记，其理想化策略不会作用于 PRIVATE 实例。

## 保存、失败和局部检查

场景保存初始条件与独立预期，结果保存源版本、已提交观测，以及运行中命令的 tick/请求/原回执。加载结果只读；重新运行创建同版本原实例，在对应 tick 重发相同命令并逐步比较。结果不是 Godot 内部游标 checkpoint。包装器版本 `scene-calls-v2+源提交` 与旧结果明确区分。

缺初始数据保留上一有效状态。执行报错后丢弃可能已改变的实例，界面保留最后有效快照；幂等关闭已丢弃会话后，重置可创建新实例。源没提供的订单损耗/状态枚举保持缺失，不补0，也不默认判通过。

```sh
WWO_ECONOMY_REPO_PATH=/absolute/path/to/wwo-at-b5bfcdd \
WWO_MILITARY_REPO_PATH=/absolute/path/to/wwo-at-04ab3cc \
WWO_GODOT_BIN=/usr/local/bin/godot \
python3 -B -m unittest discover -s external -p 'test_wwo_current.py'
```

只做所需步进、复现、正常/不符、PENDING、缺数据、错配额和不可用源检查。不执行旧矩阵、全仓门禁、内容哈希或大证据包。

## 可选历史数量 adapter

`wwo_quantity.py` reads an external WWO checkout, calls its original
`research/economy-lab-20261007/economy_quantity_lab/economy.py` implementation,
and reads the external fixture. It has no fallback to an algorithm inside Lab.

Use a separate WWO worktree on `research/economy-lab-migration-20261014`, commit
`07deb15e2ad4e75e5feead00621893e53eaf7c8a`. Do not switch or modify another
active/uncommitted WWO worktree. From `experiments/algorithm-workbench/`:

```sh
WWO_REPO_PATH=/absolute/path/to/separate-wwo-checkout \
SANDBOX_ADAPTER_PATH="$PWD/external/wwo_quantity.py" \
python3 bridge/server.py
```

Run the web app separately from this experiment directory, then connect the local
private adapter and select `private.wwo.quantity.v1`. Only the historical model's
actual observations are supplied. Missing wallets/prices remain unavailable.
Seed is recorded but this deterministic quantity model has no RNG. Source Git
commit is recorded; uncommitted research changes are
rejected for this historical adapter.

```sh
WWO_REPO_PATH=/absolute/path/to/separate-wwo-checkout \
python3 -m unittest discover -s external -p 'test_*.py'
```
