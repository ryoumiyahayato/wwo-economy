# Goal 02：来源辅助选择的真实CAD小试

**建议：停止本轮“来源窗口关联”机制扩建。** USDA7184三行施工说明的任务中，LibreCAD常规窗口、几何辅助、来源辅助均一次选对三个TEXT，错选、漏选、补选均为0。来源辅助没有减少选择或检查；扩大窗口仍会带入独立说明。没有进入第二设计运行，也没有应用内集成依据。结论只适用于本次多行TEXT任务。

## 实际任务与比较

先静态检查两页：USDA7184物理3页、NDSU ND708-1-6物理1页。均有P21-A正常BASE single.dxf、原图、正式渲染和来源记录。未使用AFTER候选、未恢复云盘文件。选择前固定任务：选中CONCRETE SLAB / REINFORCED WITH / W.W.M.三行已有可编辑TEXT，排除引线、备份轮廓、上下说明；把颜色改为ACI 2，然后撤销、保存、读回。不是移动整个图形标注。

评价身份104C/104F/1051单独写入assessment.json，仅review.py读取。selector.py不读取目标名单或预设ROI。标注和操作由AI执行者完成，**AI_QA_PROVISIONAL；无人类任务时间或工程复核**。

|方式|实际选择|错选/漏选/补选|定位后选择窗口|独立选择确认按钮|相同预设编辑与撤销|
|---|---|---|---|---|---|
|LibreCAD常规左到右窗口|3/3 TEXT|0/0/0|1|0；观察后进入属性对话框|实际变黄、撤销并保存|
|最小原型，纯几何|3/3 TEXT|0/0/0|1|1|实际DXF改色、撤销并保存|
|同一原型，加入来源|3/3 TEXT|0/0/0|1|1|实际DXF改色、撤销并保存|

全部从完整页面开始定位。LibreCAD先滚轮缩放，再用View→Window Zoom拖框；两次点角未生效、一次菜单受前台切换打断，均留在操作记录。之后一次窗口即选对，没有为改善来源成绩制造差基线。两种原型均“Zoom window按钮→拖框定位→拖框选择→检查列表并确认→改色→撤销”，各6个实际交互动作。每次检查对象均为三行；未测量真人核查时间。

原型为预设改色设置了单独按钮并附带保存。LibreCAD通过Tools→Modify→Attributes、颜色下拉、Yellow、OK执行。按钮节省属于专用操作界面，不能归因来源关联。原型日志保留AI执行者墙钟456.304秒和55.596秒，含分析和工具等待，不可用来比较效率；选择计算分别0.148/0.128毫秒，也不代表编辑劳动。

## 机制及反例

一个PySide6原型，版本source-window-v1，无机制修正。全页处理所有103个TEXT。几何方式按实际保存TEXT的LFF字形包络，来源方式按原图quad，经既有OCR_TEXT_LINE的运行内索引、原串和置信度关联同一正常DXF。两者都要求窗口完整包含包络；部分交叠列待确认并排除，靠重新框选修正。不会根据相邻、接触或相似外观扩展到引线和轮廓。选择阶段不改几何。

来源关联多提供的是“原图这行对应当前哪个已有TEXT”，没有提供“三行说明与邻近独立说明属于不同编辑意图”的关系。框选完整三行时，常规CAD和几何包络已有足够分离信息。

反例保留：把同一选择框向下扩到GRAVEL FILL，来源方式实际提出4个TEXT，误带1053一个独立说明；未确认、未编辑，一次重新框选恢复三个。相同源坐标窗口的纯几何程序对照也误带同一实体。不能把来源索引直接当说明组身份。引线穿过局部区域但不属于TEXT任务，两种原型均排除；这不认证完整图形标注归属。

## 编辑、撤销与快照身份

独立新解释器读取实际edited.dxf与undone.dxf：

- 两种原型实际修改集合均恰好104C/104F/1051，只改ACI颜色6→2。非目标完整模型空间记录和XDATA相等；撤销后全模型空间记录相等。
- LibreCAD另存读回恰好三个TEXT颜色改变，4092个顶层实体的几何及非颜色可见属性对照相等，撤销后可见记录差异0。其状态栏Selected=1797，而保存后仅三个顶层TEXT颜色改变；本轮以实际写盘实体计数，不把1797当作误选实体数。
- LibreCAD另存重新分配handle，并删除全部103个TEXT的OCR_TEXT_LINE。因此其完整来源身份未保持，不能称所有元数据不变。旧快照关联对这份实际外部保存文件返回拒绝；单独改handle、删来源XDATA的受控副本也拒绝。
- Ctrl+Shift+S实际执行Save，写到本轮initial副本。该实际文件已保留为librecad-edited.dxf；撤销保存另保留为librecad-undone.dxf，再从正常BASE还原实验initial.dxf。历史BASE从未写入。

原型背景复用既有正式渲染，不在点击改色后重绘颜色；状态栏显示写盘，实际颜色由新解释器验证。LibreCAD有实际变黄截图。没有以静态背景冒充编辑后渲染。

## 收口与证据

NDSU页只完成静态可用性检查，未运行选择或迁移。开发源的来源方案与无来源方案、常规窗口相同，缺少值得继续的增益信号，按停止条件不扩大实验。没有“独立设计成立”结论。没有改生产、FinalStructure、OCR、模型或P21-D历史结果，没有训练或哈希计算，没有提交、推送或全仓测试。执行器模型配置未核实，未开子代理。

实际范围：一个开发任务、一个邻近独立说明反例、一个最小原型；局部读回与外部快照失效检查。真人编辑效率留空。本轮建议停止该窗口关联机制；若以后研究更复杂对象，应先找到常规选择确有错选/补选成本且来源关系提供额外组信息的实际任务，再决定是否开发。不是从此任务推断所有来源辅助均无价值。

活动根：`D:/programs/Image-to-CAD/image-to-cad/instrumented-e03`。新增路径：

- `experiments/research_goal02_source_selection/`：DESIGN.md、selector.py、review.py、README_ZH.md。
- `local-artifacts/research-goal02-source-selection-20261021/`：assessment.json、outcome.json、USDA7184的实际DXF副本、选择集合、关联记录、动作日志和少量截图；NDSU708仅initial副本。
- 本报告：`docs/research-goal02-source-selection-20261021.md`。

结果根当前约22.08 MB；精确最终大小见size-summary.json。未下载资料，临时下载清理0字节。所有新增结果保留本地；未上传云盘。真实材料仍LOCAL_EVAL_ONLY。

原图与实际CAD选择同坐标视图：[来源选择](../local-artifacts/research-goal02-source-selection-20261021/USDA7184/source-01/selection.png)、[几何选择](../local-artifacts/research-goal02-source-selection-20261021/USDA7184/geometry-01/selection.png)。实际CAD编辑：[LibreCAD黄色三行](../local-artifacts/research-goal02-source-selection-20261021/ui/librecad-USDA-edited.png)。失败：[来源方式误带独立说明](../local-artifacts/research-goal02-source-selection-20261021/ui/source-counterexample.png)。全部为DIAGNOSTIC_ONLY实验副本。

**RECOMMENDATION=STOP_THIS_WINDOW_ASSOCIATION_MECHANISM；PRODUCTION_PROMOTION=NO_GO。** 完成本轮后停止，不自动开展下一轮。
