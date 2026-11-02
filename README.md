# FinalEfinityFour

基于 **Elexis（易灵思）Ti60F225** 的四镜像 FPGA 工程完整源码与发布产物。四个镜像固化在同一片 8 MiB 配置 Flash 中，采用 Selectable Flash Image（internal）multiboot 模式，上电默认进入 image7，可通过板载按键菜单在四个镜像之间热切换。

**开发环境**：Efinity 2025.2.288 ｜ 器件 Ti60F225 ｜ 系统时钟 `clk_sys` = 96 MHz（周期 10.417 ns）
**最终烧录文件**：`Hex/Hex7152_IMAGE1_GUARD_20261029.hex`（7,761,530 字节，SHA256 `93e0a7c3…e30a`）

---

## 一、四个镜像

| 槽位 | 地址 | 镜像 | 功能 |
|---|---|---|---|
| slot0 | `0x000000` | **image7** | 11 点人体骨架姿态推理。SC2210 摄像头 → ISP → DDR 快照 → 池化预处理 → 自研小 U 型卷积网络 → `64×36×11` heatmap → 逐通道 argmax 解算 11 个关节点，HDMI 叠加骨架，模型从 SD 卡 `MODEL7.BIN` 加载 |
| slot1 | `0x280000` | **image1** | 主视频与菜单。彩色 / 灰度 / Canny 边缘（前置 3×3 中值滤波）、形状识别与中文标签、屏幕左上角文字菜单、P4 扩展板按键 / MCP3202 旋钮 / 分压键。本槽为 **guard 版**，为 CSI 与像素域额外加时序裕量以排查花屏 |
| slot2 | `0x500000` | **image5** | 去噪灰度 Canny 预览。前置中值 + 两级碎边清理，可通过 FT232H 输出边缘图，支持 320 / 640 / 1920 三档 |
| slot3 | `0x680000` | **image2** | 拍照与存储。960×540 Canny 二值（去斑）照片，BMP 写入 TF 卡、相册浏览、UART 导出，拍照期间不影响实时画面 |

四个工程彼此独立（`EfinityFPGAfour/images/*_four_boot`），各自持有私有配置与菜单副本，互不污染。合并时只替换对应槽位，其余三槽逐字节保持原样。

## 二、仓库包含什么

```
FinalProject/
├── EfinityFPGAfour/          FPGA 工程（主体，778 个文件）
│   ├── images/               各镜像独立的 Efinity 工程
│   │   ├── image7_four_boot/     11 点骨架推理（默认启动）
│   │   ├── image1_four_video_guard/  image1 guard 候选
│   │   ├── image2_four_boot/     拍照与 TF 卡
│   │   ├── image5_four_boot/     灰度 Canny
│   │   └── …                     历史工程（image3/4/6、stable_ui 等）保留存档
│   ├── src/                  RTL 模块（isp / vision / pose7 / ft232h / sd / ui / top …）
│   ├── ip/                   IP 核（含 DDR3 控制器初始化数据）
│   ├── docs/                 每个功能的实现与验证说明（55 篇）
│   └── tools/                构建、检查、校验脚本
├── Hex/                      合并烧录文件 + SHA256 + 烧录说明
├── fpga/                     四个镜像各自的 .bit / .hex
├── reports/                  时序、资源、CDC、烧录读回校验、四槽位测试日志
├── sdcard/MODEL7.BIN         image7 推理模型（236,448 字节）
├── source_archive/           源码归档 zip
├── PACKAGE_MANIFEST.json     1235 个文件的逐文件 SHA256 清单
└── release_manifest.json     发布元数据（槽位、时序、候选对比）
```

**不包含**：构建中间产物（`outflow/`、`work_pnr/`、`work_syn/`、`*.sdb`、`*.netlist`、`*.troutingtraces` 等），这些由 Efinity 重新综合生成；以及 PC 端上位机运行时，该部分单独分发，不在本仓库内。排除规则见根目录与 `EfinityFPGAfour/` 下的 `.gitignore`。

## 三、烧录与切换

**烧录**（SPI Programmer，internal 模式，从地址 0 写入）：

```
文件：Hex/Hex7152_IMAGE1_GUARD_20261029.hex
地址：0x000000
方式：Selectable Flash Image / internal，烧录后执行读回校验
```

烧录前可先用 `Hex/Hex7152_IMAGE1_GUARD_20261029.sha256.txt` 校验文件完整性。

**切换镜像**（板载按键）：

1. 长按 SW1 约 0.8 s 打开菜单
2. SW2 / SW3 或旋钮移动到 `BOOT IMAGE`，短按 SW1 循环选择 `IMAGE7 → IMAGE1 → IMAGE5 → IMAGE2`
3. 移到 `LOAD IMAGE`，短按 SW1 执行重载

仅改 `BOOT IMAGE` 不会自动切换。`HERE` 表示选中当前镜像，`WAIT` 表示等待当前任务结束，`LOAD` 表示已提交，`ERROR` 表示切换失败。image2 处于拍照或 SD 读写时，切换会被推迟到任务完成。

## 四、构建

Efinity 打开对应工程目录直接综合即可，也可用脚本：

```powershell
powershell -ExecutionPolicy Bypass -File EfinityFPGAfour/tools/build-four-image.ps1 -Image 7
powershell -ExecutionPolicy Bypass -File EfinityFPGAfour/tools/test-four-image.ps1
```

发布脚本只接受通过完整 setup/hold、CDC、引脚与资源检查的产物，未通过者不会作为候选发布。

## 五、资源与时序

| 镜像 | XLR | RAM10 | DSP |
|---|---|---|---|
| image1（guard） | 52,968 | 197 | 12 |
| image2 | 41,306 | 127 | 32 |
| image5 | 20,637 | 104 | 11 |
| image7 | 57,880 | 185 | 73 |

四份工程各自的 28 项 setup/hold 时序关系全部非负，CDC 无同步器告警。image1 guard 版在 CSI setup +0.8 ns、hold +0.6 ns、像素域 setup +0.25 ns 的额外裕量下，最差 slack 为 **+0.002 ns**（CSI hold）。

## 六、文档索引

`EfinityFPGAfour/docs/` 下有每个功能的实现与验证记录，几个入口：

| 文档 | 内容 |
|---|---|
| [four-image-7152-20261029.md](EfinityFPGAfour/docs/four-image-7152-20261029.md) | 四镜像固化：槽位、烧录、切换、构建 |
| [image7-usb-points-20261029.md](EfinityFPGAfour/docs/image7-usb-points-20261029.md) | image7 11 点骨架输出开关与协议边界 |
| [image7-mocap11.md](EfinityFPGAfour/docs/image7-mocap11.md) | 11 点模型与推理链路 |
| [image1-menu.md](EfinityFPGAfour/docs/image1-menu.md) | 屏幕文字菜单实现 |
| [image1-display-fix.md](EfinityFPGAfour/docs/image1-display-fix.md) | 花屏的显示同步修复 |
| [image2-canny-photo.md](EfinityFPGAfour/docs/image2-canny-photo.md) | image2 Canny 二值拍照 |
| [image5-ft232h.md](EfinityFPGAfour/docs/image5-ft232h.md) | image5 边缘图传输 |

更完整的工程级说明见 [EfinityFPGAfour/README.md](EfinityFPGAfour/README.md)。

## 七、已知限制

- **四个镜像均未完成实板验收**。release manifest 中 `hardwareTested: false`，所有结论来自离线时序、资源与仿真，不能替代板上实测。
- **image1 花屏问题仍待确认**。guard 候选通过加强时序裕量生成，实板是否恢复需要按 `Hex/Hex7152_IMAGE1_GUARD_20261029_README.md` 的对照步骤验证（先 JTAG 独立下载观察一分钟，再烧合并 HEX 走菜单切换）。若独立下载正常而菜单切换异常，应继续排查暖重载初始化与 Flash 读取，不能把时序报告当成问题已解决。
- 构建产物不入库，clone 后需要本地重新综合；`outflow/` 与 `work_*` 目录会在首次构建时生成。
- 仓库不使用 Git LFS，也未包含任何超过 GitHub 100 MB 单文件上限的二进制。
