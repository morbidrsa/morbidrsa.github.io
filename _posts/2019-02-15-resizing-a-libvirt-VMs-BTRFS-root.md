---
layout: post
title: "resizing a libvirt VMs BTRFS root"
date: 2019-02-15 15:38M:06
tags:
- btrfs
- SUSE
- libvirt
---

Today I wanted to resize the root partition and backing storage of a SLE12-SP3
VM I use for debugging. This included quite some Google research and thus I
thought I'll write down the steps I took for reference and others.

First check your VM's block devices:

```
jthumshirn@laptop:~$ virsh -c qemu+ssh://root@kvm-server/system domblklist sles12sp3 
Target     Source
------------------------------------------------
vda        /var/lib/libvirt/images/sles12sp3-1.qcow2
sda        /mounts/dist/install/SLE-12-SP3-Server-GM/SLE-12-SP3-Server-DVD-x86_64-GM-DVD1.iso
```

I want to resize vda which is the device my **/** lives on.

```
jthumshirn@laptop:~$ virsh -c qemu+ssh://root@kvm-server/system blockresize sles12sp3 vda 80G
Block device 'vda' is resized
```

Just to be sure, lets check if the VM noticed the resize.

```
sles12sp3-fstests-vm:~ # dmesg | tail -n2
[ 1842.675424] virtio_blk virtio2: new size: 167772160 512-byte logical blocks (85.9 GB/80.0 GiB)
[ 1842.675434] vda: detected capacity change from 42949672960 to 85899345920
```

Until now, we've only resized the block device itself. Next we need to adjust
the partition. As I'm using a
[GPT](https://en.wikipedia.org/wiki/GUID_Partition_Table) based partition
layout, I'll have to fix the backup `GPT` at the end of the disk first. For
which I had to use `parted`.

```
les12sp3-fstests-vm:~ # parted /dev/vda print
Error: The backup GPT table is not at the end of the disk, as it should be.
This might mean that another operating system believes the disk is smaller.
Fix, by moving the backup to the end (and removing the old backup)?
Fix/Ignore/Cancel? F
Warning: Not all of the space available to /dev/vda appears to be used, you can
fix the GPT to use all of the space (an extra 83886080 blocks) or continue with
the current setting?
Fix/Ignore? Fix
Model: Virtio Block Device (virtblk)
Disk /dev/vda: 85.9GB
Sector size (logical/physical): 512B/512B
Partition Table: gpt
Disk Flags:

Number  Start   End     Size    File system     Name     Flags
 1      1049kB  165MB   164MB   fat16           primary  boot
 2      165MB   2319MB  2155MB  linux-swap(v1)  primary
 3      2319MB  42.9GB  40.6GB  btrfs
```

Now up to resizing the partition itself. Parted didn't let me resize a mounted
partition, so I went old school and used `fdisk`. As `fdisk` doesn't know how to
resize a partition you have to delete it and then re-create it. This is save
as `fdisk` uses in-memory datastructures and only commits changes to disk when
you instruct it to.

```
sles12sp3-fstests-vm:~ # fdisk /dev/vda

Welcome to fdisk (util-linux 2.29.2).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.


Command (m for help): p
Disk /dev/vda: 80 GiB, 85899345920 bytes, 167772160 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 087BD880-90A9-46B1-8277-CD68D6881096

Device       Start      End  Sectors  Size Type
/dev/vda1     2048   321535   319488  156M EFI System
/dev/vda2   321536  4530175  4208640    2G Microsoft basic data
/dev/vda3  4530176 83886046 79355871 37.9G Linux filesystem

Command (m for help): d
Partition number (1-3, default 3): 3

Partition 3 has been deleted.

Command (m for help): n
Partition number (3-128, default 3): 3
First sector (4530176-167772126, default 4530176):
: st sector, +sectors or +size{K,M,G,T,P} (4530176-167772126, default 167772126):

Created a new partition 3 of type 'Linux filesystem' and of size 77.9 GiB.
Partition #3 contains a btrfs signature.

Do you want to remove the signature? [Y]es/[N]o: n

Command (m for help): p

Disk /dev/vda: 80 GiB, 85899345920 bytes, 167772160 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 087BD880-90A9-46B1-8277-CD68D6881096

Device       Start       End   Sectors  Size Type
/dev/vda1     2048    321535    319488  156M EFI System
/dev/vda2   321536   4530175   4208640    2G Microsoft basic data
/dev/vda3  4530176 167772126 163241951 77.9G Linux filesystem

Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Re-reading the partition table failed.: Device or resource busy

The kernel still uses the old table. The new table will be used at the next reboot or after you run partprobe(8) or kpartx(8).
```

Thankfully `fdisk` notifies you that you have to tell the kernel about the
changed partition table as well, for this I used `partx`. Check with `lsblk` that
the kernel actually sees the update.

```
sles12sp3-fstests-vm:~ # partx -u -n 3 /dev/vda
sles12sp3-fstests-vm:~ # lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sr0     11:0    1  3.6G  0 rom
vda    253:0    0   80G  0 disk
├─vda1 253:1    0  156M  0 part /boot/efi
├─vda2 253:2    0    2G  0 part [SWAP]
└─vda3 253:3    0 77.9G  0 part /
```

Next on we have to resize the filesystem
([btrfs](https://btrfs.wiki.kernel.org/) in my case) on top of our new device
as well.

```
sles12sp3-fstests-vm:~ # btrfs filesystem resize max /
Resize '/' of 'max'
sles12sp3-fstests-vm:~ # dmesg | tail -n 1
[ 2284.767980] BTRFS info (device vda3): new size for /dev/vda3 is 83579875328
sles12sp3-fstests-vm:~ # btrfs filesystem show /
Label: none  uuid: 16511074-0ba2-422c-98b6-a8ea19a296a1
	Total devices 1 FS bytes used 4.01GiB
	devid    1 size 77.84GiB used 5.06GiB path /dev/vda3
```

Et voilà we have a 80GB root filesystem.
