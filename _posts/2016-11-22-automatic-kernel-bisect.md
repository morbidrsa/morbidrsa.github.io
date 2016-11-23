---
layout: post
title:  "Automatic kernel bisection with Qemu"
date:   2016-11-22 10:25:00
tags:
- kernel
- qemu
- git
---

Recently we had a report for an interesting [problem][1] in the Linux kernel's
SCSI subsystem, which was fixed in recent kernels but older kernels lacked the
fix so we needed to identify the fix and then back-port it to the stable kernels
the distributions and thus ultimately the users used.

I thought, as we have a fairly easy reproducer posted by the reporter let's do
some automated testing here (Disclaimer: I'm a huge fan of test automation).

In theory this should be relatively easy we'd need the following:

1.  git
2.  Qemu
3.  the reproducer as /bin/init inside an initramfs
4.  a kernel .config which is as minimal as possible (for fast reboots)

So let's start with the reproducer as PID 1. Unfortunately we cannot just copy
over the code posted on the mailinglist but have to do some kind of *framework*
around it. We need to:

1. Mount /proc
2. Mount /sys
3. Mount /dev
4. Run the test
5. Print PASS or FAIL (or something in the likes)
6. Reboot

Bullet points 1 - 3 are fairly easy to accomplish, so I've already pushed
them out to [github](https://github.com/morbidrsa/boot-test/) and tagged
them as [v0.1](https://github.com/morbidrsa/boot-test/releases/tag/v0.1)
of the repository. For completeness (and as it's just a few lines of Code)
here's the whole beauty:

~~~c
#include <sys/mount.h>

#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	int err;

	err = mount("none", "/proc", "proc", 0, NULL);
	if (err)
		goto panic;
	err = mount("none", "/sys", "sysfs", 0, NULL);
	if (err)
		goto panic;
	err = mount("none", "/dev", "devtmpfs", 0, NULL);
	if (err)
		goto panic;

	umount("/dev");
	umount("/sys");
	umount("/proc");

panic:
	exit(EXIT_FAILURE);
}
~~~


The next thing we want to do is reboot the VM once the tests are done (bullet
point 6 above) and we have unmounted /proc, /sys and /dev again. This is
[v0.2](https://github.com/morbidrsa/boot-test/releases/tag/v0.2) in the github
repository. Again, here's the relevant piece of code:

~~~c
        umount("/sys");
	umount("/proc");

	reboot(RB_POWER_OFF);
panic:
	exit(EXIT_FAILURE);
}
~~~

The *reboot* function needs the following two headers, so be sure to include
them as well:

~~~c
#include <sys/reboot.h>
#include <unistd.h>
~~~


The next thing I'd like to take care of is item number 5. We know we need a
test function and it has to return either pass or fail. For the return values
I choose an *enum* called *test_tesult* which gives us the following function
template for our test case:

~~~c
enum test_result { TEST_PASS, TEST_FAIL };

enum test_result do_test(void)
{
	return TEST_PASS;
}
~~~

And we "just" have to evaluate it in *main*

~~~c
        umount("/proc");

        ret = do_test();
        if (ret == TEST_PASS)
                printf("PASS\n");
        else
                printf("FAIL\n");

        reboot(RB_POWER_OFF);
~~~

This is [v0.3](https://github.com/morbidrsa/boot-test/releases/tag/v0.3) in
the github repository.


So as a final step before adding the actual test code, we need to be able to
execute the test init. Therefore we have to place it into an initramfs which
we can pass to Qemu. The following snippet from the Makefile builds the
initramfs:

~~~make
initramfs:  $(NAME)
        mkdir -p initramfs/{bin,proc,dev,sys,lib64}
        install -m 755 $(NAME) initramfs/bin/
        install -m 755 /lib64/$(shell ldd init | grep -E -o "libc.so.[0-9]" | head -1) initramfs/lib64/
        install -m 755 /lib64/$(shell ldd init | grep -o -E "ld-linux-x86-64.so.[0-9]+") initramfs/lib64/
        cd initramfs && find . | cpio -H newc -o | gzip > ../initramfs.img
~~~

This is [v0.4](https://github.com/morbidrsa/boot-test/releases/tag/v0.4) in
the github repository.

Now we can run our "test" in qemu (I've built a minimal kernel for it not
requiring anything but the configuration needed to reproduce the bug).

~~~bash
qemu-kvm -smp 8 -m 2048 -nographic -serial mon:stdio -kernel \
	bzImage -initrd initramfs.img -append \
	"rdinit=/bin/init console=ttyS0 quiet"
PASS
[    0.594992] reboot: Power down
~~~

Now we're at the point where we can implement the actual reproducer.

[1]: http://www.spinics.net/lists/linux-scsi/msg102097.html
