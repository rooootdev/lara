<div align="center">
  <br>
  <a href="https://discord.gg/gw8PcRF3Jr"><img src="https://github.com/rooootdev/lara/blob/main/lara.png?raw=true" alt="JESSI Logo" width="200"></a>
  <br>
  <h1>LARA</h1>

  <p>star this repo please :P</p>
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

## support
lara will at its absolute best only ever support versions up to iOS 26.0.1/iOS 18.7.1. the exploit was patched after those versions.

currently tested on iOS 17.1 - 26.0.1, up to iOS 18.7.1 only on the 18.7 series.

## compatibility

| series | version / chip | status |
| :--- | :--- | :--- |
| **iOS 17** | all versions | supported |
| **iOS 18** | 18.0 — 18.7.1 | supported |
| **iOS 26.0/26.0.1** | 26.0 — 26.0.1 **only** | supported |
| **iOS 26.1+** | 26.1+ | **patched** |
| **M-series chips** | M1 - M4  | partially supported. YMMV |

> [!CAUTION]
> if you are on an M-series device, go to lara settings, scroll down set t1sz_boot to `0x11`. if you are on any iOS version higher than 26.0.1 the app will crash on launch. this isn't a bug, lara just doesnt support those devices.
> 
> **ISSUES THAT INVOLVE LARA NOT WORKING ON UNSUPPORTED VERSIONS WILL BE CLOSED IMMEDIATELY.**<br>
> **Issues related to lara not working on versions that the exploit DOES technically support will be closed and added to the known issues section**

If you run lara on your device, and it ends up working, please contact me on [discord](https://discord.gg/gw8PcRF3Jr) and tell me:
1. your device
2. your iOS version
4. what you tested in lara (eg. Run Exploit, Init KFS, etc.)

If lara doesnt work on your device, and you want to help the project, please also provide your logs and iOS version.

## features:
### implemented:
- Font Overwrite
- Custom Overwrite
- Card Overwrite
- File Manager (Full Disk r/w)
- MobileGestalt Editor
- 3 App Bypass
- DirtyZero 2
- 5 App Dock
- Status Bar Tweaks
- Hide labels
- Upside Down
- Floating Dock (Broken)
- Grid App Switcher
- Performance
- JIT

### coming soon:
- App Decrypt

## known issues:
- wont work on M5, A19 and A19 Pro due to MTE
- on iOS 17.x, the kernel may panic when lara is closed from the app switcher.
- downloading OTA updates does not work.
- dirtyzero does not work.
- ui is buggy on 17.x
- .aea ota updates do not work.
- A16+ and M-series devices dont support RemoteCall (yet)
- apps don't detect JIT enabled however they are enabled.

### fixes:
kernelcache download fix:
1. Download the IPSW tool for your device
[here](https://github.com/blacktop/ipsw/releases/tag/v3.1.671).
2. Extract the archive.
3. Open Terminal.
4. Navigate to the extracted folder:<br>
`cd /path/to/ipsw_3.1.671_something_something/`
5. Extract the kernel:
./ipsw extract --kernel [drag your ipsw here]
6. Get the kernelcache file.
7. Transfer the kernelcache to your iPhone.
8. In the Files app:
   - Go to "On My iPhone" > "lara"
   - Place the kernelcache file there.
9. Rename the file to "kernelcache" (without extension).

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

<br>
<div align="center">a beautiful kexploit ♥️</div>
