# 背景差分已移除

以下为 image1/image2 共享平台清理阶段记录。当前仅 image3 通过 `PERSON_BUILD=1`
恢复独立 RAW 背景与候选分析，见 [image3 人体候选 ROI](image3-person-roi.md)。

当前工程已删除 U 差分处理、Bayer 平均、开/闭运算掩膜链路、专用时序/行缓存，
以及 RAW 背景采集、DDR 背景读取 FIFO、调度和跨时钟控制。

`b` 现在只执行 RGB565 拍照、DDR 缓存和 TF 保存，不再额外截取 RAW 背景。
`i` 初始化、`x` 相册、`<` / `>` 翻页、普通视频模式和 `F` 冻结功能保留。
`U/u` 返回 `!`；旧 `N<number>` 输入在回车时返回 `!`，不会误改边缘阈值。

原 RAW 背景 DDR 区间 `0x01000000..0x013fffff` 取消占用；相册及照片 DDR
地址保持不变。此操作不擦除 DDR，也不删除 TF 卡内已经保存的照片。

删除前版本保存在本地 Git 提交 `b746e0e`。本次按用户明确指示不等待 GitHub
连接恢复，因此不能把该提交称为已完成新的远端备份。差分算法备选思路保留在
对话及该提交中，后续若需要恢复可从本地提交取回文件。

保留链路的验证：

```powershell
powershell -ExecutionPolicy Bypass -File tools/test-controls.ps1
powershell -ExecutionPolicy Bypass -File tools/test-sd4.ps1
```
