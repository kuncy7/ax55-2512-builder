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
- the built kernel `.config` lacks `CONFIG_DWMAC_IPQ5018` / `CONFIG_STMMAC_ETH`
  / `CONFIG_PCS_QCA_UNIPHY`,
- the produced sysupgrade image does not contain the DWMAC driver
  (`scripts/check-image.sh` unpacks the FIT kernel and greps it).

The last two guard against the known failure mode where a silently rejected
config hunk still yields a bootable image whose DSA switch cannot register
(`rtl8365mb: unable to register switch` — no `eth0`, no conduit).

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
| `devices/*/files/` | optional rootfs overlay |
| `patches/` | optional extra local patches (applied after the published set) |
| `scripts/check-image.sh` | standalone image verifier — also usable locally: `./scripts/check-image.sh <sysupgrade.bin>` |

Derived from
[JuliusBairaktaris/Qualcommax_NSS_Builder](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder)
via [kuncy7/aw1000-nss-builder](https://github.com/kuncy7/aw1000-nss-builder),
with the NSS parts removed and the verification stages added.
