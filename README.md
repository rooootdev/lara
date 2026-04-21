<div align="center">
  <br>
  <a href="https://discord.gg/gw8PcRF3Jr"><img src="https://github.com/rooootdev/lara/blob/main/lara.png?raw=true" alt="JESSI Logo" width="200"></a>
  <br>
  <h1>LARA</h1>

  <p>请关注lara的官方仓库 :P</p>
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
  <a href="#support">support</a> •
  <a href="#features">features</a> •
  <a href="#installation">installation</a>
</p>

## 支持范围
lara will at its absolute best only ever support versions up to iOS 26.0.1/iOS 18.7.1. the exploit was patched after those versions.
lara 只在 iOS26.0.1和iOS18.7.1上处于最好的状态。这个漏洞在此之后的几个版本更新中被修复。
currently tested on iOS 17.1 - 26.0.1, up to iOS 18.7.1 only on the 18.7 series.
只在iOS17.1-26.0.1上进行过完整测试，在18.7系列里，只有iOS18.7.1支持
## 对比

| 系列 | 版本 / 芯片 | 状态 |
| :--- | :--- | :--- |
| **iOS 17** | 所有版本 | 支持 |
| **iOS 18** | 18.0 — 18.7.1 | 支持 |
| **iOS 26.0/26.0.1** | 只支持26.0 — 26.0.1  | 支持 |
| **iOS 26.1+** | 26.1+ | **已修补** |
| **M-系列芯片** | M1, M2, M3, etc...  | **不支持** |

> [!CAUTION]
> if you are on an M-series device or any iOS version higher than 26.0.1, the app will crash on launch. this isn't a bug, lara just doesnt support those devices yet.
> 如果你拥有M系列设备搭载任意iOS版本或者系统版本高于26.0.1，那么lara会在启动时崩溃，这不是bug，只是lara不支持在这些版本上运行。
> **ANY ISSUES THAT INVOLVE LARA NOT WORKING ON UNSUPPORTED VERSIONS WILL BE CLOSED IMMEDIATELY.**
任何说lara在不支持的版本上启动崩溃的议题，都会被迅速关闭。
If you run lara on your device, and it ends up working, please contact me on [discord](https://discord.gg/gw8PcRF3Jr) and tell me:
1. your device
2. your iOS version
4. what you tested in lara (eg. Run Exploit, Init KFS, etc.)

If lara doesnt work on your device, and you want to help the project, please also provide your logs and iOS version.

## features:
### implemented:
- Font Overwrite
- Custom Overwrite
- File Manager (Full Disk r/w)
- MobileGestalt Editor
- 3 App Bypass
- DirtyZero 2 (Broken)

### coming soon:
- remotecall????

## known issues:
- wont work on M5, A19 and A19 Pro due to MTE
- on iOS 17.x, the kernel may panic when lara is closed from the app switcher.
- downloading OTA updates does not work.
- dirtyzero does not work.
- ui is buggy on 17.x
- doesnt work on ipad m2?
- kernelcache download broken for some versions.

## installation:
<a href="https://celloserenity.github.io/altdirect/?url=https://raw.githubusercontent.com/rooootdev/lara/refs/heads/main/source.json" target="_blank">
   <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200">
</a>
<a href="https://github.com/rooootdev/lara/releases/download/latest/lara.ipa" target="_blank"><img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download .ipa" width="200"></a>

## tips:
deleting and redownloading kernelcache is known to fix many issues. do this before asking me for support.  
closing and reopening the app can fix font change issues.
respringing is needed to apply springboard changes such as font changes.

## credits:
- opa334 for the kernel exploit poc, ChOma and XPF
- AppInstaller iOS for help with offsets
- AlfieCG for libgrabkernel2
- Everyone who contributed!
