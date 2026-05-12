# fetch_asset Helper — Dual-Mode Asset Deployment

<constraint>
Always use `fetch_asset REL DEST` to deploy static config files — never use bare `cp` or `curl` inline in scripts. Both modes (local-dev and remote) are handled transparently.
</constraint>

## What It Does

`fetch_asset REL DEST` places a file from `assets/REL` at `DEST` on the guest. Defined in `scripts/_lib.sh:21-31`.

**Local-dev mode** (when `VAGRANT_SCRIPTS_DIR` is set):
```bash
install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
```
Source files are read from the repo mounted at `/vagrant/assets/`. `install -D` creates parent directories automatically.

**Remote mode** (no `VAGRANT_SCRIPTS_DIR`):
```bash
install -d "$(dirname "$dest")"
curl -fsSL --retry 4 --retry-delay 2 \
  "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
  -o "$dest"
```
Parent directory is created, then the file is fetched from `raw.githubusercontent.com` at the configured ref. `curl -f` aborts on HTTP 4xx/5xx; `--retry 4 --retry-delay 2` handles transient network failures.

## Full Implementation

```bash
fetch_asset() {
  local rel="$1" dest="$2"
  if [[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]; then
    install -D -m 0644 "/vagrant/assets/${rel}" "$dest"
  else
    install -d "$(dirname "$dest")"
    curl -fsSL --retry 4 --retry-delay 2 \
      "https://raw.githubusercontent.com/${SCRIPTS_REPO}/${SCRIPTS_REF}/assets/${rel}" \
      -o "$dest"
  fi
}
```

Source: `scripts/_lib.sh:21-31`

## Usage Examples

```bash
# Deploy an XFCE config XML to the user perchannel dir
fetch_asset xfwm4.xml /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# Deploy a systemd unit file
fetch_asset systemd/vbox-clipboard.service /home/vagrant/.config/systemd/user/vbox-clipboard.service

# Deploy Chrome managed policy
fetch_asset chrome-policy-no-gpu.json /etc/opt/chrome/policies/managed/no-gpu.json
```

Sources: `scripts/41-xfce-theme.sh:18-19`, `scripts/50-vboxclient-supervisor.sh:22`, `scripts/40-xfce-base.sh:84`

## Subdirectory Assets

Assets in `assets/systemd/` and `assets/apt/` use the subdirectory prefix as the `rel` arg:

```bash
fetch_asset systemd/vbox-draganddrop.service /home/vagrant/.config/systemd/user/vbox-draganddrop.service
```

Source: `scripts/50-vboxclient-supervisor.sh:23`

## Mode Switching

| Mode | Trigger | Asset source |
|---|---|---|
| Local-dev | `VAGRANT_SCRIPTS_DIR` is set + file exists at `/vagrant/assets/REL` | `/vagrant/assets/REL` |
| Remote | `VAGRANT_SCRIPTS_DIR` unset OR file not found locally | `raw.githubusercontent.com/$SCRIPTS_REPO/$SCRIPTS_REF/assets/REL` |

## Gotchas

**File missing from `assets/`**: in local-dev mode, if the file doesn't exist at `/vagrant/assets/REL`, the condition `[[ -n "${VAGRANT_SCRIPTS_DIR:-}" && -f "/vagrant/assets/${rel}" ]]` is false and it falls through to the remote curl — silently fetching from GitHub even in local-dev mode. Always add new assets to `assets/` before using them in scripts.

**Default mode for new assets**: remote mode does NOT create parent directories recursively with `install -D`; it uses `install -d "$(dirname "$dest")"` which creates only one level. If the path requires multiple new directories, the parent `mkdir -p` call must precede `fetch_asset`. Source: `scripts/40-xfce-base.sh:35-36` for the `mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml` pattern before calling fetch_asset.

**Permission**: `fetch_asset` always sets mode `0644` in local-dev mode. If a deployed file needs different permissions (e.g. 0755 for a script), add `chmod` immediately after `fetch_asset`. Source: `scripts/50-vboxclient-supervisor.sh:30` (`chmod 0755`), `scripts/40-xfce-base.sh:85` (`chmod 0644`).
