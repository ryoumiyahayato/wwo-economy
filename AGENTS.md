# Economic Lab 守则

- **只修改本仓库 `ryoumiyahayato/wwo-economy-lab`。** 不修改、合并、删除、迁移或清理 `ryoumiyahayato/wwo` 主项目的分支与文件。
- **固定默认分支 `sandbox/main`。** 不以日期命名新默认分支，不自动切换默认分支，不把每轮经济实验变成新的永久分支。
- 当前接续版本为已归档的第23代，源码在仓库根目录；地图、数据、导入缓存、存档和历史报告保存在 `economy-gen23-closeout-20261024` Release。
- 原正式WorldState、GameClock、Ledger、StockLots、订单、运输和权限是既有共享权威；经济实验不创建第二份可支配世界库存、可支付资金或独立GameClock。
- 只对用户明确指定的经济任务施工。停止状态下不得自行运行Godot、模拟或GUI；本机高负载资源须经用户明确调度。
- 旧Python研究分支、历史标签与开放PR属于历史资产。归档前确认提交与PR归属；删除分支前先保存不可变的明确归档引用。不得force push、重写历史、擅自关闭开放PR。
- 大型地图依赖、玩家存档、缓存、证据和日志不提交到Git默认分支。里程碑保存在带恢复说明的Release中。
- 不自动建立任务轮询、持续CI协调或定时唤醒。一次性归档工作流完成后删除。
- 执行和报告区分已验证、CONDITIONAL、UNVERIFIED、FAILED，不能用宏观估计成交冒充正式货款和实物交付。
