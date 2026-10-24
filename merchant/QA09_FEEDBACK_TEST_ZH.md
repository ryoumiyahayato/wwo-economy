# 0.9隔离反馈验证脚本

`qa09_feedback.gd` 只使用独立候选世界与合法玩家动作，不启动GUI、不改写用户存档，也不替NPC调用首次采购/报价决定。

由统筹者使用Godot 4.6.3运行：

```
godot --headless --path <candidate> --script res://merchant/qa09_feedback.gd -- /tmp/qa09_feedback_report.json /workspace/shared/economy_08_opportunities/verified_manual/day6_slot4.json
```

- 同一exact snapshot恢复A/B；A合法买8粮，只接受首次可见最小粮采购并供货；B不做玩家经营动作。并行自然推进8日。
- A再连续推进30日。仅在自由库存<3、无在途采购、可用现金≥30时尝试4粮采购，最多再4次；最多接受4项自然出现的粮采购。NPC只由正式时间推进触发。
- 每日记录真实买方库存、`_input_need`、生产计划、公开/已知报价、原订单、运输任务、收据、NPC订单及决策依据、商号现金、合同、只读反馈。
- 每笔采购/接单/供货，以及选定日边界和持续经营每5日，候选恢复后逐项比较economy_native、ledger、clock与派生观察。候选恢复不改变活世界或生成新NPC订单。
- 重放每个玩家动作并验证结果、整个世界snapshot不变；检查公开反馈纯读、返回值脱离、未知人/跨企业无权；若观察到未送达公告，合法尝试接单必须被拒绝。
- NPC销量与到货观察独立从4日原收据重算；校验window4、cooldown2、target3..12。
- 供货因果证据使用原订单→收据→acquisition_id货批→生产inputs.portion_id精确引用，并附货款Ledger交易。不会因同一天生产就归因于玩家。
- 真实0.8第四槽通过merchant_save读取，恢复必须保持economy_native/ledger精确；损坏receipts候选应被拒绝且活世界不变。
- 默认JSON含完整每日取样，日志仅输出摘要；JSON `untriggered`明确记录未自然触发项。

脚本交付时未在本子任务启动引擎。最终通过/失败以统筹统一运行日志及JSON为准。仍应同时运行原QA08 information/integrity等负向专项；本脚本不以有限样本声称覆盖所有未来责任组合。

## 静态审计追加

- 验证旧收据仅有delivered_day=3时，原_delivery_minute返回4320。
- 从已送达notice原terms逐项检查历史事件，完全不借用实时views/need/cash决定预期。超过12条时只强制比当前截断边界更新的公告；并列边界与更旧项如实记录为不强制，避免误判排序截断。出现的公告必须保留原数量、原单价和真实送达日期。
- 性能拆分advance_only_ms（严格只包围advance_minutes）和advance_and_player_ms（含合法玩家动作及其内部核验，但不含当日observe取样）。不要把后者当作纯世界推进耗时。
