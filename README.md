# WWO Economy Lab

独立的 WWO 经济数量模型与算法研究仓库。Round2已成为可复现研究基线；
Round3已合并，当前研究分支开展Round4A供应商准入与取消确认。原算法、fixture、报告和
Round2实验结果保持不变。

基线标识：`inventory-round2-2026-10-07`。来源和限制见
[BASELINE.md](BASELINE.md)，全部 156 个来源文件的 SHA-256 见
[source_manifest.json](docs/source_manifest.json)。

## 安装与完整验证

只需要 Python 3.12 和标准库，无第三方依赖。已在 Windows Python 3.12.14
运行；GitHub Actions 使用 Ubuntu 和 Python 3.12。

```sh
git clone https://github.com/ryoumiyahayato/wwo-economy-lab.git
cd wwo-economy-lab
python verify_baseline.py
python verify_round3.py
# Round4A研究分支新增完整验证。
git switch research/supplier-admission-round4a
python verify_round4a.py
```

统一入口协调既有命令，运行原 8 项测试、新 9 项测试、两组 200 日原实验、
全部 33 组 600 日对照，检查来源和全部 139 份输出的 SHA-256 与文件集合。
输出 Python 版本、基线标识、状态、summary hash，并以非零退出码报告失败。
每次运行保留到新的 `.local/verification-*` 目录，包含原始输出、日志及
`verification.json`；不会覆盖来源证据。可指定 `--output-dir artifacts`。

原 runner 用平台默认文本模式写 JSON。Windows 产生 CRLF，来源是 LF；统一
入口仅在 Windows 对生成 JSON 的 CRLF→LF 字节进行额外哈希比较，保留原始
文件和原始哈希，并明确报告哪些文件不是直接字节匹配。CSV 不做任何转换。
`--strict-bytes` 禁止此兼容比较；Linux CI 使用该参数，要求所有输出直接
逐字节匹配。原始 CSV 自带 CRLF，其 Git 路径例外防止自动转换破坏既有哈希。

## 原有入口

以下命令在仓库根目录开始，`python3` 也可替代 `python`。

```sh
cd economy_quantity_lab
python -m unittest -v test_economy.py
python run_experiment.py --output-dir ../artifacts/baseline
cd inventory_round2
python -m unittest -v test_inventory_comparison.py
python run_inventory_comparison.py --output-dir ../../artifacts/round2 --execution-log ../../artifacts/round2_execution_log.json
```

原打包脚本仍保留，可以在各自目录运行 `python package_experiment.py` 或
`python package_inventory_comparison.py`。后者在原始 LF JSON 的 Windows
检出上会严格拒绝 JSON 换行差异；需要完整包的严格复现时使用 Linux，或使用
统一入口查看明确区分原始与换行兼容结果的报告。不要修改原脚本来掩盖差异。

## 研究证据与边界

源码和 import 关系保持来源布局。两份历史报告原样保留：
[原 200 日报告](economy_quantity_lab/REPORT.md)、
[Round2 600 日报告](economy_quantity_lab/inventory_round2/INVENTORY_COMPARISON_REPORT.md)。
本轮保留全部 9,129,147 字节、156 个来源文件，包括原四份 CSV 和 Round2 的
135 份结果，因为既有严格打包验证依赖完整树。后续运行放在忽略目录；CI 将
完整再生输出作为有期限的 Actions artifact 上传，不逐轮提交 ZIP 或大量 CSV。

CI 证明当前提交仍可复现已声明行为。数量残差为零是账目一致性证据，不能证明
模型真实性。H0 固定目标、H1 时延相关目标、buffer 对照与 coverage diagnostic
均属有限实验；诊断只读，H1 尚未批准为 WWO 正式经济规则。

原Round2长期未发订单没有处置机制；后续Round3/4A分别研究取消与确认。
转单、多供应商、价格、工资、家庭、金融均未实现。这里不复制 WWO UI、Globe、人物、政治、军事、SaveGame、GameClock、
完整历史库或正式世界模拟，也不自动整合到 WWO。

PR #1已按明确授权合并，annotated tag `economy-lab-v0.2-baseline`指向实际main
`60278ee7f1703ef5aec6cb7933a2bcf6073e1038`。历史导入结论仍保留于BASELINE。

## Round3订单承诺与处置

新增实验位于`economy_quantity_lab/order_round3/`。四个供给场景分别运行R0/R1/R2，
另加两个无承诺R1控制，共14×600日。18项新增检查、两次完整59文件字节复现及
旧基线验证由CI实际执行。运行`python verify_round3.py`前也运行旧验证。

R1只排除可信供给中的逾期余额；R2显式取消未发余额，再向原供应商FIFO尾部新订。
两者都不能在断运下恢复物质供给。新事实、结果和限制见
[Round3报告](economy_quantity_lab/order_round3/ORDER_COMMITMENT_REPORT.md)与
[当前研究边界](docs/RESEARCH_BOUNDARIES.md)。完整逐日/订单轨迹输出进入忽略目录和
CI artifact，Git保存小型summary、hash manifest及因果证据。

Round3 PR #2已合并，v0.3 annotated tag冻结合并后的基线；其策略仍未获正式采用。

## Round4A供应商准入与取消确认

`economy_quantity_lab/supplier_round4a/`将采购请求与真实接受订单分离，比较S0全接受
和S1基于当前运力的共享三日ATP。拒单不进入订单账，取消请求一日后确认，未确认
仍计入pending。10×600日、四个握手专项、缺货反证探针及29项检查实际运行。
`verify_round4a.py`再生两次44文件并核对冻结hash；提交前运行全部三个统一入口。

实体结果未改善，持续停运S1保留need320而非不可履约pending；超载仍有backlog1470。
运输ATP不能保证供应商有货。报告与Gate见
[Round4A报告](economy_quantity_lab/supplier_round4a/SUPPLIER_ADMISSION_REPORT.md)。
独立研究PR等待审查；没有第二供应商或WWO集成，本轮不开始Round4B。
