# lara
a beautiful kexploit.

## support
Currently tested on iOS 17.4.1 - 18.6.2.
If you run lara on your device, and it ends up working, please contact me on [discord](https://discord.com/users/919268666305024010) and tell me:
1. your device
2. your iOS version
4. what you tested in lara (eg. Run Exploit, Init KFS, etc.)
5. your logs

If lara doesnt work on your device, and you want to help the project, please also provide your logs and iOS version.

## features:
### implemented:
- Font Overwrite
- DirtyZero 2 (Broken)
- MobileGestalt Editor (also probably broken, but successfully overwrites the mobilegestalt)

### coming soon:
- File Manager (Full Disk r/w)

## known issues:
- on iOS 17.x, the kernel panics when lara is closed from the app switcher. this may or may not be fixed soon?
- dirtyzero does not work.

## tips:
deleting and redownloading kernelcache is known to fix many issues. do this before asking me for support.

## credits:
- opa334 for the kernel exploit poc, ChOma and XPF
- AppInstaller iOS for help with offsets
- AlfieCG for libgrabkernel2
