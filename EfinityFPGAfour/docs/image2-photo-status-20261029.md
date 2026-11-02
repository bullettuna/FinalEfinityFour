# image2：实际拍照状态与保持实时画面

本版独立工程为 `images/image2_photo_status/Ti60_Image2_Photo_Status.xml`。
在已确认流畅的 video_guard 版上增加实际拍照状态，不改摄像头、DDR或HDMI算法和时钟。

SAVE SD一行显示READY／WAIT／OK／ERROR；请求未被接收时显示BUSY。
WAIT覆盖采集、Canny处理和SD写入；仅原FAT32写入器发出完成信号后才显示OK。
写入失败显示ERROR；原保留图像、失败重试及删除保护继续有效。
保存后不自动进入相册，保留当前显示模式继续实时显示。GALLERY仍可手动进入和翻页。

已验证真实SD4/FAT32保存WAIT→OK、注入写失败ERROR→保留帧重试WAIT→OK，
无自动相册、实时DDR视频继续更新、手动相册和双确认删除；原串口与窗口对齐测试通过。
28项setup/hold和CDC通过，CSI额外setup/hold为0.8/0.6ns，余量+0.663/+0.020ns。
资源41,269 XLR、127 RAM10、32 DSP。

BIT SHA256为`d8259815e92d3de10e8f36340b45d4350b90cf249ef6337ae0509191981d1554`。
2026-10-29，用户在“画面流畅、WAIT→OK、不跳相册”的实板验证问题下回复“没问题”。
此版本作为后续默认参数调整和7/1/5/2合并之前的回退检查点保留；相关旧BIT/HEX不删除。
