# Economy Goal 01 已授权研究发布索引

[Cycle01 完整报告](../economy_quantity_lab/goal_cycle01/REPORT.md)、[研究入口](../economy_quantity_lab/goal_cycle01/README.md)

## 发布与封存身份

用户于 2026-10-08 明确授权同步已完成经济与军事算法研究及未来游戏接入直接相关材料。此分支只新增恢复/发布索引。原封存状态文件中“未 push / 未授权发布”等描述保留为历史记录，未被覆写。

- LOCAL_SEALED_HEAD：93633b4321dc288bd14b064350cc7fb053529bae
- REMOTE_PUBLICATION_COMMIT：[封存树等价快照](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/3ffa0f5c4b368f290622d93eca8e83806c3e0610)
- 原封存 tree：9e3b740c0817bf8090b811f2e14c18423da6e271
- 456 个原文件的路径、mode 和 Git blob 字节完全相同；整棵 tree SHA 精确一致
- 本分支 HEAD 是随后增加 publication/ 目录的索引提交，其父提交为上述等价快照

正常 Git 传输没有可用认证；此次使用已连接 GitHub 的原生 Git 对象工具生成新 publication commit。新提交具有新元数据，不能把它称为原 local sealed HEAD 的上传。真实原提交身份与所需对象仍在 Library 完整恢复包中。完整原文件索引见 [SEALED_TREE_FILES.json](SEALED_TREE_FILES.json)，关系与发布范围见 [PUBLICATION_MANIFEST.json](PUBLICATION_MANIFEST.json)。

## 完整恢复

archive_index/CYCLE01_LIBRARY_ARCHIVE.json 给出原始完整包 WWO_Economy_Goal_Cycle01.zip 的 Library 身份、30,775,867 字节大小及 SHA-256。先在自己的 Library 保存该准确文件并核对 SHA，再解压查看 source/ 与 handoff/。

原 bundle 与 patch 都依赖真实 Round6 BASE 334d3f546824415604b7645a91a61196fb2bad83，原始依赖/哈希和实际恢复验收见 archive_index/original_export_manifest.json 与 original_local_export_checks.json。bundle 不是独立克隆；patch 只应用一次。

若需要不依赖远端下载的完整 Git 对象恢复，可使用 Cycle02 的 Source_Restore.zip（Library ID libfile_84147cfbf6e08191ba3f16108f8d622d，SHA-256 885668981df71846514a94173141acdb58df68efd7d77b9261f05626b561f707，5,859,120 字节）。它包含真实 Cycle01 与 Cycle02 的所需对象及明确 Round6 shallow 边界。原 Cycle01 完整档案也被 Cycle02 的完整 raw 恢复集保留。不能用小阅读包替代完整源/证据恢复。

Cycle01 的原 353 文件冻结经济结果及原失败证据均保留。发布未复跑、未改变原结果。

## 未来游戏接入的审查入口

继续审查单一经济/订单/物资结算权威、Cycle01 的支付/排序/局部价格反馈、Cycle02 的因果审计与唯一受限 N4 候选，以及报告记录的愿付振荡、sink 服务转移、缓存增长和模型限制。源代码、冻结配置、反例与原报告全部同树保留。

本次没有修改 main、创建 PR、merge、tag、生产部署、正式 WWO 接入或开启下一研究周期。数据均来自 [冻结人工模拟](SYNTHETIC_DATA_SCOPE.md)。远端 CI 未被此索引声称通过；最终交付另核对当前 commit 的 run/check/status。
