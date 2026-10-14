# WWO Algorithm Sandbox

独立、可复现的**控制变量功能实验台**。在测试边界之外，把供应、运输、资金、路径或补给设为理想依赖，逐步检查算法是否实现实验作者的预期。运行成功不等于功能正确，demo 通过也不代表任何私人项目算法有效。

公开代码完全原创；公开运行不需要私人项目、密钥、账号、付费服务或地理资产。这里不包含 WWO 私有代码、历史、地图、真实业务数据或当前算法快照。

## 启动

需要 Node.js 22.12+（已在 Node 24 验证）。

```sh
npm ci
npm run dev
# http://127.0.0.1:5173
```

生产构建也可在本机运行，无公开部署：

```sh
npm run build
python3 bridge/server.py
# http://127.0.0.1:8787，公开 demos 仍在浏览器执行
```

默认只绑定 loopback。不要将带私有适配器的桥接服务公开部署。

## 怎么检查一个实验

1. 选择经济 / 军事及实验模板；声明被测边界。
2. 编辑条件与**独立预期配置**。预期由实验作者给定，算法输出不会反写预期。
3. 点击“应用条件并重置”；固定种子后单步、开始 / 暂停或重置。
4. 逐项查看预期 / 实际 / 差异、阶段因果链、单步变化、真实事件和阻塞原因；按订单 / 单位 ID 追踪。
5. 使用 A/B 对照，仅改变一个外部条件（或明确选定的参数）。种子、算法版本、其余配置和预期保持相同。
6. 导出场景、结果或完整 A/B 结果；导入结果只回放，重新运行必须有相应适配器，绝不静默换成 demo。

JSON 都有版本：`wwo-sandbox/scenario/v1`、`result/v1`、`comparison/v1`、`terrain/v1`。结果包含完整历史、事件、种子、输入、适配器版本与独立规则。导入时重新计算判定，不能用被篡改的“通过”标签覆盖观测证据。

“每一步”规则检查所有已观察状态，显示首个失败值；deadline 规则在指定 tick 判定。未提供的指标 / 未定义的规则显示**待判断**。价格是否收敛、行为是否合理等留给人工解释，默认不宣称平衡或所有订单必须成交。

## 已实现的合成实验

| 实验            | 真正执行的功能                                                                     | 默认预期 / 反例                                                                                    |
| --------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 经济市场循环    | 需求生成 → FIFO 匹配 → 固定挂牌价分配 → 托管 → 收货结算 / 货损退款 → 消费 → 下一轮 | 第3轮消费至少30、未满足需求0，资金 / 商品 / 订单残差0。零初始资金+有限资金策略，显示不符与资金阻塞 |
| 经济库存        | 真实库存扣减与订单分配，有限来源                                                   | 供应不被理想替身补满；零库存会阻塞                                                                 |
| 经济运输        | 容量、时延、逐单位随机货损、到货结算                                               | 在途与托管按真实时延变化；货损退款但 demo **不实现补运**，保留未满足需求                           |
| 军事移动        | 一个抽象编制单位，按真实速度逐步推进位置                                           | 10 ticks 内到达位置10；零速度保留原预期并显示不符；路径阻断不制造成功移动                          |
| 军事交火 / 弹药 | 位置、逐发固定种子抽样、弹药扣减、双方伤亡与结果                                   | 不保证命中或获胜；有限弹药边界不能按需补给；hitChance=0不可能造成目标伤亡                          |

这些都是 **demo.economy.v1 / demo.military.v1 原创示范算法**。固定挂牌价不是价格发现，运输退款不是完整补运体系，抽象编制不是单兵或现实作战优化。独立预期故意不符使用原创零资金 / 零速度 fixture，不修改私有算法。

经济资金核对：`initialFunds + externalFunds = buyerCash + sellerCash + escrow`。
商品核对：`initialGoods + externalGoods = supplierStock + buyerInventory + inTransit + consumed + lost`。
订单核对：`requested = pending + inTransit + delivered + lost`（delivered 包含已消费部分）。
军事核对：`initialAmmo + injectedAmmo = remainingAmmo + firedShots`；双方初始人数 = 当前人数 + 实际伤亡。

## 外部依赖与控制变量矩阵

这是通用实验契约；具体私有算法依赖需由对应版本的适配器声明。用户明确要求先理想化边界外库存 / 运输 / 其他依赖；资金、路径、补给等是可配置设计假设，正式新版职责尚待版本接口确认。

| 环境依赖                  | 缺乏时的表现            | 理想策略                                         | 必须由被测代码决定                                     | 恢复一个约束         |
| ------------------------- | ----------------------- | ------------------------------------------------ | ------------------------------------------------------ | -------------------- |
| 来源商品                  | 无候选余量、无订单分配  | **供应侧**按有限请求补货并记账；不直接满足需求方 | 匹配、分配、库存扣减；库存被测时不补货                 | `supply: finite`     |
| 资金                      | 无支付 / 托管、订单停留 | 按需提供有限金额，保留来源注入                   | 价格 / 可购买数量 / 托管 / 结算 / 退款（若属于职责）   | `funding: finite`    |
| 运输                      | 等容量、在途不消失      | 外部即时且足额分配，零时延有明确记录             | 内部请求 / 最终收货 / 物资账；运输被测时保持容量和时延 | `transport: bounded` |
| 路径 / 许可               | 无路或非法目标          | 提供合法可通行路径                               | 实际移动 / 坐标 / 行动完成条件                         | `path: blocked`      |
| 弹药 / 补给               | 无射击、行动能力下降    | 按有限需求提供并记录                             | 每发扣减、命中、伤亡；弹药被测时不注入                 | `resupply: finite`   |
| 拓扑 / 商品目录 / 实体 ID | 配置失败、非法输入      | 小型合法 fixture、稳定 ID                        | 输入校验、实际规则执行                                 | 一个非法项，预期拒绝 |
| 时钟与调用边界            | 无进展、重复副作用      | 每次恰好推进1tick、重复请求拒绝                  | 实际 step / settle / action 的转移                     | 重复 / 乱序请求验证  |
| 地形 / 仓储 / 税 / 季节等 | 与预期外部条件混淆      | 声明固定值 / 足够余量，来源与单位清楚            | 被测地形 / 配方 / 限制规则不替换                       | 每次只恢复一个条件   |

默认不会向余额、库存或 JSON 写入 `Infinity`，也不会通过把移动、成交、命中或消费直接设为成功来“验证”这些功能。测试边界编辑器锁定内部库存 / 运输 / 弹药的对应策略；矛盾 JSON 会被拒绝。

## 架构与私有算法接入

```text
场景 + 独立预期  ──> Run（版本、连续tick、固定配置）
                         │
               AlgorithmAdapter v1
                 ├─ 浏览器内原创 demo
                 └─ loopback bridge ──> 私有目录中的 provider ──> 真实算法
                         │
             原始观测 snapshot / events
                         │
            独立检查器 ──> 预期/实际/差异、回放与导出
```

适配器规范在 [src/core/types.ts](src/core/types.ts)。`metadata` 必须声明协议版本、ID、真实 sourceRef、版本、domain、`kind: demo/private`、参数、测试边界与默认场景。`create(scenario)` 返回初始 tick0 与 session；`step()` 每次返回恰好下一个 tick；`close()` 清理会话。适配器只转换输入、调用算法、推进时间和读取状态，不替算法计算成交或行动。外部替身应在可替换依赖的边界实现，不能侵入被测机制。

Python桥接入口 [bridge/server.py](bridge/server.py) 使用标准库，无需 pip。插件协议：`get_adapters() -> {id: provider}`；provider 提供 JSON `metadata` 与 `create(scenario)`；session 提供 `snapshot()` / `step()` / 可选 `close()`。公开 [bridge/example_adapter.py](bridge/example_adapter.py) 是独立 counter fixture，验证协议，**不是市场算法**：

```sh
SANDBOX_ADAPTER_PATH="$PWD/bridge/example_adapter.py" python3 bridge/server.py
```

真实插件应放在独立私有目录，使用绝对路径加载；公开仓库只保存接口，不复制真实模型和 fixture。启动桥接后点击“连接本地私有适配器”。所有调用来自已登记 ID；导入 JSON 不能指定任意 Python 路径。`expectedTick` 防止重试造成重复扣款，失败的 plugin 调用可能已改变状态时，桥接丢弃会话而不重试。

若真实模型不拥有资金、价格或单兵命中，不要用适配器补一套计算；省略相应观测，规则显示“待判断”。旧版适配必须注明历史版本，不能冒充未提交的新版。本公开版未接入当前 WWO。

## 法国500公里地形与兵模扩展

确认的平面方块：EPSG:2154 Lambert-93，`[650000,6150000,1150000,6650000]`米。共同西南原点；5km→100×100，25km→20×20，50km→10×10，严格从同一基础格聚合。经纬包络不是方形；投影500km不是椭球面上的精确500km。包括法国东南主体和相邻国家，不能理解为法国政治边界。

军事界面提供层级切换、格子检查和聚合残差。数据与高度/坐标单位、DSM/DTM、来源、许可、采样方式独立记录；河网保留矢量结构，不以粗格多数地类推导桥通行。代码 `terrain/v1` 保留同源显示 / 输入的接口。**当前 demo 尚未消费地形，界面显式显示未接入**。

交付时 AWS COG请求被执行环境代理以 `CONNECT 403` 阻挡，故默认真实高度 / 地类都是未知，没有把 nodata 画成海或生成虚构山脉。导入合法区域数据后即可检查；不会自动下载全球，也没有购买地图服务。

本地导入工具只读取用户已有的必要区域栅格 / GeoJSON：

```sh
python3 -m venv .local/geo-venv
.local/geo-venv/bin/pip install -r tools/terrain-requirements.txt
.local/geo-venv/bin/python tools/import_terrain.py \
  --dem /private/maps/regional-dem.tif \
  --cover /private/maps/regional-worldcover.tif \
  --rivers /private/maps/regional-rivers.geojson \
  --cities /private/maps/regional-cities.geojson \
  --sources /private/maps/source-notices.json \
  --output results/france-terrain.json
```

`--dem` / `--cover` 可重复；河与城市必须是EPSG:4326 GeoJSON，工具裁剪到该方块并投影。源清单是包含 `title/url/license/attribution` 的 JSON 数组；输出每个输入的 SHA-256 和投影包络。5km高度是格中心采样，粗层平均只是这些样本平均，不是完整细节地形。水类没有外部海岸证据时保持“water”，不能推定海深。现代 WorldCover 城市覆盖不代表1900城市或建筑；DSM不是裸地、掩体或单兵弹道。

原创可复用兵模标记 [src/presentation/UnitMarker.tsx](src/presentation/UnitMarker.tsx) 绑定真实实体ID；一个标记代表适配器的一支单位，位置来自snapshot。插值默认关闭，只作用显示；不会播放与状态无关的成功动画。当前是精确平面检查视图，没有3D编辑器。

建议公开数据来源与数据许可独立于代码许可：

- [Copernicus DEM / AWS](https://registry.opendata.aws/copernicus-dem/) — GLO-30公共DSM；[单独许可](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf)，实际派生数据须保留第6条署名与责任声明。
- [ESA WorldCover](https://esa-worldcover.org/en/data-access) — 2021 v200、CC BY4.0；实际派生图须按来源页署名。公开版没有包含这些栅格。

## 验证

```sh
npm run build
npm test
python3 -m unittest discover -s tests -p 'test_*.py'
```

核心测试覆盖预期通过与故意不符、资金/商品/订单/弹药/人数守恒、实际到货时延和退款、固定种子回放、重置、未知预期、协议异常、结果导入以及5/25/50km聚合一致。桥接测试包含真实插件调用和重复tick拒绝。浏览器走查另行验证开始/暂停/单步/重置、文件往返、对照、经济/军事实际变化、移动端布局和console错误。

界面只做局部实验，千tick上限与内存会话适合功能检查；不证明世界规模性能、不提供持久数据库、完整WWO或真实作战建议。
