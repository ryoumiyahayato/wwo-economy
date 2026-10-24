# WWO经济实验室｜第23代接续基线

本仓库是 **WWO经济研究的独立仓库**，不管理、不写入也不清理 `ryoumiyahayato/wwo` 主游戏仓库的分支。

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
