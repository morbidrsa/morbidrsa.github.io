---
layout: post
title: "Testing NVDIMM using Qemu"
date: 2016-12-08 13:27:00
tags:
- kernel
- qemu
---

In order to test some specific features of the Linux kernel, I try to use
virtual machines as much as possible. This has a lot of advantages with the most
prominent being able to take your test environment with you when travelling.
Often you don't have access to your lab or the VPN connection to the lab is
just not reliable enough.

So here's the set needed to create a Qemu VM that includes NVDIMMs.


```
host:~$ qemu-system-x86_64 -enable-kvm -machine pc,nvdimm -smp 2\
		-m 2G,maxmem=100G,slots=10 -object \
		memory-backend-file,share,id=mem2,mem-path=NVDIMM.img,size=16G \
		-device nvdimm,memdev=mem2,id=nv2 \
		-drive file=SLES12-SP2-GM.qcow2,if=virtio \
		-serial mon:stdio -nographic
```

Just as it is with normal NVDIMMs you can use the ndctl utility to query
information about your DIMM or DIMMs.

```
vm:~ # ndctl list
{
  "dev":"namespace0.0",
  "mode":"raw",
  "size":17179869184,
  "blockdev":"pmem0"
}
vm:~ #
```

You can also change the mode of your DIMM to secotor or DAX or whatever you
like:

```
vm:~ # ndctl create-namespace -f -e namespace0.0 --mode=sector
{
  "dev":"namespace0.0",
  "mode":"sector",
  "uuid":"5c3bf6ac-4bf5-4b17-bc87-d07500f159bb",
  "sector_size":4096,
  "blockdev":"pmem0s"
}
vm:~ # ndctl create-namespace -f -e namespace0.0 --mode=dax
{
  "dev":"namespace0.0",
  "mode":"dax",
  "size":16909336576,
  "uuid":"04ed0bcb-23dd-4641-9bdf-2788c97dea47"
}
vm:~ # ndctl create-namespace -f -e namespace0.0 --mode=raw
{
  "dev":"namespace0.0",
  "mode":"raw",
  "size":17179869184,
  "blockdev":"pmem0"
}
vm:~ #
```

And the lsblk utility  also shows you pmem devices.

```
vm:~ # lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
fd0      2:0    1    4K  0 disk
sr0     11:0    1 1024M  0 rom
vda    253:0    0   40G  0 disk
├─vda1 253:1    0    2G  0 part [SWAP]
├─vda2 253:2    0 15.7G  0 part /tmp
└─vda3 253:3    0 22.3G  0 part /home
pmem0  259:0    0   16G  0 disk
vm:~ #
```

You can use the above scenario for instance to test back-ported patches or run
the [NVDIMM test suite](https://lwn.net/Articles/654071/).

