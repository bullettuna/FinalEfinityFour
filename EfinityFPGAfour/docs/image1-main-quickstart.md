# 从 main 直接使用 image1

当前为2026-10-26最新P4扩展板版：SW1=P4-37，ADC SPI=P4-13/14/17/18，FPGA侧1.8V。接线见 [P4输入说明](image1-p4-inputs.md)。

本次发布包含当前 image1 源码、工程约束、菜单和显示同步修复，以及配套的预编译文件。
bit/hex 使用普通 Git 文件保存；不需要 Git LFS，不需要先在 Efinity 中编译。

## 获取文件

已有仓库中运行：

```powershell
git switch main
git pull --ff-only origin main
```

首次获取可运行：

```powershell
git clone --branch main https://github.com/bullettuna/EfinityFPGAfour.git
cd EfinityFPGAfour
```

直接在 Efinity Programmer 中重新选择并加载：

`releases/image1/Ti60_Image1_Vision_checked.bit`

同目录的 `Ti60_Image1_Vision.hex` 是同次导出的 Flash 镜像；
`manifest.json` 记录源码指纹、文件SHA256、默认值、资源和28项时序检查结果。
可选校验命令：

```powershell
python tools/check-image1-release.py
```

## 当前功能与操作

- 保留1080p摄像头/HDMI、C/G/E/O、3×3中值、分屏、冻结、双目标检测框及中文标签。
- 修复中值开关的同步短脉冲；显示模式使用固定同步相位。
- 长按KEY1约1秒打开/关闭17项文字菜单；KEY2上移、KEY3下移；短按KEY1进入/确认编辑。
- 旋钮只在对应菜单EDIT中调参数，菜单关闭时不直接改变Canny阈值。
- 默认Canny H25/L8，白平衡496/416/313，Gamma开启、强度255。
- 串口使用115200/8N1；C/G/E/O选择画面，M切中值，F冻结，D识别，Z独立测试图。

完整操作见 [菜单说明](image1-menu.md)、[中值说明](image1-median-canny.md)和
[显示同步修复](image1-display-fix.md)。

## 修改与重新编译

使用 Efinity 2025.2.288，打开：

`images/image1_vision/Ti60_Image1_Vision.xml`

或者指定本机Efinity安装目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-image.ps1 -Image 1 -EfinityRoot E:\Efinity
```

重新构建的文件在 `images/image1_vision/outflow/`。
仓库中 `releases/image1/` 是本次发布的固定文件，构建脚本不会自动覆盖它。
修改源码后校验脚本提示与发布镜像不同，表示需要自行重新编译。

发布镜像来自2026-10-26 23:48:07的P4版，TIMING_2/seed17/effort2，
28项setup/hold全部通过。清单核验100个源码/配置依赖与配套bit/hex。
按键/ADC和菜单仿真已通过，新P4接线实际操作仍需上板验收。
