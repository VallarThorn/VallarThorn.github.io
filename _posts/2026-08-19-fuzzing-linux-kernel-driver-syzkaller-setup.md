---
title: "Fuzzing a Linux Kernel Driver with Syzkaller: Setting Up Coverage-Guided Fuzzing from Scratch"
date: 2026-08-19
categories: [Fuzzing, Kernel]
tags: [syzkaller, fuzzing, linux-kernel, kasan, kcov, qemu, arm64, kernel-driver]
---

<!--
TODO (write this section): why syzkaller, why this target — fuzzing the Mali GPU
kernel driver (mali_kbase.ko) without owning the physical hardware. Frame the
problem: syzkaller needs a real device node to fuzz through (ioctls on /dev/mali0),
which means the driver's probe() has to actually succeed inside the VM first.
-->

## No Hardware, No Problem: `CONFIG_MALI_NO_MALI`

<!-- TODO: explain the driver's hardware simulation backend and why it lets you
fuzz the ioctl surface without a real GPU. -->

## Getting `probe()` to Fire

The Mali driver is a platform driver — it only binds if the device tree has a
matching node. QEMU's `virt` machine has none, and the driver's fallback fake
platform device is compiled out whenever `CONFIG_OF=y` (always true on arm64).
The fix is to inject a node into the auto-generated device tree:

```bash
gpu@e000000 {
	compatible = "arm,mali-valhall";
	reg = <0x00 0xe000000 0x00 0x200000>;
	interrupts = <0x00 0x60 0x04>,
		     <0x00 0x61 0x04>,
		     <0x00 0x62 0x04>;
	interrupt-names = "JOB", "MMU", "GPU";
};
```

```bash
# dump QEMU's device tree, decompile, inject the node above, recompile
qemu-system-aarch64 -M virt,dumpdtb=virt.dtb -cpu cortex-a57 -smp 4 -m 2048 -nographic
dtc -I dtb -O dts virt.dtb -o virt.dts
# ... inject gpu@e000000 node, then:
dtc -I dts -O dtb virt.dts -o virt-mali.dtb
```

<!-- TODO: explain the symptom without this (module loads, taints kernel, but no
/dev/mali0 ever appears) and how you diagnosed it was a device-tree binding issue
rather than a driver bug. -->

## Kernel Config: What Syzkaller Actually Needs

```
# Coverage (mandatory for syzkaller)
CONFIG_KCOV=y
CONFIG_KCOV_INSTRUMENT_ALL=y
CONFIG_KCOV_ENABLE_COMPARISONS=y

# Debug info (mandatory for symbolization)
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_DEBUG_FS=y

# KASAN: essential -- detects UAF, OOB, heap corruption
CONFIG_KASAN=y
CONFIG_KASAN_INLINE=y

# Namespaces (syzkaller sandbox)
CONFIG_NAMESPACES=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
...

# Disable KASLR for reliable module coverage
# CONFIG_RANDOMIZE_BASE is not set
```

<!-- TODO: explain the tradeoffs you made and why — e.g. UBSAN and LOCKDEP
disabled (boot time / overhead cost vs. what they'd catch), KASLR disabled
specifically because module coverage addresses need to be stable, PANIC_ON_OOPS
so syzkaller reliably catches crashes instead of the kernel limping on. -->

## The Manager Config

```json
{
    "name": "mali-csf",
    "target": "linux/arm64",
    "type": "qemu",
    "sandbox": "none",
    "cover": true,
    "procs": 4,
    "enable_syscalls": [
        "openat$mali",
        "ioctl$KBASE_IOCTL_MEM_ALLOC_EX",
        "ioctl$KBASE_IOCTL_CS_QUEUE_REGISTER",
        "ioctl$KBASE_IOCTL_CS_QUEUE_BIND",
        "ioctl$KBASE_IOCTL_KCPU_QUEUE_ENQUEUE"
        // ... trimmed, full list is ~50 ioctls
    ],
    "no_mutate_syscalls": ["openat$mali"],
    "module_obj": ["/path/to/drivers/gpu/arm/midgard"]
}
```

<!-- TODO: explain why enable_syscalls is an explicit allowlist here rather than
letting syzkaller fuzz the whole syscall surface, why openat$mali is excluded
from mutation, what module_obj buys you for coverage on an out-of-tree module,
and the "sandbox": "none" choice. -->

## Writing the Syscall Descriptions

<!-- TODO: describe the syzlang description file for the Mali ioctls
(dev_mali_csf.txt) — how you derived the struct layouts from the real UAPI
headers rather than guessing, and what happens to fuzzing effectiveness when
a description is wrong (silently rejected ioctls, near-zero new coverage). -->

## Running the Campaign

```bash
./bin/syz-manager -config=mali-csf.cfg
# dashboard at :56701
```

<!-- TODO: what the first hours/days of the campaign looked like, how you read
the dashboard, and where this hands off to syz-viz for coverage visualization
and syz-heuristic for seed prioritization. -->

## What's Next
