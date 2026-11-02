# image7 默认启动，菜单切换 image1 / image5 / image7

本发布包面向 VF-Ti60F225 板卡的 W25Q64JWSSIQ 配置 Flash（64 Mbit，即 8 MiB）。三个程序存放在同一片 Flash 中，每次只运行其中一个。上电先加载 image7；在任意一个程序的 HDMI 菜单里都能选择并切换到另外两个程序。

image7 的 A11 模型、MODEL7.BIN、Canny 输入和 FT232H 数据包格式保持不变。image5 接入已有的 2026-10-27 菜单版本，保留 USB 模式、USB 尺寸、白平衡等功能。image6 及其依赖的原 UART／FT／存储运行模块保留。

## 固化文件

必须烧录发布包根目录的 **FLASH_IMAGE7_1_5.hex**。它是 Efinity 官方 `multi_image_merger.py` 生成的 `selectable_flash_image / internal` 文件，包含每个镜像所需的内部重配置选址表。

不能依次将三个独立 HEX 都烧在地址 0，也不能将三个 BIT 简单拼接。包内独立 BIT 用于 JTAG 调试和追溯，不代替合并 Flash 文件；临时 JTAG 下载独立 BIT 后也不能据此验收多镜像切换。应从合并 Flash 重新上电启动后验收。

固定映射：

- 内部选择值 `00`：image7，地址 `0x000000`，默认启动／Golden 镜像。
- 内部选择值 `01`：image1，地址 `0x280000`。
- 内部选择值 `10`：image5，地址 `0x500000`。
- `11` 不提供菜单入口，不存放第四套算法。

每个镜像保留 2.5 MiB 空间，最后一个镜像不能超过 `0x780000`，总文件不能超过板载 `0x800000` 字节容量。最终实际长度、地址、SHA256、资源和时序报告见随包 manifest 与 reports。

## 手动烧录与首次启动

1. SD 卡继续使用 FAT32 根目录的原 **MODEL7.BIN**。该文件未改变；若卡中已存在正确版本，无需重新复制。image1 / image5 不依赖这个模型文件。
2. 使用板卡已有的 JTAG-to-Flash／Flash Loader 固化方式，在 Efinity Programmer 中选择 `FLASH_IMAGE7_1_5.hex`，写入配置 Flash 并执行校验。此操作由用户手动完成；本次软件工具没有连接或写入板卡 Flash。
3. 完成后重新上电，而不只是临时 JTAG 下载。应进入 image7。若 SD 文件有效，image7 会重新加载权重、自检并启动推理。
4. 后续升级任意一套程序，都应重新生成合并 HEX，再按同样方式固化；不要用单独的 image1／image5 HEX 覆盖默认启动位置。

## 三个窗口的共同操作

- SW1 长按约 0.8 秒：打开／关闭菜单。
- SW2／SW3 或旋钮：移动菜单光标；原有数值编辑方式不变。
- 找到 **BOOT IMAGE**，短按 SW1：循环选择 `IMAGE7 → IMAGE1 → IMAGE5 → IMAGE7`。这一步只选目标，不重启当前程序。
- 移到下一行 **LOAD IMAGE**，再次短按 SW1：执行切换。

进入新程序后，按同样方式打开其菜单即可切回 image7 或切到第三套程序。选择正在运行的镜像会显示 `HERE`，不会无意义地重启。断电重上电始终默认 image7，不保存上次选择为新的默认值。

切换会重启当前程序，HDMI 可能暂时黑屏，摄像头和 DDR 重新初始化；USB／串口会话也应按程序重启处理。image7 重新进入时从 SD 加载模型。程序之间不保留图像参数、冻结状态、推理开关或游戏运行状态。

## 切换状态

- `READY`：已选择目标，等待执行。
- `WAIT`：等待当前程序准备退出。
- `LOAD`：内部重配置已开始。
- `ERROR`：准备退出超时、重配置未按预期完成，或配置硬件报告过失败。
- `HERE`：所选目标就是当前程序，无需切换。

image7 会停止新推理和快照，等待在途推理、SD 读取、自检和相关 DDR 事务结束；已排队的 SD 检查、UART 上传／诊断也有退出保护。准备切换期间不再接收新的模型串口或 SD 检查任务。USB 接收端未连接／阻塞不会无限阻止切换。image5 会先停止 FT232H 图像通路并排空它的事务。image1 不含 TF 写入或模型推理任务。

这不是保存游戏进度的功能；重配置必然清除当前应用的易失状态。若准备退出超过 10 秒，软件不发 CONFIG，留在当前程序显示 ERROR。配置失败时，硬件可回退 Golden image7；软件不会在上电或回退后自动再次触发切换，避免重启循环。恢复失败原因后可重新手动选择。

image7 准备退出时会关闭推理；若退出超时留在原程序，推理保持关闭，可排除原因后手动开启推理或重试切换。

image7 的 `ERR04`／`BIN CHECK FAIL E04` 表示 SD 中模型文件未找到，与 Flash 切换 ERROR 是不同状态。模型文件有问题时，只要 SD／DDR 任务已经安全退出，仍可从菜单选择 image1 或 image5。

## 工程与复现

- image1：`images/image1_vision/Ti60_Image1_Vision.xml`。
- image5：`images/image5_canny/Ti60_Image5_Canny.xml`。
- image7：`images/image7_mocap11_a/Ti60_Image7_Mocap11_A.xml`。
- 构建：`pwsh -File tools/build-multiboot-image.ps1 -Image 1`，分别对 5、7 执行。每个工程有独立构建锁；不得并发构建同一个工程。
- 功能：`tools/test-multiboot.ps1`，覆盖全部槽位、真实菜单输入和窗口文字。
- 退出保护：`tools/test-image7-reconfig.ps1`，覆盖部分 UART 上传、停止期间禁止新任务、超时释放、SD 检查和诊断所有权。
- 完整 image7：`tools/test-image7-standalone.ps1 -WithVideo -SimulationName pose7_multiboot_final`，覆盖 SD4、FAT32、自检、连续推理、视频 DDR 竞争、USB 阻塞、启动期间／实时推理期间的退出。
- 原菜单：image1、image5、image7 的菜单测试脚本仍可运行。image5 的菜单 UART 和 FT 控制器采用私有模块，避免改变 image6。
- 打包：`python tools/package-multiboot.py`。只接受源码指纹匹配、资源与 setup/hold 合格的三套产物；调用 Efinity 官方合并工具后，再独立核对三套地址表、模式位、Flash 容量和配置数据未变。

## 资料依据与验收边界

板卡配置 Flash 型号来自随板硬件资料中的 VF-Ti60F225 用户手册与核心板原理图。内部接口和文件组合方式依据 [Efinix AN010 v2.5](https://www.efinixinc.com/docs/an010-using-internal-reconfiguration-feature-v2.5.pdf)。重配置使用原 96 MHz 系统时钟，未增加外部布线或更改 Flash 电平。

软件仿真、配置文件校验和静态时序不能代替实板验收。烧录后需验证：断电上电默认 image7；7→1→5→7 及反向切换；三套 HDMI 稳定；image7 重新加载模型并恢复识别；USB 启停正常。实板烧录、校验和这些现场结果由用户完成后再确认。
