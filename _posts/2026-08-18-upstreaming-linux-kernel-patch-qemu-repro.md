---
title: "Upstreaming to the Linux Kernel: A Real Bug Fix and the QEMU Repro Behind It"
date: 2026-08-18
categories: [Kernel, Linux]
tags: [linux-kernel, kernel-development, qemu, c, open-source, driver, staging-tree]
---

<!--
TODO (write this section): the setup — Emperatriz project, working through Greg KH's
staging tree with the Linux Foundation "Beginners Guide to Linux Kernel Development",
why you picked this as a way to get real upstream contribution experience.
Resources you used:
- https://trainingportal.linuxfoundation.org/learn/course/a-beginners-guide-to-linux-kernel-development-lfd103/
- https://git.kernel.org/pub/scm/linux/kernel/git/gregkh/staging.git/
- https://kernelnewbies.org/FirstKernelPatch
-->

## The Bug

<!-- TODO: explain investigate_read_descriptor() in xircom_cb.c, the 11-bit packet
length field, why subtracting 4 for the CRC can underflow, and what that underflow
does once it reaches skb_put_data(). -->

The fix, as submitted:

```diff
diff --git a/drivers/net/ethernet/dec/tulip/xircom_cb.c b/drivers/net/ethernet/dec/tulip/xircom_cb.c
index e5d2ede13845..62c64da1c8fa 100644
--- a/drivers/net/ethernet/dec/tulip/xircom_cb.c
+++ b/drivers/net/ethernet/dec/tulip/xircom_cb.c
@@ -1110,6 +1110,11 @@ investigate_read_descriptor(struct net_device *dev, struct xircom_private *card,
 					/* minus 4, we don't want the CRC */
 		struct sk_buff *skb;

+		if (pkt_len < 0) {
+			dev->stats.rx_length_errors++;
+			goto out;
+		}
+
 		if (pkt_len > 1518) {
 			netdev_err(dev, "Packet length %i is bogus\n", pkt_len);
 			pkt_len = 1518;
```

## Reproducing It Without the Hardware

<!-- TODO: explain the core problem — you don't own a Xircom CardBus NIC, so you
need to prove the fix without physical hardware. Walk through why xircom_cb only
binds to PCI ID 115d:0003, and how you attach a QEMU-emulated "tulip" NIC
(DEC 21143, PCI ID 1011:0019) and force-bind the driver to it via new_id. -->

```sh
# Boots a vng VM with an extra QEMU-emulated "tulip" NIC (DEC 21143,
# PCI ID 1011:0019) attached alongside vng's own default networking.
#
# xircom_cb.c only matches PCI ID 115d:0003 (Xircom), so it will NOT
# bind to this device automatically. Once booted, inside the guest:
#
#   lspci -nn                                        # confirm 1011:0019 is present
#   echo "1011 0019" > /sys/bus/pci/drivers/xircom_cb/new_id
#   dmesg | tail -30                                  # see whether probe() succeeds
#
# Networking backend is "socket" (listen mode), NOT "user"/SLIRP --
# SLIRP resynthesizes well-formed frames and cannot deliver a
# deliberately malformed/undersized one.
```

<!-- TODO: note the SLIRP limitation explicitly here — this is a good technical
detail: why "user" networking mode in QEMU can't be used to deliver a deliberately
malformed/undersized frame, and what "socket,listen=" mode gets you instead. -->

## Sanity-Booting the Patched Kernel

<!-- TODO: describe scripts/boot.sh and why a second, simpler repro script exists
for patches where a full hardware-accurate repro isn't feasible (see patch 003,
the i915/lspcon one — vng has no way to emulate a DP++ port + LSPCON adaptor, so
that script only proves the kernel builds and boots, not that the fix behaves as
expected on real dual-GPU hardware). -->

```sh
KERNEL_DIR=/path/to/staging

case $1 in
	run)
		vng --run "$KERNEL_DIR" --debug
		;;
	gdb)
		vng --run "$KERNEL_DIR" --gdb
		;;
	*)
		echo "usage: $0 {run|gdb}"
		exit 1
		;;
esac
```

## Sending the Patch

<!-- TODO: describe the submission process — checkpatch.pl, git send-email,
the commit message conventions (Signed-off-by, Fixes: tag if applicable),
and link to the actual submission on lore.kernel.org:
https://lore.kernel.org/all/alPVQEAdoUFjHiJo@ThinkPad-P15/ -->

## What's Next

<!-- TODO: next patches in the pipeline (002-net-psp, 003-i915-lspcon,
004-net-micrel-ksz884x), and what you learned that changes how you approach
the next one. -->
