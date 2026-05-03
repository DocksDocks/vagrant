# Papirus-Dark Icon Inheritance Gap

<constraint>
Papirus-Dark inherits from `breeze-dark,hicolor` — NOT from Papirus. Icons that exist only in Papirus (like `utilities-terminal.svg`) are unreachable by Papirus-Dark. The hicolor user overlay is the correct fix; do not modify package-managed icon directories.
</constraint>

## Root Cause

The `Inherits=` line in Papirus-Dark's `index.theme` specifies `breeze-dark,hicolor` as the inheritance chain. It does NOT include `Papirus`. This means any icon present in Papirus but absent in both `breeze-dark` and `hicolor` is invisible to GTK when Papirus-Dark is the active theme.

`utilities-terminal.svg` — used by Tilix's "Close terminal?" dialog — is a Papirus-specific icon. Result: Tilix logs `[warning] closedialog.d:88: Could not load icon for 'utilities-terminal'` on every dialog render.

Source: `scripts/41-xfce-theme.sh:25-32` (comment block)

## The Fix: User-XDG hicolor Overlay

`hicolor` is GTK's universal fallback theme — every GTK app falls back to it when the active theme doesn't have an icon. A user-scoped overlay at `~/.local/share/icons/hicolor/` adds icons to the hicolor fallback without modifying package-managed files.

```bash
ICON_DST=/home/vagrant/.local/share/icons/hicolor
ICON_SRC=/usr/share/icons/Papirus
for size in 16x16 22x22 24x24 32x32 48x48 64x64; do
  mkdir -p "$ICON_DST/$size/apps"
  ln -sfn "$ICON_SRC/$size/apps/utilities-terminal.svg" \
          "$ICON_DST/$size/apps/utilities-terminal.svg"
done
mkdir -p "$ICON_DST/scalable/apps"
ln -sfn "$ICON_SRC/64x64/apps/utilities-terminal.svg" \
        "$ICON_DST/scalable/apps/utilities-terminal.svg"
[ -e "$ICON_DST/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICON_DST/"
gtk-update-icon-cache -q -f "$ICON_DST" >/dev/null 2>&1 || true
```

Source: `scripts/41-xfce-theme.sh:33-47`

## Why Symlinks, Not Copies

Symlinks into `/usr/share/icons/Papirus/` automatically track future Papirus package updates. If Papirus changes `utilities-terminal.svg`, the symlink picks up the new version without re-provisioning.

The `|| true` on `gtk-update-icon-cache` is correct — cache rebuild failure is non-fatal (the icon still resolves, just more slowly via directory scan).

## Survives Package Upgrades

- `apt upgrade papirus-icon-theme`: symlink targets update automatically.
- `apt remove papirus-icon-theme`: symlinks become dangling — GTK falls back to a missing icon (the original problem). This is acceptable since Papirus is a required installed package.
- `apt upgrade papirus-dark`: same as papirus-icon-theme (same package).

User-scoped `~/.local/share/icons/hicolor/` is never touched by apt.

## index.theme Requirement

`gtk-update-icon-cache` requires an `index.theme` file in the root of the hicolor directory to write a valid cache. The check-and-copy at `scripts/41-xfce-theme.sh:44` handles this:

```bash
[ -e "$ICON_DST/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICON_DST/"
```

## Gotchas

**Adding a new icon for a new app**: repeat the same pattern — `ln -sfn /usr/share/icons/Papirus/$size/apps/$icon.svg $ICON_DST/$size/apps/$icon.svg` for each size, then `gtk-update-icon-cache`. Do not add icons to `/usr/share/icons/hicolor/` directly — that is package-managed.

**`gtk-update-icon-cache` must run AFTER all symlinks are created**: if it runs partway through, some icons are in the cache and some aren't — but the next GTK icon lookup will rescan if the cache is stale relative to the directory mtime. Running it once at the end is correct.

**scalable variant**: the loop covers `16x16` through `64x64` explicitly; `scalable` is handled separately with a copy of the `64x64` source. Some themes only provide scalable icons — check Papirus for the specific icon before assuming sized PNGs exist.
