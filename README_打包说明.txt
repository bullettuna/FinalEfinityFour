最终版本源码及已有编译结果归档

最终烧录文件：Hex/Hex7152_IMAGE1_GUARD_20261029.hex
SHA256：93e0a7c34ec4980451ef8acd6eef0cb33ee50b2c58e800d509464ff181bde30a

四份最终工程（EfinityFPGAfour 目录下）：
image1：images/image1_four_video_guard/Ti60_Image1_Four_Boot.xml
image2：images/image2_four_boot/Ti60_Image2_Four_Boot.xml
image5：images/image5_four_boot/Ti60_Image5_Four_Boot.xml
image7：images/image7_four_boot/Ti60_Image7_Four_Boot.xml

目录说明：
EfinityFPGAfour/：从本次 HEX 原发布包的源码快照原样提取，保持工程相对路径；
  包含公共 src、ip、pri 和被引用的其他 images 源码，因此保留了相关历史源码目录。
  包含公共 src、ip、pri 和被引用的其他 images 源码，因此保留了相关历史源码目录。
  四份最终工程已有的 outflow/work_syn/work_pnr 编译生成结果也已复制到对应工程目录。
  image1 的旧 *_checked.bit/hex 及旧资格记录未混入，最终版本为 *_guard_checked.bit/hex，
  同目录常规 Ti60_Image1_Four_Boot.bit/hex 与最终 guard 位流相同。
fpga/：四份最终独立 BIT 和 HEX，image1 对应 VIDEO_GUARD 版本。
Hex/：用户指定的最终合并 HEX、原 SHA256 文件、原发布说明和合并报告。
reports/：原有编译、时序、CDC、合并核对报告及已有验证日志。
sdcard/MODEL7.BIN：原发布包配套模型文件。
source_archive/project.zip：原发布包完整源码压缩快照，原样保留。
release_manifest.json：原发布清单，清单内相对路径以原发布包为基准。
PACKAGE_MANIFEST.json：本次归档文件清单、SHA256 和来源。

Flash 槽顺序：image7@0x000000、image1@0x280000、image5@0x500000、image2@0x680000。
上电默认 image7。
源码发布提交：c9f2688b34c87e53ccfc34279be45c3d270b1518。
本次仅复制、解压和计算校验值，没有修改任何现有源码、工程配置或仿真文件；
没有重新编译、运行仿真、重新合并 HEX 或烧录硬件。
