# image7：11点骨架发送开关

本版只为 image7 增加持续骨架输出开关；image1、image5、image6 的算法和发布文件均不修改。模型、摄像头、DDR／推理调度和时钟保持稳定版不变。

## 已确认的 image6／旧 image7 行为

SD 自主版上电自动加载模型、自检和推理，但 FT232H 默认模式为 0（停止），不会自行持续发送骨架或图像。电脑发送启动命令后才会持续输出。image6 仅做源码核对及哈希保护，没有修改。

## 新 image7 的操作

1. SD 根目录继续使用原 MODEL7.BIN，不用更新权重。
2. 长按 SW1 约 0.8 秒打开菜单，用 SW2／SW3 或旋钮移到最后一项 **USB PTS**。
3. 短按 SW1 在 OFF／ON 之间切换。上电／重配置后的默认值为 OFF。
4. SD 自检完成且 INFERENCE 开启时，默认自动推理路径下打开 USB PTS 就持续发送 11 点结果，不要求电脑另外发送 FT 启动命令。该开关表示允许输出；模型未就绪或推理关闭时不会凭空产生新结果。
5. OFF 停止普通持续骨架输出，保留本地推理与 HDMI 骨架显示。INFERENCE 和 SKELETON 的原开关相互独立。

原有串口图像模式和命令仍保留，USB PTS 不提供图像模式选择。若电脑显式用旧串口协议切换为图像／手动模式，仍按原有模式所有权运行；USB PTS 仅允许当前推理产生的骨架结果输出，不替代模式或推理控制。旧的 !S／!R 查询仍描述串口传输模式与尺寸，不代表新增的 USB PTS 许可。

## 发送边界和协议

骨架协议仍为 FT5!、版本2、kind5、640×360坐标基准、86字节负载、总长114字节，11个点的顺序、Q14.2坐标、置信度及两段 CRC 均不改变。取消普通发送时保持正在进行的物理 WR# 脉冲完整，然后停止并释放输出，不会为了等待电脑接收而卡住推理。

停止可能取消正在发送的最后一个逻辑包，接收脚本应继续按 FT5! 包头、长度和 CRC 同步；重新开启后从新的完整包开始。发送器保留序号状态，不把不同推理帧拼进同一包。用于整数参考比对的显式串口单次诊断请求仍可返回单包，它不会打开持续输出，也不会在上电自检时自动发送。

## 下载文件

- 临时测试：`fpga/image7_usb_points.bit`。它用于检查本版画面、菜单和发送，不用于验收多镜像 Flash 地址表。
- 三镜像固化：包根目录 `FLASH_IMAGE7_USB_POINTS_1_5.hex`，已经以 internal / Remote Update 模式合并，槽位依次为 image7、image1、image5。烧录并校验后断电重新上电，不要再次合并，也不要用独立 BIT 代替 Flash 启动。
- 默认进入 image7；BOOT IMAGE 只选目标，LOAD IMAGE 执行切换。image1 沿用此前合格 LOAD 版，不包含编号1实验；image5 沿用已发布 H23／L11 稳定版。

新工程为 `images/image7_usb_points/Ti60_Image7_USB_Points.xml`。旧的稳定版、全部旧 HEX／BIT 和原 Hex157 文件保留。构建用 `tools/build-image7-usb-points.ps1`，测试入口为 `tools/test-image7-usb-sender.ps1`、`tools/test-image7-usb-menu.ps1`、`tools/test-image7-usb-render.ps1`、`tools/test-image7-standalone.ps1 -WithVideo -UsbCandidate -SimulationName pose7_usb_points_standalone`。

软件资格检查包括实际按键和155位帧边界CDC、三拍视频通路、阻塞／写脉冲中停止和重开、完整点包及CRC、真实SD/FAT32模型启动与自检、在DDR视频压力下关闭发送后推理继续、UART及Flash退出保护、资源上限和全部setup/hold、CDC及外部FT时序预算。发布的 manifest 和 reports 记录结果。

静态时序及仿真不能代替本版实板验收。本轮不访问或烧录板卡；请实测 HDMI 流畅、USB PTS 开关、接收端未连接时关闭发送、重复OFF/ON及7→1→5→7。
