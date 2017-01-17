---
layout: post
title: "Hotplugging USB disks in Qemu"
date: 2017-01-17 10:58:00
tags:
- kernel
- qemu
---

Recently I wanted to test the `scsi_remove_device()` and `__scsi_remove_device()` paths in the Linux kernel so I thought "What about using qemu's hotplug feature to plug and unplug USB disks.

So here's what I did, first start qemu with a **usb-ehci** device attached
(and some others):

```
qemu-system-x86_64 -enable-kvm -m 2048 -M q35 -smp 4 -netdev user,id=netdev \
        -device e1000-82545em,netdev=netdev -nographic \
	-drive id=disk1,if=none,file=leap-ahci.qcow2 -device ich9-ahci,id=ahci \
	-device ide-drive,drive=disk1,bus=ahci.0 -serial mon:stdio \
	-device usb-ehci
```

After the VM has booted, drop into the qemu monitor (by issuing`ctrl-a c`) and
add a disk and a *usb-storage* device:

```
QEMU 2.6.2 monitor - type 'help' for more information
(qemu) drive_add 1 if=none,id=usbdisk1,file=vdisk1
(qemu) device_add usb-storage,id=usbdisk1,drive=usbdisk1
(qemu) info usb
  Device 0.2, Port 1, Speed 480 Mb/s, Product QEMU USB MSD, ID: usbdisk1
(qemu)
```

Next in Linux check the disk has been attached (either via lsscsi or dmesg):

```
linux-xch0:~ # lsscsi
[0:0:0:0]    disk    ATA      QEMU HARDDISK    2.5+  /dev/sda
[12:0:0:0]   disk    QEMU     QEMU HARDDISK    2.5+  /dev/sdb
```

And you're done.

For the hotplug testing you can run `device_del usbdisk1` in the qemu monitor
and it vanishes again.
