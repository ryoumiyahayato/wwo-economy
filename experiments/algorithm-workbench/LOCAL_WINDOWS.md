# Windows 本地运行

本次只在云端 Linux 执行。下列 Windows 启动入口已经编写，尚未在 Windows 实机执行；没有操作用户电脑。算法源版本不匹配时会停止并显示需要的版本，不会切分支、拉取覆盖、改核心或合并。

## 依赖与目录

安装 Git、Python 3.12+、Node.js 22.12+（本次实测24.19）、Godot **4.6.3**。Godot 使用控制台可执行文件，例如 `Godot_v4.6.3-stable_win64_console.exe`。浏览器使用支持 WebGL2 的现代版本。本次实际为 Linux Chromium/SwiftShader；Windows GPU性能未测。

准备彼此独立的目录，军事和经济原库不能放进沙盒源码目录：

- `wwo-economy-lab`：本 PR 工作分支；安装/build 只操作此沙盒。
- 军事 WWO：`04ab3cc9ffb2233fa0ab5290e0ec0a952f229630`，需原 `experiments/war_resolver/interactive_observer/client.py` 与配套项目。
- 经济 WWO：`b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`，需原 `scripts/world/economy_r1_slice.gd`、`WorldBootstrap`、`LivelihoodAction` 及完整项目。原 Python 研究入口也从此目录读取。

两个路径由用户配置；不用把私人算法或素材上传到公共站点。若本地算法已更新，请保留原工作目录另建兼容检出，或显式提供已适配新接口的插件。启动器不会自行降级到 demo，也不会假装兼容更新版。

## 启动

在 `experiments/algorithm-workbench` 打开 PowerShell，先检查：

```powershell
.\tools\start-workbench.ps1 -MilitaryRepo 'D:\WWO-military' -EconomyRepo 'D:\WWO-economy' -GodotExe 'D:\Godot\Godot_v4.6.3-stable_win64_console.exe' -CheckOnly
```

去掉 `-CheckOnly` 即执行 `npm ci`、构建、原经济项目的 Godot import，再启动本地桥接。导入生成 `.godot` 缓存，也可能生成未跟踪的 `.uid` / `.import` 元数据；领域源码不改，也不自动提交这些生成文件。首次安装需要 npm 网络访问。完成后打开 `http://127.0.0.1:8787`，点击“加载 / 刷新真实算法”。Ctrl+C 停止桥接及它自己的会话进程。

可选 `-PythonExe 'C:\…\python.exe'`、`-Port 8788`、`-SkipInstall`（已有依赖时）、`-AdapterPath 'D:\…\custom_adapter.py'`。自定义插件使用 [ADAPTER_V1.md](ADAPTER_V1.md) 的入口，自行报告其版本与能力；原插件固定版本校验不会被“忽略警告”绕过。

若系统脚本策略拒绝 `.ps1`，无需改系统策略，可直接使用同一 Python 启动器：

```powershell
python .\tools\start_workbench.py --military-repo 'D:\WWO-military' --economy-repo 'D:\WWO-economy' --godot 'D:\Godot\Godot_v4.6.3-stable_win64_console.exe'
```

启动器设置 `WWO_MILITARY_REPO_PATH`、`WWO_ECONOMY_REPO_PATH`、同经济目录的 `WWO_FORMAL_REPO_PATH`、`WWO_GODOT_BIN` 和 `SANDBOX_ADAPTER_PATH`。数据/配置/缓存放沙盒 `.local/algorithm-workbench/godot/`，网页构建放 `.local/algorithm-workbench/dist/`，仅监听127.0.0.1。

## 已测与未测

云端实测：两原算法版本检查、Godot原宿主启动、军事本人移动与双方因果观察、同画布50/25/5公里展开、正式个人生活完整链、生产/库存/账本观察、暂停回放不写原状态、桌面与390px移动视口、最小Godot消费例子、构建和局部测试。截图和视频来自真实浏览器。

Windows脚本/进程退出、Windows Godot管道与导入、Windows浏览器/GPU尚未实测。更晚的本地军事/经济接口、未上传餐饮/租住功能、逐发射击与经济人物身体动作未接入，不可据此声称已通过。兼容检查不等于算法正确性或长期稳定性证明。
