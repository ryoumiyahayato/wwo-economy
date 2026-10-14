# WWO Algorithm Sandbox

这个私人仓库现在用于独立经济 / 军事算法的控制变量功能实验。
保留提交历史和 PRIVATE 可见性；不会公开历史研究内容。

可运行实验台位于 [`algorithm-sandbox/`](algorithm-sandbox/README.md)：
独立预期、实际结果与差异；固定种子；开始/暂停/单步/重置；事件因果链；
JSON 场景/结果往返；同场景单变量对照；版本化私有适配接口。

```sh
cd algorithm-sandbox
npm ci
npm run dev
```

地址为 `http://127.0.0.1:5173`。源码包单独保持可公开；此整个仓库因包含
私人历史与旧研究资料而保持 PRIVATE。公开 demo 仅验证工作台，不证明新版
WWO 算法有效。真实法国500km地形仍未取得，数据接口与原创夹具已提供。

## 历史经济研究迁移

历史 Economy Lab 来自提交
`48b280a37be8f5fd72f0c277f4ae435e675efa1f`，已原样迁入 WWO 私有研究目录：

- [WWO 迁移 draft PR #115](https://github.com/ryoumiyahayato/wwo/pull/115)
- 分支 `research/economy-lab-migration-20261014`
- 提交 `07deb15e2ad4e75e5feead00621893e53eaf7c8a`
- 目录 `research/economy-lab-20261007/`

363 个历史跟踪文件的字节、Git blob 和模式均保持一致。七个验证入口
`verify_baseline.py` 至 `verify_round5b.py` 在新目录全部通过。迁移没有替换
Godot 默认算法，也没有自动接入游戏。

本分支将旧 Lab 原布局移动至 [`legacy/economy-lab-20261007/`](legacy/economy-lab-20261007/README.md)，
保留完整副本供恢复和来源核验。迁移 PR 尚未合并，不删除这份历史副本，
也不刷新其冻结 manifest。旧名字和路径在历史报告中是来源事实，不改写。

私有适配器后续可令 `WWO_LAB_PATH` 指向 WWO 迁移目录（需检出上述分支），
再调用原 Python `Simulation.step()`。钱包或定价不属于这套数量研究模型，
应显示未提供而不是由适配器补算。

## 仓库命名与云环境

用户授权将 `wwo-economy-lab` 重命名为 `wwo-algorithm-sandbox`，保持 PRIVATE。
已核验现有库 ID `1408302789` 和 PRIVATE 状态，并用当前已配置连接请求
`PATCH /repos/ryoumiyahayato/wwo-economy-lab`，仅发送新 `name`。
该动作返回 Forbidden，故库名仍为 `wwo-economy-lab`，没有更换凭据、扩大
权限或用其他接口绕过。名称调整受阻不影响本分支的沙盒用途和已核验迁移。
本分支不修改默认分支或可见性；尚不更新 remote 或保存的云环境绑定。
