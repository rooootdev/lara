<div align="center">
  <br>
  <a href="https://discord.gg/gw8PcRF3Jr"><img src="https://github.com/rooootdev/lara/blob/main/lara.png?raw=true" alt="JESSI Logo" width="200"></a>
  <br>
  <h1>LARA</h1>

  <p>Please follow the official repository of LARA :P<br>
  请关注lara的官方仓库 :P</p>
</div>

<p align="center">
  <a href="https://discord.gg/gw8PcRF3Jr">
    <img src="https://img.shields.io/badge/Discord-Join%20Server-7289DA.svg" alt="Discord">
  </a>
  <a href="https://github.com/rooootdev/lara/stargazers">
    <img src="https://img.shields.io/github/stars/rooootdev/lara?style=social" alt="GitHub stars">
  </a>
  <a href="https://github.com/rooootdev/lara/issues">
    <img src="https://img.shields.io/github/issues/rooootdev/lara" alt="GitHub issues">
  </a>
  <a href="https://github.com/rooootdev/lara/releases">
    <img src="https://img.shields.io/github/v/release/rooootdev/lara" alt="Release">
  </a>
</p>

<p align="center">
  <a href="#support">support 支持</a> •
  <a href="#features">features 功能</a> •
  <a href="#installation">installation 安装</a>
</p>

## Support 支持范围
LARA will at its absolute best only ever support versions up to iOS 26.0.1/iOS 18.7.1. The exploit was patched after those versions.<br>
LARA 只在 iOS26.0.1和iOS18.7.1上处于最好的状态。这个漏洞在此之后的几个版本更新中被修复。

Currently tested on iOS 17.1 - 26.0.1, up to iOS 18.7.1 only on the 18.7 series.<br>
只在iOS17.1-26.0.1上进行过完整测试，在18.7系列里，只有iOS18.7.1支持。

## Comparison 对比
| Series 系列 | Version/Chip 版本/芯片 | Status 状态 |
| :--- | :--- | :--- |
| **iOS 17** | All versions 所有版本 | Supported 支持 |
| **iOS 18** | 18.0 – 18.7.1 | Supported 支持 |
| **iOS 26.0/26.0.1** | 26.0 – 26.0.1 only 只支持26.0 – 26.0.1 | Supported 支持 |
| **iOS 26.1+** | 26.1+ | **Patched 已修补** |
| **M-series Chips** | M1, M2, M3, etc... | **Not Supported 不支持** |

> [!CAUTION]
> If you are on an M-series device or any iOS version higher than 26.0.1, the app will crash on launch.
> This isn't a bug; LARA just doesn’t support those devices yet.<br>
> 
> 如果你拥有M系列设备搭载任意iOS版本或者系统版本高于26.0.1，那么LARA会在启动时崩溃，这不是bug，只是LARA不支持在这些版本上运行。
>
> **ANY ISSUES THAT INVOLVE LARA NOT WORKING ON UNSUPPORTED VERSIONS WILL BE CLOSED IMMEDIATELY.**<br>
> **任何说LARA在不支持的版本上启动崩溃的议题，都会被迅速关闭。**

If you run LARA on your device, and it ends up working, please contact me on [Discord](https://discord.gg/gw8PcRF3Jr) and tell me:
1. Your device
2. Your iOS version
3. What you tested in LARA (e.g., Run Exploit, Init KFS, etc.)<br>
如果你在设备上运行LARA且成功，请通过[Discord](https://discord.gg/gw8PcRF3Jr)联系我并告诉我：
- 你的设备
- 你的iOS版本
- 在LARA中测试了什么（例如：运行Exploit, 初始化KFS等）。

If LARA doesn’t work on your device, and you want to help the project, please also provide your logs and iOS version.<br>
如果LARA在你的设备上无法运行并希望帮助改善项目，请提供日志和iOS系统版本。

## Features 功能
### Implemented 已实现
- Font Overwrite 字体覆盖
- Custom Overwrite 自定义覆盖
- File Manager (Full Disk r/w) 文件管理器（完整磁盘读写）
- MobileGestalt Editor MobileGestalt编辑器
- 3 App Bypass 3 应用绕过
- DirtyZero 2 (Broken) DirtyZero 2 (损坏)

### Coming Soon 即将到来:
- remotecall????

## Known Issues 已知问题
- Won't work on M5, A19, and A19 Pro due to MTE<br>
  因为MTE无法在M5, A19和A19 Pro 上运行
- On iOS 17.x, the kernel may panic when LARA is closed from the app switcher.<br>
  在iOS 17.x 上，从应用程序切换器关闭LARA时可能会导致内核崩溃
- Downloading OTA updates does not work.<br>
  OTA更新下载无效
- DirtyZero does not work.<br>
  DirtyZero 功能无效。
- UI is buggy on 17.x<br>
  在17.x版本的UI存在问题。
- Doesn’t work on iPad M2?<br>
  可能无法在iPad M2运行
- Kernelcache download broken for some versions.<br>
  某些版本的Kernelcache下载受损。

## Installation 安装
<a href="https://celloserenity.github.io/altdirect/?url=https://raw.githubusercontent.com/rooootdev/lara/refs/heads/main/source.json" target="_blank">
   <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200">
</a>
<a href="https://github.com/rooootdev/lara/releases/download/latest/lara.ipa" target="_blank">
   <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download IPA" width="200">
</a>

## Tips 贴士
- Deleting and redownloading Kernelcache is known to fix many issues. Do this before asking me for support.<br>
  删除并重新下载Kernelcache可以解决大多数问题。在向我求助之前，请尝试这样做。
- Closing and reopening the app can fix font change issues.<br>
  关闭并重新打开应用程序可以解决字体更改问题。
- Respringing is needed to apply Springboard changes such as font changes.<br>
  Respring可以应用Springboard更改，例如字体更改。

## Credits 鸣谢
- opa334 for the Kernel Exploit POC, ChOma, and XPF<br>
  感谢opa334提供的内核漏洞验证、ChOma 和 XPF
- AppInstaller iOS for help with offsets<br>
  感谢AppInstaller iOS在offsets方面的帮助。
- AlfieCG for libgrabkernel2<br>
  感谢AlfieCG提供libgrabkernel2
- Everyone who contributed!<br>
  每一位贡献者！