#!/usr/bin/env bash
# 41-xfce-theme.sh — XFCE theme (Tokyo Night GTK + Papirus + Noto Sans) + GTK3 headerbar CSS.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${SCRIPTS_REPO:=docksdocks/vagrant}"
: "${SCRIPTS_REF:=main}"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_lib.sh
. "${VAGRANT_LIB_PATH:-/vagrant/scripts/_lib.sh}"

# A personalização "Night Owl" (tema Tokyo Night GTK) é específica do nosso
# alvo Debian. Em Ubuntu (box arm64/UTM) pulamos — fica um XFCE funcional com o
# tema padrão da distro. Ver nota de multi-plataforma no Vagrantfile.
if [ "$(. /etc/os-release && echo "$ID")" != "debian" ]; then
  echo ">> $(. /etc/os-release && echo "$ID") detectado — pulando tema XFCE Night Owl (apenas Debian)."
  exit 0
fi

FORCE="${FORCE_REINSTALL:-0}"

# ── Tokyo Night GTK theme (system-wide, pinned + commit-verified) ──
# No literal "Night Owl" GTK theme exists upstream (Night Owl is a code-editor
# theme — nobody ported it to window chrome). Tokyo Night is the closest
# maintained navy GTK3/4 + xfwm4 theme in the same deep-navy / blue-purple
# family, so it pairs with the Night Owl terminal (assets/tilix.dconf) and
# editor (assets/gtksourceview/night-owl.xml). See plans/0007-night-owl-desktop.md.
#
# Built from SASS by the upstream installer (needs `sassc`, installed in
# 20-packages.sh). We fetch exactly one immutable commit and assert HEAD
# matches it before compiling — same integrity contract as the Colloid pin in
# 72-kate-editor.sh. arc-theme stays installed as the documented revert path.
TOKYONIGHT_PIN=6c340e058e84c1975a038a8e5d1e384477225dc0
if [[ "$FORCE" == "1" ]] || [ ! -d /usr/share/themes/Tokyonight-Dark ]; then
  echo ">> Instalando tema GTK Tokyo Night (pin ${TOKYONIGHT_PIN:0:12})..."
  tmp=$(mktemp -d)
  git init --quiet "$tmp"
  git -C "$tmp" remote add origin https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme
  git -C "$tmp" fetch --depth 1 --quiet origin "$TOKYONIGHT_PIN"
  git -C "$tmp" checkout --quiet FETCH_HEAD
  got="$(git -C "$tmp" rev-parse HEAD)"
  if [ "$got" != "$TOKYONIGHT_PIN" ]; then
    echo "✗ Tokyo Night commit mismatch — expected $TOKYONIGHT_PIN, got $got. Refusing." >&2
    rm -rf "$tmp"; exit 1
  fi
  # Build only the standard dark blue variant → /usr/share/themes/Tokyonight-Dark
  # (gtk-3.0 for XFCE apps + xfwm4 for the window borders set in xfwm4.xml).
  "$tmp/themes/install.sh" --dest /usr/share/themes --theme default --color dark --size standard >/dev/null
  rm -rf "$tmp"
else
  echo ">> Tema GTK Tokyo Night já instalado — pulando (FORCE_REINSTALL=1 para refazer)."
fi

# ── GTK3 headerbar button fix (theme-agnostic CSD button styling) ──
mkdir -p /home/vagrant/.config/gtk-3.0
fetch_asset gtk.css /home/vagrant/.config/gtk-3.0/gtk.css

# ── Tema visual (Tokyo Night GTK + Papirus + Noto Sans) ────────
mkdir -p /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml

fetch_asset xsettings.xml       /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
fetch_asset xfwm4.xml           /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# Ownership of /home/vagrant/* is corrected in scripts/55-permissions.sh.

# ── Tilix CloseDialog icon overlay ──────────────────────
# Papirus-Dark inherits from `breeze-dark,hicolor` — NOT from Papirus — so
# `utilities-terminal.svg` (which only Papirus ships) is unreachable. Tilix
# logs `[warning] closedialog.d:88: Could not load icon for 'utilities-terminal'`
# every time the "Close terminal?" dialog renders. Drop a user-XDG hicolor
# overlay symlinking each size to the corresponding Papirus icon. Hicolor is
# GTK's universal fallback theme so this resolves the icon for any active
# theme. User-scoped (~/.local/share/icons), so `apt upgrade
# papirus-icon-theme` and `papirus-icon-theme` package removal don't break it.
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
# index.theme is required for `gtk-update-icon-cache` to write a valid cache.
[ -e "$ICON_DST/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$ICON_DST/"
# Run as root so we don't need a mid-script chown — 55-permissions.sh sweeps
# /home/vagrant at the end of provisioning.
gtk-update-icon-cache -q -f "$ICON_DST" >/dev/null 2>&1 || true

# ── Tilix dock icon: override Papirus-Dark's monochrome 2-pane fallback ──
# Papirus-Dark ships its own com.gexperts.Tilix.svg (a gray flat 2-pane
# design) which takes priority over the hicolor inheritance chain — it's
# visually indistinguishable from xfce4-terminal's generic icon at panel
# sizes. The upstream Tilix icon (navy 3-pane) lives at hicolor/scalable;
# we expose it through a user-scoped Papirus-Dark overlay so the docklike
# panel plugin picks the distinctive branding without touching system
# theme files. Survives `apt upgrade papirus-icon-theme`.
PD_DST=/home/vagrant/.local/share/icons/Papirus-Dark
TILIX_SRC=/usr/share/icons/hicolor/scalable/apps/com.gexperts.Tilix.svg
mkdir -p "$PD_DST"
cat > "$PD_DST/index.theme" <<'PD_INDEX'
[Icon Theme]
Name=Papirus-Dark
Comment=User overrides for Papirus-Dark
Inherits=Papirus-Dark,hicolor
Directories=16x16/apps,22x22/apps,24x24/apps,32x32/apps,48x48/apps,64x64/apps

[16x16/apps]
Size=16
Context=Applications
Type=Fixed

[22x22/apps]
Size=22
Context=Applications
Type=Fixed

[24x24/apps]
Size=24
Context=Applications
Type=Fixed

[32x32/apps]
Size=32
Context=Applications
Type=Fixed

[48x48/apps]
Size=48
Context=Applications
Type=Fixed

[64x64/apps]
Size=64
Context=Applications
Type=Fixed
PD_INDEX
for size in 16x16 22x22 24x24 32x32 48x48 64x64; do
  mkdir -p "$PD_DST/$size/apps"
  ln -sfn "$TILIX_SRC" "$PD_DST/$size/apps/com.gexperts.Tilix.svg"
done
gtk-update-icon-cache -q -f "$PD_DST" >/dev/null 2>&1 || true
