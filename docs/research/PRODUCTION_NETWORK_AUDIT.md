# 生产计算审查（修改前）

审查基线：`f56bc96f5b9d50b20a1573f9ed9ed5c304c829cf`，2026-10-25，唯一写入仓库 `ryoumiyahayato/wwo-economy`，默认分支 `sandbox/main`。本文件先于局部实现写成。

## 实际执行路径

`EconomySliceConfig.valid → normalize/_normalized_site → EconomyR1Slice.bind/initialize` 创建独立企业账户和站点货批。原 `SimulationStep` 推进原 `GameClock`；每日 `settle_day` 依次消息、到货与到期工资、企业计划、实际工作与工资责任、建设/服务占用劳动、生产、采购、发运、消费和后续决定。

`_plan_firms` 用本站目标库存、自己已接受订单、收到的请求、已知入库暴露、历史实际订单和规划窗口形成所需批次数。共享设备池先限制每日计划。`_allocate_production` 按活动依赖顺序，计算整数批次：

```
b = min(当日计划批次, floor(剩余已工作小时 / hours),
        floor(可用适配设备池 / capacity_units),
        各材料 floor(现场可用量 / materials[g]), 整数累计量上限)
实际产出[g] = b * outputs[g]
实际材料耗用[g] = b * materials[g]
分配生产劳动 = b * hours
```

`_material_batches` 还扣除已有订单/其他用途承诺。`_produce` 从 `EconomyStockLots.selection` 取本站的真实货批，消费具体 portion，创建输出 source/portion；成本器将输入成本和实际工资责任分配到输出。投影 `_stocks` 不是另一个可写仓库。多活动依次使用同一劳动/设备池，中间品要先实际生产才可用。

## 对八个问题的回答

1. 每批产量由活动 `outputs` 给定，旧 `recipe` 被规范为单件输出；劳动、设备、材料影响可执行批次数，不自动改变每批收率。
2. `hours` 为每批整数人时；岗位 `hours * workers` 为实际工作供给，不能把空缺岗位数当已工作时间。
3. 没有企业通用效率系数，也没有工人技能连续乘数；不同活动工时/产出可不同。岗位技能是入职门槛，已工作小时在本站共用，尚无生产活动级岗位隔离。
4. `EconomyCapitalFormation.pools` 合并开发站点基础 capacity 与已安装、ACTIVE、适配活动的资本资产能力。暂停、维护、拆装状态不能贡献设备能力；建设会消耗真实材料和劳动且有周期。设备提高批次上限，不直接倍增每批产量。基础 capacity 是开发内容声明，不能声称每台初始设备已有采购历史。
5. 材料或劳动不足减少批次，设备为0停产；没有负库存或无限补料。采购需已知卖方报价、权限、资金/预算和路线容量；订单预留资金，货权交付和付款使用原机制。工资为实际工作产生的责任，到期仅支付可用现金的部分，余款保留；现金不足也可能使原NPC拒绝招聘或新增采购，但生产本身不要求再付一遍已发生工资。
6. 改初始活动工时、材料、输出或设备能力能改变生产；现有资本形成可增加能力。没有通用技术研发、自动学习、活动版本迁移或改写已签订单的正式机制。
7. 成本器有真实投入货批成本、已发生工资（与已付工资分开）、买方到货运费、建设/维护和服务记录。期初库存成本为 UNKNOWN，联合产品需显式权重。折旧、残值、租金及通用间接费用不能随意摊成净利润；原视图是已知直接成本和有限毛贡献。真实经营现金变动也不是净利润。
8. Formal 权威是身份、地点、时钟、Ledger、StockLots、合同、权限、订单、运输和消费记录。初始现金、原料库存、配方系数、工时、能力、目标库存、工资/报价、需求和消息延迟均为开发情景参数；历史地点或线路来源不使这些经营参数变成历史测量。

## “每小时2单位粮食、无材料”

`EconomyDevelopmentConfig.multisite()` 的 `activity` 工厂函数固定 `hours=1, capacity_units=1`；其 `activity:grain` 使用 `outputs={grain:2}, materials={}`（规范为各商品0）。因此有1小时和1能力单位可执行一批，得2个开发粮食单位；其本身未计种子、水、肥料、土地、天气、季节或收获周期。它只表示该开发活动的确定性批次收率，不是农业经验参数，也不能推广至矿业、工业或运输。旧 R1 单输出 recipe 规范化为1件，与此两件批次也不同。

农业的土地、水、日照/生物周期属于天然资源/条件；种子、肥料、燃料等可交易物料属于货批投入。矿藏也不等于矿石库存。不能因没有工业中间品就认定自然投入无限。本轮合同对未实现约束保留 UNAVAILABLE；有限开仓粮食/煤矿库存是开局禀赋，不是无限农业/采矿生产。

## Round6 审查与适配决定

只读历史分支 HEAD `334d3f546824415604b7645a91a61196fb2bad83`，`economy_quantity_lab/network_round6/{firm_network,network_simulation,network_fixtures}.py` 及综合报告。FirmNode 的 inventories 引用旧数量 Simulation.stock，RecipeGraph、局部请求、已知供应商、StockCommitments 和 TransportSlots 支持共享稀缺及实际运输延迟；不存在 Formal Ledger、价格/资金可支付性、工资责任、正式财产权或授权。所以28/55节点不计为20家正式企业。

逐项适配：稳定节点ID→Formal firm/site；数量表→唯一 StockLots；采购请求→原 buy admission；commitments→原订单和货批预留；槽/lead→原路线及 shipment/receipt；计划→原 `_plan_firms`；局部知识→原 information 接收。数量轨迹、资金、历史数据结构不合并，旧分支不改写、不执行或迁移。

## 本轮局部实现范围

在既有活动上增加可选 process 合同：批次与单位、来源/估计性质、正常产出/不合格品、工艺ID、周期及批次上限、活动级劳动/天然资源/设备等尚未支持约束的显式不可用状态。净合格输出继续由原 outputs 执行，材料和工资继续原路径。不是第二套生产器。旧活动保持原行为，并在接口标记 LEGACY_UNSPECIFIED。有限代表为食品加工、纺织、煤铁钢和工具；农业/采矿的自然再生产不冒称已实现。
