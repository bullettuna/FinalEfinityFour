# image5 FT5! v1 图像协议

传输为 FT232H FT245 异步 FIFO / D2XX 字节流，原 UART 只负责控制。
没有固定的 USB 读取边界：接收器需要缓存分片，在流中搜索 FT5!，校验帧头后按长度接收。

```text
24 字节帧头 + payload_length 字节载荷 + 4 字节载荷 CRC32

偏移    字节数    内容
0       4         ASCII FT5!
4       1         version=1
5       1         kind（见下）
6       1         flags=0
7       1         header_length=24
8       4         sequence，从 0 递增，新会话重新从 0 开始
12      2         width，实际像素宽
14      2         height，实际像素高
16      4         payload_length
20      4         header_crc32，覆盖偏移 0..19
24      N         载荷
24+N    4         payload_crc32，仅覆盖 N 字节载荷
```

多字节整数及 CRC 字段均为小端；CRC 为 IEEE reflected CRC32，与 Python zlib.crc32 一致。
帧头 Python 定义是 `struct.Struct("<4sBBBBIHHII")`。

- kind=0：计数测试，宽高为 0，4096 字节 00..FF 重复 16 次。
- kind=1：8bpp 灰度，长度 width×height，每像素 0..255。
- kind=2：原有 8bpp 边缘，长度 width×height，每像素 0/255。
- kind=3：新增 1bpp 边缘，长度 ceil(width/8)×height；1 为边缘，0 为背景。

图像按从上到下、每行从左到右排列。1bpp 每字节按 bit7→bit0 对应八个连续像素。
例如像素 `0,1,0,1,1,0,0,1` 打包成 `0x59`。
每行独立打包；当前 FPGA 支持的 320/640/1920 均为 8 的倍数，没有补位。
PC 解码器也支持非整字节行宽，要求每行最后一个字节的右侧补位为零。

1bpp 载荷：320×180 为 7200 字节，640×360 为 28800 字节，1920×1080 为 259200 字节。
对应完整包分别为 7228、28828、259228 字节。
灰度和 kind=2 载荷仍为 57600、230400、2073600 字节。
version 保持 1、kind 增加 3；旧解析器拒绝未知 kind，必须更新接收工具才能看新边缘。

串口 !3 默认启动 kind=3；!7 启动 kind=2；!2 启动 kind=1。
!4/!5/!6 选择尺寸，!0 安全停止。!V=A 保留，新增 !P=1 识别打包能力。
自动接收程序在发边缘命令前检查 !P；手动模式必须自行确认。

接收实现为 [ft232h_receive.py](../tools/ft232h_receive.py)：

```python
parser = Parser()
for frame in parser.feed(chunk):
    check_frame(frame)
    if frame.kind:
        pixels = image_bytes(frame)  # 返回 width×height 个 8 位显示像素
```

Frame.payload 始终保留原始线上载荷，CRC 在解包前检查。
image_bytes 使用标准库按 MSB-first 解包，显示和 PGM 保存为 0/255；这一步不改变协议中的长度或 CRC。
有 CRC/序号异常应报告，不应把坏包或硬复位留下的半包当作有效图像。

本版本保留一帧 8bpp DDR 快照，在读出后进行 8 合 1 打包。
发送器接管一个字节后即保存私有副本，TXE 背压期间不会重复计算或重复写入。
打包好的字节保持稳定直到下游接受，缓存边界和模式切换按既有握手收尾。
完整接线和运行命令见 [FT232H 异步说明](image5-ft232h.md)。
