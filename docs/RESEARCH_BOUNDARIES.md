# 当前研究边界

Round2历史基线仍由`BASELINE.md`和`docs/source_manifest.json`定义。156个来源
文件及139个输出的校验政策不变；`economy-lab-v0.2-baseline`指向实际合并main
`60278ee7f1703ef5aec6cb7933a2bcf6073e1038`。

Round3仅在`economy_quantity_lab/order_round3/`增加明确承诺、派生promise_status、
可信供给过滤与即时接受的未发余额取消实验。固定target320、时延2、buffer2。
不修改原Simulation、生产、运输、fixture、H0/H1或Round2结果。

R0保留事实账采购；R1只过滤决策；R2在原B采购边界取消逾期未发余额，再向同一个
供应商FIFO尾部新订。真实订单恒等式增加cancelled，商品账不计取消。C steel规则
保持原样，其承诺仅观察。没有实现合同协商或异步取消确认。

实际14×600日结果并未改善物质服务。持续停运R1队列551张、未发58720；R2累计
取消58400、期末未发320，却同样停产。R1/R2均未获准作为正式规则。

详见`economy_quantity_lab/order_round3/ORDER_COMMITMENT_REPORT.md`。进入完整
多供应商发现/切换前，需要明确已知可履约候选、拒单/承诺数量、取消确认和旧在途
去重语义。未实现任何第二供应商、资金/价格/金融或WWO运行时集成；不自动开展Round4。
