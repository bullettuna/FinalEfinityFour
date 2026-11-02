# FPGA 与 PC 游戏源码包

本目录包含 Ti60F225 四镜像 FPGA 工程和 Soul Rider 电脑端 Local 源码。
已移出 FPGA 编译中间结果、预编译 BIT/HEX、发布校验报告和重复源码压缩包。
保留工程配置、引脚与时序约束、IP 初始化数据、模型、游戏素材和训练样本。

## 目录

- `EfinityFPGAfour/`：FPGA RTL、IP、工程、约束、仿真、脚本、样本和技术文档。
- `Local/FPGA_GAME/`：PC Python 源码、网页游戏、素材、模型和测试。
- `Local/TrainingData/`：十一点骨架训练样本。
- `Local/START_SOULRIDER_LOCAL.cmd`：PC 启动入口。
- `START_PC.cmd`：根目录 PC 启动入口，转到上述 Local 启动脚本。
- `sdcard/MODEL7.BIN`：image7 从 SD 卡加载的模型数据，运行所必需。

## FPGA 工程入口

使用 Efinity 2025.2.288，器件 Ti60F225，打开以下工程：

- image1：`EfinityFPGAfour/images/image1_four_video_guard/Ti60_Image1_Four_Boot.xml`
- image2：`EfinityFPGAfour/images/image2_four_boot/Ti60_Image2_Four_Boot.xml`
- image5：`EfinityFPGAfour/images/image5_four_boot/Ti60_Image5_Four_Boot.xml`
- image7：`EfinityFPGAfour/images/image7_four_boot/Ti60_Image7_Four_Boot.xml`

image1 使用 video guard 版本。
`images/image1_four_boot`、`images/image5_canny`、`images/image7_mocap11_a`
和 `images/four_boot_common` 仍被最终工程引用，已保留。
`src/`、`ip/`、`pri/` 也一起保留。

本包不附带现成的 FPGA 烧录文件，需要重新综合、布局布线和生成位流。
原四槽顺序为 image7、image1、image5、image2，上电默认 image7。
使用 image7 时，把 `sdcard/MODEL7.BIN` 放在 SD 卡根目录。
## PC 端启动

双击 `START_PC.cmd` 或 `Local/START_SOULRIDER_LOCAL.cmd`。
本机已有可用环境位于项目外的 `E:\Efinity_Project\FPGA_GAME\.venv-fourpoint`。
当前目录层级与原 Local 相同，因此原启动脚本的相对路径仍能找到它。
本源码包没有复制 Python、虚拟环境、CUDA DLL 或 Portable EXE。

换电脑后安装 Python 3.10+ 和依赖：

```powershell
cd .\Local\FPGA_GAME
py -3 -m pip install -r .\requirements.txt
```

游戏：`http://127.0.0.1:8765/game/`
调试：`http://127.0.0.1:8765/game/debug.html`

默认配置为 FT232H 十一点输入（kind=5），与 image7 配套。
需要 FTDI D2XX 驱动及实际连接的 FPGA/FT232H。
未连接设备时可以启动软件，进入游戏后会等待姿态数据。

PC 测试：在 `Local/FPGA_GAME` 目录使用装好依赖的 Python 执行
`python -B -m unittest discover -s tests -v`。

## 归档范围

不包含：`outflow/`、`work_*/`、FPGA 发布目录、Portable 运行环境、PC 日志、
缓存、运行输出，以及由报告脚本生成的 Word 成品。
保留：全部原有 FPGA 源码及文档、PC 主要代码和配置、素材与许可证、
推理模型、训练数据及测试。`.git/` 仅用于版本管理。