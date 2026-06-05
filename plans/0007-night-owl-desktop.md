# 0007 — Night Owl desktop (Tilix + Mousepad + Tokyo Night GTK chrome)

**Status:** Proposed (trial — merge to `main` if the look proves worth keeping)
**Branch:** `feat/night-owl-desktop`
**Scope:** the box's *own* XFCE desktop look. Repalettes Tilix, ships a Night
Owl editor scheme for Mousepad, and swaps the GTK/xfwm4 chrome from Arc-Dark to
Tokyo Night. Extends existing scripts (`20`, `40`, `41`, `60`) + four assets; no
new numbered script. Independent of the Kate trial (`plans/0006-kate-editor.md`)
— deliberately branched off `main`, not off `feat/kate-editor-trial`.

## Problem

The Kate trial (0006) ported the Night Owl palette into one editor and the user
liked the aesthetic, but disliked Kate itself. The ask: bring the Night Owl look
into the box's *own* desktop — the surfaces used every day — instead of a
throwaway editor. Today the box is themed Arc-Dark (GTK + xfwm4), a near-black
`#1E1E1E` Tilix palette, and a `solarized-dark` Mousepad.

## Root cause (why this isn't a one-line theme swap)

Night Owl is a **code-editor** theme (Sarah Drasner's VS Code theme). It defines
editor + terminal colors, but **nobody has ported it to GTK window chrome** —
not gnome-look, not Fausto-Korpsvart (the canonical palette-GTK-theme author,
who ships Tokyo Night / Nightfox / Gruvbox / Catppuccin, but no Night Owl). So
"Night Owl on the desktop" splits into surfaces where the real thing exists
(terminal, editor) and the chrome, which must be an interpretation. The look is
also set in several places at once: GTK theme name (`assets/xsettings.xml`),
xfwm4 window-decoration theme (`assets/xfwm4.xml`), the LightDM greeter
(`assets/lightdm-gtk-greeter.conf`), the Tilix palette (`assets/tilix.dconf`),
and the Mousepad `color-scheme` (`scripts/60`).

## Decision

1. **Tilix → Night Owl palette** (literal). `assets/tilix.dconf` background
   `#011627`, foreground `#d6deeb`, and the canonical 16-colour ANSI palette
   (from `mbadolato/iTerm2-Color-Schemes`). Profile UUID, font, and 4%
   transparency unchanged. Compiled into the dconf user-db by `scripts/60`
   exactly as before (`dconf compile`, first-provision-only).
2. **Mousepad → Night Owl** (hand-authored, no upstream port exists). A new
   GtkSourceView 4 style scheme `assets/gtksourceview/night-owl.xml` (`id`
   `night-owl`), authored from the Night Owl palette using the upstream
   `solarized-dark.xml` structure. Deployed **every** provision to
   `~/.local/share/gtksourceview-4/styles/` (Mousepad is GTK3 → GtkSourceView 4);
   `scripts/60` switches the `color-scheme` gsetting from `solarized-dark` to
   `night-owl` (seeded first-provision-only, like the rest of the dconf).
3. **Icons → keep Papirus-Dark** (reuse, not Colloid). The Nerd Font already
   covers the *terminal/superfile* glyph layer; the desktop icon **theme** is a
   separate mechanism (SVGs via the freedesktop spec) that a font cannot serve.
   Neither Papirus-Dark nor Colloid is intrinsically "Night Owl", and Papirus
   already has integration work in `scripts/41` (the Tilix CloseDialog overlay +
   navy 3-pane dock-icon override). Switching to Colloid would mean vendoring a
   second theme and redoing those overlays for zero Night-Owl gain — so we don't.
4. **GTK chrome → Tokyo Night GTK** (closest maintained navy). Since no literal
   Night Owl GTK theme exists, install Fausto-Korpsvart's `Tokyonight-GTK-Theme`
   — the closest maintained GTK3/4 **+ xfwm4** theme in the same deep-navy /
   blue-purple family. Installed system-wide from a **pinned commit**
   (`git fetch --depth 1 <SHA>` + assert `HEAD == SHA`), compiled from SASS by
   the upstream installer (`--theme default --color dark --size standard` →
   `/usr/share/themes/Tokyonight-Dark`). `sassc` added to `scripts/20` deps so
   the installer's interactive `sudo apt-get install sassc` fallback never fires.
   `assets/xsettings.xml` (`ThemeName`), `assets/xfwm4.xml` (`theme`), and the
   greeter (`theme-name` + navy `background=#011627`) all point at it.
   `arc-theme` stays apt-installed as the documented one-line revert path.

## Alternatives considered

### Desktop icon theme

| Option | Verdict |
| --- | --- |
| **Keep Papirus-Dark** | **Chosen.** Already integrated (Tilix overlays in `scripts/41`); zero new vendoring; not less "Night Owl" than any other dark icon set. |
| Switch to Colloid-Dark | Rejected. Came in via the Kate trial; would vendor a second theme + rework the Tilix overlays for no Night-Owl gain. |
| Reuse the JetBrainsMono Nerd Font glyphs | Impossible. Nerd Font glyphs are font *characters* rendered by terminal/TUI apps (superfile); the GUI icon theme is SVGs consumed by Thunar/panel/menus. Different layer — a font cannot be an icon theme. |

### GTK window chrome

| Option | Verdict |
| --- | --- |
| **Tokyo Night GTK** (Fausto-Korpsvart) | **Chosen.** Closest *maintained* navy GTK3/4 + xfwm4 theme; same colour family as Night Owl; pinned + commit-verified like the Colloid install. Not literally `#011627`. |
| Keep Arc-Dark chrome | Lowest-risk; Night Owl would live only in terminal + editor. Documented revert (arc-theme stays installed). User opted for navy chrome instead. |
| Hand-build a literal Night Owl GTK theme | Rejected. No upstream base; we'd own/maintain a bespoke theme with rough-edge risk across GTK widgets — disproportionate to the payoff. |

### Mousepad editor scheme

| Option | Verdict |
| --- | --- |
| **Hand-author the GtkSourceView style** | **Chosen** — no upstream Night Owl GtkSourceView port exists; authored from the canonical palette on the upstream `solarized-dark.xml` skeleton. |
| Reuse an existing port | Not possible — none published. |

## How it's enabled at provision time

- `scripts/20-packages.sh` — adds `sassc` (build dep for the GTK theme).
- `scripts/41-xfce-theme.sh` — compiles Tokyo Night from the pinned commit into
  `/usr/share/themes/Tokyonight-Dark` (idempotent: skips if present;
  `FORCE_REINSTALL=1` redoes), then deploys `xsettings.xml` (GTK theme name) +
  `xfwm4.xml` (window-border theme). Papirus icon overlays unchanged.
- `scripts/60-apps-tilix-mousepad.sh` — deploys `night-owl.xml` to the user
  GtkSourceView styles dir (every provision; chowned to vagrant since
  `55-permissions.sh` runs *before* `60`), seeds the Tilix Night Owl palette +
  Mousepad `color-scheme='night-owl'` via `dconf compile` (first provision only).
- `scripts/40-xfce-base.sh` — deploys the greeter (now Tokyo Night + navy bg).

## Verification steps

- `shellcheck -x scripts/{20,41,60}-*.sh` → clean (only the expected SC1091
  `_lib.sh` info); `bash -n` OK on all three.
- XML well-formed (`xsettings.xml`, `xfwm4.xml`, `night-owl.xml`).
- `night-owl.xml`: scheme `id` is `night-owl` (matches the gsetting); all 19
  palette `<color>`s defined; **no** unresolved colour references.
- Tilix palette has exactly 16 entries; bg/fg are the canonical Night Owl values.
- Tokyo Night flags verified against the upstream `themes/install.sh`:
  `--theme default --color dark --size standard` builds exactly `Tokyonight-Dark`
  (gtk-3.0 for XFCE apps + xfwm4 window borders); pin HEAD == the recorded SHA.
- Post-`vagrant up` (visual): Tilix renders navy `#011627`; Mousepad uses Night
  Owl; Thunar / panel / dialogs and the xfwm4 titlebars render Tokyo Night navy;
  the LightDM login screen is navy. Papirus-Dark icons unchanged.

## Caveat

The chrome is Tokyo Night, **not** literal Night Owl colour values — no literal
Night Owl GTK theme exists, so the window chrome is a same-family approximation
by necessity (the terminal + editor *are* literal Night Owl). The GTK theme is
SASS-compiled at provision time, adding `sassc` + a few seconds to the first
provision. If the upstream theme repo changes, re-pin `TOKYONIGHT_PIN` in
`scripts/41`. To revert the chrome only: set the three theme names back to
`Arc-Dark` (still installed).

## Files changed

- `assets/tilix.dconf` — Night Owl palette
- `assets/gtksourceview/night-owl.xml` (new — Mousepad editor scheme)
- `assets/xsettings.xml` — GTK `ThemeName` → `Tokyonight-Dark`
- `assets/xfwm4.xml` — window-decoration `theme` → `Tokyonight-Dark`
- `assets/lightdm-gtk-greeter.conf` — greeter theme + navy background
- `scripts/20-packages.sh` — `sassc` build dep
- `scripts/41-xfce-theme.sh` — pinned Tokyo Night GTK install
- `scripts/60-apps-tilix-mousepad.sh` — deploy Night Owl GtkSourceView style + select it
- `scripts/40-xfce-base.sh` — greeter comment
- `AGENTS.md` — Theme line + script notes + Installed Tools
