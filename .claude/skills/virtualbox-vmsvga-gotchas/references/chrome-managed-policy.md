# Chrome Managed Policy (No GPU)

<constraint>
Deploy managed policy via `/etc/opt/chrome/policies/managed/no-gpu.json`. This is the official Google mechanism — it survives `apt upgrade google-chrome-stable` and applies to every Chrome launch path. Do NOT use command-line flags or user-level preferences (both are overridable by Chrome itself).
</constraint>

## Deployment

```bash
fetch_asset chrome-policy-no-gpu.json /etc/opt/chrome/policies/managed/no-gpu.json
chmod 0644 /etc/opt/chrome/policies/managed/no-gpu.json
```

Source: `scripts/40-xfce-base.sh:84-85`

Policy content:

```json
{
  "HardwareAccelerationModeEnabled": false
}
```

Source: `assets/chrome-policy-no-gpu.json:1-3`

## Why This Is Needed

VMSVGA has no real GPU. Chrome's hardware-accelerated paths probe it and deadlock under combined load: Next.js dev server + Chrome + Claude Code. The freeze is non-deterministic and appears to be a GPU process deadlock specific to VMSVGA (Oracle VirtualBox bug [#15417](https://www.virtualbox.org/ticket/15417)). Source: `scripts/40-xfce-base.sh:80-83`, `CLAUDE.md` (Chrome freezes).

## Verification

```
chrome://policy
```
Row `HardwareAccelerationModeEnabled`, Scope: `Machine`, Status: OK, Value: `false`.

```
chrome://gpu
```
Every "Graphics Feature Status" row reads "Software only, hardware acceleration unavailable" or "Disabled".

## Alternative Approaches (Rejected)

| Approach | Why rejected |
|---|---|
| `--disable-gpu` command-line flag | Only applies to that launch; doesn't affect Chrome launched from XFCE menu or other paths |
| User preference in Chrome settings | User-overridable; Chrome may reset on upgrade |
| VirtualBox 3D acceleration | Makes Chrome GPU probing worse on Linux guests; regresses xfwm4 compositing |

## Gotchas

**Policy file must be in `managed/` not `recommended/`**: `managed/` is machine-level and cannot be overridden by user settings. `recommended/` can be overridden. Use `managed/`. Source: Google Chrome Enterprise docs.

**`apt upgrade google-chrome-stable` preserves policy**: managed policy files under `/etc/opt/chrome/policies/` are not touched by the Chrome package — they are configuration, not part of the package payload.

**Policy not showing at `chrome://policy`**: the directory `/etc/opt/chrome/policies/managed/` may not have been created by `fetch_asset`. Check that `scripts/40-xfce-base.sh:84` was executed (it relies on `fetch_asset` which calls `install -d` on the parent directory first in remote mode).
