# AX55 25.12 builder

GitHub-Actions builder for **TP-Link Archer AX55 v1** images on plain
**openwrt-25.12**, consuming the published AX55 patch set exactly the way a
downstream builder does:

```
openwrt/openwrt @ openwrt-25.12
  + ax55-v1-openwrt-2512-full.patch      (from kuncy7/openwrt-ax55-v1, src-2512/)
  + board-tplink_ax55v1.{ipq5018,qcn6122}
```

Its main job, besides producing images, is **clean-room verification of the
patch set**. The workflow fails — loudly, before publishing anything — if:

- any hunk of the patch does not apply (`git apply` is atomic),
- the ethernet symbols are missing from `ipq50xx/config-default` after
  patching,
- the built kernel `.config` has any of `CONFIG_STMMAC_ETH`,
  `CONFIG_STMMAC_PLATFORM`, `CONFIG_DWMAC_IPQ5018`, `CONFIG_PCS_QCA_UNIPHY`,
  `CONFIG_PTP_1588_CLOCK` missing **or demoted to `=m`**
  (`scripts/check-kernel-config.sh`),
- the produced sysupgrade image does not contain the DWMAC driver
  (`scripts/check-image.sh` unpacks the FIT kernel and greps it).

The last two guard against the known failure mode where a silently rejected
config hunk still yields a bootable image whose DSA switch cannot register
(`rtl8365mb: unable to register switch` — no `eth0`, no conduit).

## The `guard-all-kmods` job

A separate job covers a failure the gates above are blind to, because it only
appears in *someone else's* configuration. Our builds do not select every
kernel module; a downstream builder shipping a full package repository does,
and that pulls in `kmod-ptp`. `STMMAC_ETH` depends on
`PTP_1588_CLOCK_OPTIONAL`, which follows `PTP_1588_CLOCK` down to `=m` — so
kconfig demotes `STMMAC_ETH`, `STMMAC_PLATFORM` and `DWMAC_IPQ5018` to modules
without a word. Nothing packages the resulting `.ko` files, the build still
succeeds, and the image comes up with no `eth0`.

The job re-runs `prepare-build.sh` with `devices/*/config.all-kmods` appended
(`CONFIG_ALL_KMODS=y`), builds only as far as `target/linux/compile`, and
asserts the symbols are still `=y`. It produces no image. A failure means the
patch set is broken *for downstream consumers* while our own release remains
valid — so it reports loudly but does not block publishing.

## How it runs

- **push** to `builder.yml`, `devices/`, `patches/`, `scripts/` or the
  workflow → always builds;
- **manual** (`Run workflow`) → always builds;
- **daily cron** → builds only when `openwrt-25.12` **or**
  `kuncy7/openwrt-ax55-v1` moved since the last release.

Successful builds are published as releases (`ax55-2512-<timestamp>-<run>`),
the newest 3 are kept.

## Layout

| path | purpose |
|---|---|
| `builder.yml` | the single file to edit: upstream, sources repo, device, release policy |
| `devices/tplink_archer-ax55-v1/config` | OpenWrt seed config (target + LuCI + diagnostics) |
| `devices/*/config.all-kmods` | fragment for the guard job, appended via `CONFIG_FRAGMENT` |
| `devices/*/files/` | optional rootfs overlay |
| `patches/` | optional extra local patches (applied after the published set) |
| `scripts/check-image.sh` | standalone image verifier — also usable locally: `./scripts/check-image.sh <sysupgrade.bin>` |
| `scripts/check-kernel-config.sh` | asserts the ethernet symbols are `=y`, not `=m`: `./scripts/check-kernel-config.sh <openwrt_dir>` |

Derived from
[JuliusBairaktaris/Qualcommax_NSS_Builder](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder)
via [kuncy7/aw1000-nss-builder](https://github.com/kuncy7/aw1000-nss-builder),
with the NSS parts removed and the verification stages added.
