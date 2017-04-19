---
layout: post
title:  "Rapid kernel development with dracut and Qemu"
date:   2017-04-19 17:16:00
tags:
- kernel
- qemu
- dracut
---

Here's a small How-to for testing kernel changes with Qemu but without the
need of a rootfs. Instead of going down the disk image plus installation path
I just quickly fired up [dracut ](https://dracut.wiki.kernel.org/index.php/Main_Page)
to build an initramfs suitable for my tests.

The 1st step is to build the kernel and install the needed modules

```
make -j `getconf _NPROCESSORS_ONLN` && \
	make INSTALL_MOD_PATH=mods/ modules_install
```

Then build the dracut initrd and install the tools you need to reproduce your
problem:

```
dracut --no-compress --kver `make kernelrelease` --install "shutdown tail \
	blockdev ps rmdir dd grep find df strace mkfs.xfs mkfs.btrfs \
	/lib64/libkeyutils.so.1 blkid /usr/lib64/libuuid.so.1 \
	/usr/lib64/libblkid.so.1 fdisk /usr/lib64/libfdisk.so.1 \
	/usr/lib64/libsmartcols.so.1 /lib64/libtinfo.so.5  \
	/lib64/libreadline.so.6" --kmoddir mods/  \
	--add-drivers "nvme nvme-core btrfs xfs" --no-hostonly \
	--no-hostonly-cmdline --modules "bash base" --tmpdir  `pwd`/initrds/ \
	--force initrds/myinitrd
```

And last but not least, fire up Qemu and pass your *-kernel* and *-initrd*
parameters.

```
qemu-system-x86_64  \
	-drive file=../VMs/NVDIMM.img,id=D22,if=none,format=raw,snapshot  \
	-device nvme,drive=D22,serial=1234 -nographic -serial mon:stdio \
	-kernel arch/x86/boot/bzImage -initrd initrds/myinitrd -enable-kvm \
	-append "console=ttyS0" -smp 4 -m 2048
```
