# image1 按键串口测试

2026-10-26起image1使用最新P4扩展板接线，当前配置和操作见 [P4输入说明](image1-p4-inputs.md)。本文旧P3引脚保留为历史记录。

外接板按键接入 `key`：B3 / GPIOL_04，低电平表示按下，使用板上上拉。
image1 开启 `ENABLE_KEY_UART=1`；其他镜像默认关闭此功能。

输入先经双级同步，再按 96 MHz 系统时钟计数 1,920,000 周期，即 20 ms。
按下和松开均要求连续稳定 20 ms，中途反向跳变重新计时。
每次有效按下只发送一条 `key  1\r\n`（两个空格，固定数字 1），长按不重复；
稳定松开后才可再次触发，松开本身不发送消息。

消息接入现有 UART 仲裁器第 3 路，沿用 115200、8N1。
完整一行发完后其他命令回复才能发送；串口忙时计数暂存后续按键事件。
保持现有 ADC/OLED 接口空闲配置。

仿真：`tools/test-key-uart.ps1`，缩短消抖计数用于测试，解码真实 UART 输出线。
覆盖短毛刺、按下/松开抖动、长按、再次按下、串口忙时事件排队、
命令回复与按键行同时发送及复位。

编译：`tools/build-image.ps1 -Image 1`，完整编译并检查网表及约束时序。
上板使用 `images/image1_vision/outflow/Ti60_Image1_KeyUART_checked.bit`，
与本轮 `Ti60_Image1_Vision_checked.bit` 内容相同。
串口助手设置 115200、8 数据位、无校验、1 停止位，按一下看到一行 `key  1`；
按住数秒仍只有一行，松开后再按出现下一行。

2026-10-14 验证：上述仿真通过；完整编译、实际网表及全部 28 条约束内
Setup/Hold 检查通过。使用 TIMING_2 / seed=7 / effort=2，原时钟约束未变。
clk_sys Setup +4.229 ns，像素时钟 Setup/Hold +0.072/+0.035 ns；
最小余量为 DDR core_clk→twd_clk Setup +0.002 ns，余量较小。
首轮 seed=6 的 DDR Setup −0.052 ns，未作为 checked 文件交付。
总资源 46,324 XLR / 185 RAM10 / 12 DSP；按键模块 133 XLR / 0 RAM。
修改前源码已备份并推送为 b82e326，旧 bit 保存在
`outflow/baseline_before_key_b82e326/`。此次未下载实板或烧写 Flash。

按键版长度 2,888,205 字节，SHA256：
`D66DF361327FDE76202F3E595AADADC5C15BFABDB7648A0F32C225677807E308`。
