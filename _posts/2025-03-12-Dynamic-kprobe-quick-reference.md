---
layout: post
title: "Dynamic kprobe quick reference"
date: 2025-03-12 13:51M:41
tags:
- btrfs
- kernel
---

At the moment I'm debugging a NULL pointer dereference from a report on the
linux-btrfs mailinglist and to help me debugging it I thought of adding a
kprobe to the respective function. As I always forget the how to dynamically
add a kprobe to the kernel, this post serves as a memory reference for myself
and hopefully also is of some use for others.

The function in question is `__btrfs_add_free_space_zoned()`:

```c
static int __btrfs_add_free_space_zoned(struct btrfs_block_group *block_group,
					u64 bytenr, u64 size, bool used)
{
	struct btrfs_space_info *sinfo = block_group->space_info;
	struct btrfs_free_space_ctl *ctl = block_group->free_space_ctl;
	u64 offset = bytenr - block_group->start;
	u64 to_free, to_unusable;
	int bg_reclaim_threshold = 0;
	bool initial;
	u64 reclaimable_unusable;

	spin_lock(&block_group->lock);

	initial = ((size == block_group->length) && (block_group->alloc_offset == 0));
	WARN_ON(!initial && offset + size > block_group->zone_capacity);
	if (!initial)
		bg_reclaim_threshold = READ_ONCE(sinfo->bg_reclaim_threshold);

    /* [...] */

	return 0;
}

```

The Null-pointer dereference triggers because of the `btrfs_space_info`
pointer is NULL, but `initial` is false. So we're interested in `size`,
`block_group->length` and `block_group->alloc_offset`.

Next, let's check if we can actually trace the function (i.e. it's not
inlined by the compiler):

```
virtme-zns:~ # grep __btrfs_add_free_space_zoned /proc/kallsyms
ffffffff817256d0 t __pfx___btrfs_add_free_space_zoned
ffffffff817256e0 t __btrfs_add_free_space_zoned
```

Taking a quick look into `arch/x86/entry/calling.h` for the x86\_64 calling
convention we get:

```
 x86 function call convention, 64-bit:
 -------------------------------------
  arguments           |  callee-saved      | extra caller-saved | return
 [callee-clobbered]   |                    | [callee-clobbered] |
 ---------------------------------------------------------------------------
 rdi rsi rdx rcx r8-9 | rbx rbp [*] r12-15 | r10-11             | rax, rdx [**]

```

So the `struct btrfs_block_group` is in RDI, `bytenr` will be in RSI, `size`
in RDX and `used` in RCX.

Next we need to grab the offsets for `length` and `alloc_offset` from the
start of `struct btrfs_block_group`. That's easiest with `pahole`:

```
johannes@nuc:linux (btrfs-for-next)$ pahole -C btrfs_block_group vmlinux | grep -e alloc_offset -e length
        u64                        length;               /*    96     8 */
        u64                        alloc_offset;         /*   840     8 */
```

So our `length` will be in RDI+96 and `alloc_offset` in RDI+840. Note: This is
in decimal.

The syntax for `kprobe_events` is %REG and +OFFSET(%REG). Additionally we can
specify formatting options, all non-pointer arguments I want to have in
decimal. The syntax for that then is %REG:u64 for a 64 Bit unsigned integer.
So in the end we get:

```
virtme-zns:~ # echo 'p:myprobe __btrfs_add_free_space_zoned block_group=%di length=+96(%di):u64 alloc_offset=+840(%di):u64 bytenr=%si:u64 size=%dx:u64 used=%cx:u8' >> /sys/kernel/debug/tracing/kprobe_events
```

Next we need to enable the kprobe and the ftrace subsystem and run some tests:

```
virtme-zns:~ # echo 1 > /sys/kernel/debug/tracing/events/kprobe/myprobe/enable
virtme-zns:~ # echo 1 > /sys/kernel/debug/tracing/tracing_on
virtme-zns:~ # dd if=/dev/random of=/mnt/test bs=128k count=1000 oflag=sync
1024+0 records in
1024+0 records out
134217728 bytes (134 MB, 128 MiB) copied, 5.91738 s, 22.7 MB/s
```

Then we can grab the trace buffer (and for convenience save it into /tmp):

```
virtme-zns:~ # cat /sys/kernel/debug/tracing/trace >/tmp/trace.txt
virtme-zns:~ # head -n 20 /tmp/trace.txt
# tracer: nop
#
# entries-in-buffer/entries-written: 2123/2123   #P:2
#
#                                _-----=> irqs-off/BH-disabled
#                               / _----=> need-resched
#                              | / _---=> hardirq/softirq
#                              || / _--=> preempt-depth
#                              ||| / _-=> migrate-disable
#                              |||| /     delay
#           TASK-PID     CPU#  |||||  TIMESTAMP  FUNCTION
#              | |         |   |||||     |         |
   kworker/u10:0-378     [001] .....  3903.181095: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888102355400 length=134217728 alloc_offset=0 bytenr=1744830464 size=134217728 used=1
              dd-403     [001] .....  3903.213082: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888101c78800 length=134217728 alloc_offset=180224 bytenr=671236096 size=16384 used=1
              dd-403     [001] .....  3903.213088: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888101c79000 length=134217728 alloc_offset=100581376 bytenr=1040089088 size=16384 used=1
              dd-403     [001] .....  3903.213092: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888102355800 length=134217728 alloc_offset=134217728 bytenr=1407664128 size=16384 used=1
              dd-403     [001] .....  3903.213097: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888102355800 length=134217728 alloc_offset=134217728 bytenr=1428504576 size=16384 used=1
              dd-403     [001] .....  3903.213101: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888102355800 length=134217728 alloc_offset=134217728 bytenr=1448312832 size=16384 used=1
              dd-403     [001] .....  3903.213104: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888102355800 length=134217728 alloc_offset=134217728 bytenr=1449426944 size=16384 used=1
              dd-403     [001] .....  3903.213108: myprobe: (__btrfs_add_free_space_zoned+0x0/0x1c0) block_group=0xffff888102355800 length=134217728 alloc_offset=134217728 bytenr=1467482112 size=16384 used=1
```

Et voila, the kprobe worked! We see several different `block_groups`, the
length all of them is 128M (the zone capacity of the emulated ZNS drive in my
test VM) the used parameter always is `true` and the other values differ.
Looking at the first entry (that is created by the kernel not the `dd` test
case) we see the prerequisites for `initial` being satisfied:

```c
initial = ((size == block_group->length) && (block_group->alloc_offset == 0));
```

In all other cases `initial` will be false.

So far so good, the test worked. Now we need to get the correct offsets in the
bug reporter's kernel and construct the kprobe command accordingly. Luckily
the reporter is using a stock Fedora 41 kernel, so we can grab the offset from
Fedora's kernel debuginfo rpm. As far as I remember, btrfs is built-in in
Fedora so we can get the offsets from vmlinux using pahole.

```
johannes@nuc:tmp$ wget https://kojipkgs.fedoraproject.org//packages/kernel/6.13.5/200.fc41/x86_64/kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm
--2025-03-12 15:57:44--  https://kojipkgs.fedoraproject.org//packages/kernel/6.13.5/200.fc41/x86_64/kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm
Resolving kojipkgs.fedoraproject.org (kojipkgs.fedoraproject.org)... 38.145.60.20, 38.145.60.21
Connecting to kojipkgs.fedoraproject.org (kojipkgs.fedoraproject.org)|38.145.60.20|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 1092996689 (1.0G) [application/x-rpm]
Saving to: ‘kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm’

kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm                                                100%[==============================================================>]   1.02G  4.87MB/s    in 4m 41s

2025-03-12 16:02:27 (3.70 MB/s) - ‘kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm’ saved [1092996689/1092996689]
johannes@nuc:tmp$ rpm2cpio kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm | cpio
-id
8785071 blocks
johannes@nuc:tmp$ ls
kernel-debuginfo-6.13.5-200.fc41.x86_64.rpm  usr
johannes@nuc:tmp$ find usr -name vmlinux
usr/lib/debug/lib/modules/6.13.5-200.fc41.x86_64/vmlinux
johannes@nuc:tmp$ pahole -C 'btrfs_block_group' usr/lib/debug/lib/modules/6.13.5-200.fc41.x86_64/vmlinux | grep -e length -e alloc_offset
        u64                        length;               /*    32     8 */
        u64                        alloc_offset;         /*   520     8 */
```

So we now have the offsets we're interested in, but let's make sure
`__btrfs_add_free_space_zoned()` is actually available and not optimized out:

```
johannes@nuc:tmp$ nm usr/lib/debug/lib/modules/6.13.5-200.fc41.x86_64/vmlinux | grep __btrfs_add_free_space_zoned
ffffffff817a73b0 t __btrfs_add_free_space_zoned.isra.0
ffffffff817a73a0 t __pfx___btrfs_add_free_space_zoned.isra.0
```

That looks good, so the new offsets will be 32 and 520, and the resulting
command line for the reporter will be:

```
echo 'p:myprobe __btrfs_add_free_space_zoned block_group=%di length=+32(%di):u64 alloc_offset=+520(%di):u64 bytenr=%si:u64 size=%dx:u64 used=%cx:u8' >> /sys/kernel/debug/tracing/kprobe_events
```

References:
[Fun with Dynamic Kernel Tracing Events - Steven Rostedt](https://events19.linuxfoundation.org/wp-content/uploads/2017/12/oss-eu-2018-fun-with-dynamic-trace-events_steven-rostedt.pdf)
