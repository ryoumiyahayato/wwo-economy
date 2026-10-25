# 第23代原生 GUI 截图

入口仍为 `merchant/main.tscn`、`merchant/global_market.tscn`；没有新场景、网页复刻或新经济算法。
`gui_capture07.gd`、`gui_capture08.gd` 保留为同一截图脚本的兼容入口。

## 已有本地工程：被动截图

先确认经济候选工程路径、当前源码 SHA、工作区改动，以及 assets/data/shared 链接的实际目标和读写权限。
仅在该经济工程应用本轮源码增量，不覆盖主 WWO、共享资源目标或受保护存档；无需重新下载历史资源。
使用 Godot 4.6.3，原工程原有存档与授权规则照常生效。真实设备可直接打开两个原场景人工操作。

```text
godot --path EXISTING_ECONOMY_PROJECT --script res://merchant/gui_capture.gd -- --scene global --output ABSOLUTE_NEW_EMPTY_DIRECTORY --seconds 120 --size 1280x800
```

`--scene main` 打开原商号。全球场景按“打开全球研究世界”，然后选择地区/小麦、切换实物订单层。
脚本仅在状态变化时读取实际渲染后的 Viewport；不会自动点采购、保存或推进时间。
超时结束只释放场景和线程，不发送保存命令。人工点击原 GUI 的操作仍按原 GUI 规则执行。
输出目录必须显式指定、可写且为空；无显示服务时明确失败，不生成 headless 假截图。
捕获结束后须检查控制台错误和实际图片，不能只以退出码或文件存在判定视觉通过。

## 云端一次局部捕获

`--sequence` 是截图脚本的显式选项，使用同一两个原场景。它要求设置
`WWO_GUI_CAPTURE_DISPOSABLE=1`，且实际 Godot 用户目录没有任何已有槽位或宿主偏好；不满足就拒绝。
启动者必须指定一个新的、可丢弃的用户数据根目录，不能对日常玩家目录设置这个选项。

本轮 Linux 启动方式（各路径均须换成自己的空工作目录）：

```sh
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
XDG_DATA_HOME=/ABS/NEW/userdata XDG_CONFIG_HOME=/ABS/NEW/config XDG_CACHE_HOME=/ABS/NEW/cache \
WWO_GUI_CAPTURE_DISPOSABLE=1 \
godot --path EXISTING_ECONOMY_PROJECT --audio-driver Dummy --rendering-method gl_compatibility \
  --script res://merchant/gui_capture.gd -- --sequence --output /ABS/NEW/frames --size 1280x800
```

序列通过既有 `Consumer.build("consumer_combined")` 和原条件入口建立全新开发世界，初始化原 shocks 参考市场，
仅用原 SimulationStep 推进3日到 minute4320，再用原 MerchantSave 保存到该临时目录槽6供原全球场景恢复。
这不是既有第62日对照或历史玩家档，也不是新经济实验结论；没有365日运行。
随后暂停捕获：全球全图（收起详情）、法国小麦详情、切到实物订单并选择已有订单、
通过原“经营原商号”按钮移交同一 Runtime 后关闭入门说明并捕获经营页。所有画面来自真实渲染。
日志输出实际 minute、订单 ID、显示服务和渲染器；不把估计调配算作实物订单。

本轮机器为云端 Linux、Xorg dummy display、Mesa llvmpipe 软件 OpenGL；不是 Xvfb、Windows GPU 或 Android。
仅检查实际画面、原生场景入口与局部切换。Windows/Android 字体、真实输入、GPU和帧率仍待本地验收。
状态始终为 **USER_VISUAL_PENDING / UX_UNACCEPTED**，以 Issue #12 中的用户反馈决定下一项修改。
