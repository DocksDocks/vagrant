# dconf compile Rationale (Provisioning Without a Session Bus)

<constraint>
Use `dconf compile OUTPUT KEYFILEDIR` — not `dconf load`, not `gsettings set`, not `dbus-run-session`. During provisioning there is no D-Bus session bus, and `dbus-run-session` consistently fails with socket permission errors under bento/debian-13's `tmp.mount`. Source: `scripts/60-apps-tilix-mousepad.sh:14-26`.
</constraint>

## Why dconf load Fails

`dconf load` and `gsettings set` communicate with `dconf-service` over the session bus (`DBUS_SESSION_BUS_ADDRESS`). During Vagrant shell provisioning:

- No login session → no `pam_systemd` → no user manager → no `XDG_RUNTIME_DIR`
- `dbus-run-session` spawns a temporary bus, but under bento/debian-13's `tmp.mount` the daemon cannot bind a socket at `/tmp/dbus-*`: `Failed to bind socket "/tmp/dbus-…": Permission denied`

Multiple workarounds were attempted and failed: `loginctl enable-linger`, `env -u XDG_RUNTIME_DIR`, `runuser -l`, pre-creating `/run/user/$UID`. The third call (Tilix `dconf load`) consistently failed regardless. Source: `scripts/60-apps-tilix-mousepad.sh:14-26`.

## How dconf compile Works

`dconf compile OUTPUT KEYFILEDIR` writes a binary GVDB (GLib Variant Database) directly to disk. This is how system-wide `/etc/dconf/db/*` databases are built. The user database at `~/.config/dconf/user` uses the same format.

```bash
KEYFILES_DIR=$(mktemp -d)
trap 'rm -rf "$KEYFILES_DIR" /tmp/tilix.dconf' EXIT

cat >"$KEYFILES_DIR/00-mousepad" <<'EOF'
[org/xfce/mousepad/preferences/view]
show-line-numbers=true
color-scheme='solarized-dark'
EOF

# ... populate more keyfiles ...

runuser -u vagrant -- dconf compile /home/vagrant/.config/dconf/user "$KEYFILES_DIR"
```

Source: `scripts/60-apps-tilix-mousepad.sh:38-62`

`runuser -u vagrant` ensures the binary GVDB is owned by vagrant and uses vagrant's GLib context.

## Keyfile Syntax Requirements

Keyfiles use absolute GSettings schema paths as section headers:

| dconf-load syntax | keyfile syntax (for compile) |
|---|---|
| `[/]` | `[com/gexperts/Tilix]` |
| `[profiles/UUID]` | `[com/gexperts/Tilix/profiles/UUID]` |
| `[org/xfce/mousepad/preferences/view]` | `[org/xfce/mousepad/preferences/view]` (already absolute) |

The sed rewrite converts `assets/tilix.dconf` from dconf-load to keyfile:

```bash
sed -e 's|^\[/\]$|[com/gexperts/Tilix]|' \
    -e 's|^\[\(profiles/[^]]*\)\]$|[com/gexperts/Tilix/\1]|' \
    /tmp/tilix.dconf > "$KEYFILES_DIR/10-tilix"
```

Source: `scripts/60-apps-tilix-mousepad.sh:53-55`

## Compile Replaces the Entire Database

`dconf compile` writes a completely new binary GVDB — it does NOT merge with existing content. Every keyfile in the directory is compiled together into one output. Consequences:

- All Tilix and Mousepad settings from keyfiles are written in one shot.
- Any user-changed settings in the VM are overwritten on re-provision.
- This is acceptable because both apps' settings live in a single payload, and user changes during provisioning would be wiped anyway.

Source: `scripts/60-apps-tilix-mousepad.sh:29-31` (comment in script).

## Do NOT Add || true

The `dconf compile` call has no `|| true`:

```bash
# No `|| true`: this is the custom palette + font. Silent failure means the
# user opens Tilix, sees the default ugly theme, and assumes the box is broken.
runuser -u vagrant -- dconf compile /home/vagrant/.config/dconf/user "$KEYFILES_DIR"
```

Source: `scripts/60-apps-tilix-mousepad.sh:59-62`. Fail loud so a regression is visible in the provision log.

## Gotchas

**Keyfile directory permissions**: `chown -R vagrant:vagrant "$KEYFILES_DIR"` must run before `dconf compile` (as `runuser -u vagrant`) — otherwise vagrant cannot read the keyfiles. Source: `scripts/60-apps-tilix-mousepad.sh:58`.

**Keyfile filename ordering**: files in KEYFILEDIR are processed in sort order. Use numeric prefixes (`00-mousepad`, `10-tilix`) to ensure deterministic merge order when two keyfiles have overlapping keys.

**`dconf update` vs `dconf compile`**: `dconf update` recompiles system databases in `/etc/dconf/db/`; `dconf compile` writes a single output file. Don't confuse them — `dconf update` does not touch `~/.config/dconf/user`.
