# image1／image5／image7：稳定基线回退与窗口修复

## 本轮依据

用户于 2026-10-29 实板反馈：performance_v1、performance_v2_latest 的 HDMI 视频出现卡顿；此前 menu_v3 画面流畅，允许保留其骨架更新延迟。用户确认流畅基线为 `releases/image7/menu_v3/fpga/image7_mocap11_a.bit`，生成于当天 02:23，源码提交 `afafc10`，SHA256 为 `b7476606329cd0a11149d677061cb9ec2af10568147f659301c7bdd64ab0135d`。

本轮按该回退方案执行。两个提速包保留用于追溯，但不再作为推荐运行版本。先前通过的数值仿真和静态时序没有覆盖这次实板视频问题；目前不能断言卡顿的物理根因。新位流必须先临时下载验证 HDMI 连续流畅，再固化。

## 已做修改

- image7 恢复确认版本的原始卷积、串行量化、输入缩放、上采样／拼接、AXI 主机和单帧快照路径；不使用 performance_v1 的加速执行器或 v2 的连续双缓冲。保留现有安全多镜像切换控制及 SD 只读检查功能。
- image1 沿用已有的 LOAD 切换合格版（源码 `284106a`，BIT SHA256 `8e39552c393cc4a165fa4b717d31e9226a35d0a8a4baac88d0806cad6cf55775`）。没有改它的视频算法，也不重新实现 LOAD。新增编号 1 的实验没有通过时序／布局检查，本轮不发布。实验综合和布局参数已恢复为原 image1 设置，失败文件保留用于追溯。
- image5、image7 左上角常驻编号：**2=image5，3=image7**。菜单横向移到 x=40，image7 的启动状态文字也右移，避免遮挡。编号复用原字幕的三拍流水线，VS／HS／DE／RGB 拍数、行长、帧周期均不改变，不增加帧缓冲。
- image7 检查窗口增加持久反馈行，例如 `CHECK 2 BIN FAIL E04`：序号只在实际接受检查请求时增加；执行时 WAIT，结束后保留 PASS 或 FAIL，失败显示真实错误码。
- SD 检查根据卡初始化及 FAT32 解析判定；BIN 检查还要求模型文件、文件头、CRC 与数值自检通过。卡和 FAT32 可用但 MODEL7.BIN 缺失时，SD 可以 PASS，BIN 为 FAIL E04。列表中的 Ehh 是这次完整加载流程的错误码，不能只看它判断卡是否损坏；持久反馈行标明本次实际执行的 SD／BIN 项。
- image5、image7 上电及 CANNY RESET 的默认值改为 **H=23，L=11**。image1 阈值保持原值。
- image5、image7 的白平衡 R/G/B 为 **496／416／313**，Gamma 开启、强度 **255**，黑阈值 **96**，与 image1 默认值对齐。image5 原本已采用这些白平衡和 Gamma 值，本轮保持；image7 改为同值。

图像参数变化会改变实时边缘和模型输入，模型权重不变；固定输入自检 PASS 不代表已经验证新参数下的实拍识别精度。骨架效果需与实际画面对照。验收优先级为：视频持续流畅、窗口控制反馈正确、再观察骨架效果。

## 文件及下载

新独立工程为 `images/image5_stable_ui`、`images/image7_stable_ui`；image1 复用 `releases/multiboot/image7_default_1_5/fpga/image1.bit/.hex`。`images/image1_stable_ui` 仅为未合格实验归档，不能用于下载。原有 HEX／BIT 全部保留，发布工具会复核本轮修改前登记的 80 个文件的长度与 SHA256。

1. 先临时 JTAG 下载 `fpga/image7_stable_ui.bit`，保持现有 SD 卡和 HDMI；观察至少几分钟视频是否连续流畅，再开关推理、骨架和菜单。
2. image1 如需单独下载，使用 `fpga/image1_load.bit`，它与之前通过时序的 LOAD 版完全相同，本轮没有新增常驻编号 1。image5 使用 `fpga/image5_stable_ui.bit`，检查编号 2、RGB 色彩与 H23／L11 默认值。
3. image7 长按 SW1 打开菜单，浏览到 SD CHECK／BIN CHECK，短按执行。检查底部序号变化、WAIT 及最终 PASS／FAIL。使用缺失文件的卡测试时应看到 BIN FAIL E04；恢复原 MODEL7.BIN 后重新检查，应恢复 PASS。不要为测试改写唯一一份模型文件。
4. 三套临时测试通过后，向配置 Flash 写入包根目录 **FLASH_IMAGE7_STABLE_1_5.hex** 并校验，重新上电。默认进入编号 3 的 image7；BOOT IMAGE／LOAD IMAGE 仍可切换 image1、image5、image7。
5. 单独 BIT 用于临时调试，三镜像地址表由官方合并步骤写入合并 HEX。请从合并 Flash 上电后验证多镜像切换。

SD 根目录继续使用原 **MODEL7.BIN**（236,448 字节，SHA256 `74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e`）。不需要重新训练或更换模型。

包内 `baseline/image7_confirmed_menu_v3.bit` 是用户确认流畅的原始位流，可用于立即回退对照。它没有本轮编号、参数和反馈修复，也不是三镜像合并文件。

## 验证边界与复现

新 image5／image7 的离线检查覆盖：图像编号、三拍 RGB／同步不变、菜单开关与完整帧尺寸、154 位显示记录的整帧提交、真实按键检查地址、实际 SD／FAT32 读取与模型 CRC／数值自检、SD PASS 与 BIN FAIL E04 的区分、重复检查序号、完成反馈保留、在视频 DDR 压力下的模型启停／重载／USB 与安全退出，以及全部 setup／hold、CDC、MIPI 附加裕量和资源门禁。

image1 的原有 28 项 setup／hold 关系、CDC、菜单切换测试和源代码归档经过独立复核；`reports/image1` 是原合格版本的证据，没有把新实验的失败结果当成通过。

这些检查不能保证修改后的新布局已在实板流畅。`hardware_tested=false`，本轮没有连接或写入串口、JTAG 或板卡 Flash。各套资源、编译记录和校验值见 `manifest.json` 与 `reports`。

主要命令：`tools/build-stable-ui.ps1 -Image 5`／`-Image 7`、`tools/test-stable-ui.ps1 -Images 5,7`、`tools/test-stable-menu-control.ps1`、`tools/test-image7-standalone.ps1 -WithVideo -StableCandidate -SimulationName pose7_stable_ui_standalone`、`tools/package-stable-ui.py`。不再继续 image1 的额外综合或布局试验。
