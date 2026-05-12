# VMSVGA Graphics Controller Rationale

<constraint>
Use VMSVGA. Not VBoxSVGA (Windows-only, black screen on Linux). Not VBoxVGA 3D (deprecated since 6.1). Not "enable 3D acceleration" (regresses compositing + Chrome). These constraints are collectively load-bearing.
</constraint>

## Controller Comparison

| Controller | Linux support | VRAM ceiling | Compositing | Notes |
|---|---|---|---|---|
| VMSVGA | Yes (`vmwgfx`, mainline) | 256 MB (hard) | Works with `vblank_mode=off` | Correct choice for this setup |
| VBoxSVGA | No (`vboxvideo` may not load) | 128 MB | Black screen from boot | Windows-only |
| VBoxVGA | Partial | 256 MB | Deprecated since VBox 6.1 | Not recommended |

Source: `Vagrantfile:105`, `CLAUDE.md` (Black screen after login, Black screen from boot)

## VMSVGA Driver Chain

VMSVGA → `vmwgfx` kernel driver → software rendering via `llvmpipe`/`SVGA3D`/`virgl`

These are the GL renderers exposed to userspace. xfwm4 checks the GL renderer string in `src/compositor.c` and marks `llvmpipe`, `SVGA3D`, and `virgl` as unsupported for vblank — but not for compositing itself. Result: compositing works fine; vblank sync does not.

Fix: `vblank_mode=off` in `assets/xfwm4.xml:7`. Compositing remains enabled (`use_compositing=true` at line 6).

## 256 MB VRAM Ceiling

VirtualBox silently clamps VMSVGA VRAM at 256 MB regardless of the configured value.

```ruby
vb.customize ["modifyvm", :id, "--vram", "256"]
```

Source: `Vagrantfile:104`. References: VBox forum [#107806](https://forums.virtualbox.org/viewtopic.php?t=107806), [#81370](https://forums.virtualbox.org/viewtopic.php?t=81370).

"GPU memory" in this context is host RAM used as a framebuffer — it is NOT GPU acceleration. There is no path to real GPU acceleration under VMSVGA on Linux without enabling 3D acceleration, which is prohibited.

## Why 3D Acceleration Is Prohibited

Enabling `--accelerate3d on` causes two regressions:

1. **xfwm4 compositing black screen after login**: 3D acceleration changes the GL path xfwm4 takes for compositing in a way that fails silently and leaves the desktop black after autologin. Source: `CLAUDE.md` (Black screen after login).

2. **Chrome GPU probing worsens**: Chrome's GPU process probes the 3D-accelerated path, encounters failures specific to the Linux guest + VMSVGA combination, and deadlocks more readily than without 3D acceleration. Source: `CLAUDE.md` (Chrome freezes).

Both regressions are documented in CLAUDE.md and were discovered via `vagrant destroy -f && vagrant up` testing (commits `f00bff2` → `159b6bf` on 2026-04-03).

## Historical Black Screen Fix

The original black screen root cause was VBoxSVGA (the wrong controller for Linux). The fix was switching to VMSVGA in commits `f00bff2` → `159b6bf`. The compositor-disable workaround added previously is now unnecessary but `vblank_mode=off` is still required for the GL renderer warning. Source: `CLAUDE.md` (Black screen after login, Common Issues).

## Gotchas

**Setting `--vram` above 256**: no error is shown in `vagrant up` output; VirtualBox silently clamps. The `VBoxManage showvminfo` output shows the actual (clamped) value.

**Switching to VBoxSVGA "to test"**: the VM will not display anything on Linux — no recovery path except reverting the Vagrantfile and running `vagrant destroy -f && vagrant up`. The `vboxvideo` kernel module is not present in the Debian 13 default kernel.

**`vblank_mode=off` is per-user config**: it lives in `assets/xfwm4.xml` deployed to `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml` by `scripts/41-xfce-theme.sh:19`. If the user deletes this file or resets XFCE settings, the next XFCE start will use the system default which does not include `vblank_mode=off`.
