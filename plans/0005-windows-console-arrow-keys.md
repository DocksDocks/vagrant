# 0005 — Host-aware key reading for the resource-profile menu (Windows arrow keys)

**Status:** Accepted
**Branch:** `claude/kind-gates-83HIP`
**Scope:** `Vagrantfile` only (host-side Ruby; no provisioning, no guest change)

## Problem

On a Windows host, `vagrant up` renders the resource-profile menu correctly
(box, colours, the `❯` cursor highlight all draw), and `q` cancels normally,
but pressing **↑/↓ does nothing** — the selection never moves. The same menu
works fine on Linux/macOS hosts. Reported against an `mintty`-free, real
Windows console (cmd.exe / PowerShell / Windows Terminal), since the menu only
opens when both `$stdin.tty?` and `$stdout.tty?` are true.

## Root cause

The original reader was Unix-only:

```ruby
def read_menu_key
  IO.select([$stdin])
  $stdin.read_nonblock(8)   # expects the ANSI burst "\e[A" / "\e[B"
end
```

Arrow keys reach a process differently depending on the console:

- **Unix/macOS** (and Windows Terminal *only* when `ENABLE_VIRTUAL_TERMINAL_INPUT`
  is set): the terminal delivers the ANSI escape burst `\e[A` / `\e[B`, which
  `IO.select` + `read_nonblock` captures whole.
- **Classic Windows console** (the default mode of cmd.exe / PowerShell /
  Windows Terminal — VT *output* is on, which is why the box renders, but VT
  *input* is off): arrow keys carry no character and are **never delivered to
  the byte stream that `read_nonblock`/`ReadFile` sees**. They surface only via
  `getch`, as an *extended-key* pair — a `0x00` or `0xE0` prefix byte followed
  by an ASCII scancode (`H`=`0x48` up, `P`=`0x50` down, `K`/`M` left/right).

That asymmetry is the whole bug: `q`, `j`, `k`, Enter and digits are ordinary
characters, so they come through `read_nonblock` and worked; the arrows are
extended keys, so they were invisible to it and silently did nothing.

References:
- [ruby/io-console `console.c`](https://github.com/ruby/io-console/blob/master/ext/io/console/console.c)
  — the Windows `getch` path: when `_getwch()` returns `0x00`/`0xe0` it stores
  the prefix and immediately reads the scancode, returning **both bytes in a
  single `getch` call**.
- Microsoft Q&A, *Scan codes for arrow keys* — extended keys are prefixed by
  `0x00`/`0xE0`; up/down are scancodes `0x48`/`0x50`.

## Decision

Make key reading **host-aware**, with the OS detected once via a new
`WINDOWS` constant (`HOST_OS =~ /mswin|mingw|cygwin/i`):

- **Unix path** (`next_action_unix`): keep `IO.select` + `read_nonblock`
  inside `$stdin.raw`, decoding the ANSI burst — behaviour unchanged.
- **Windows path** (`next_action_windows`): read with `$stdin.getch` (which
  manages the console mode itself, so no `raw` block) and decode the
  extended-key burst.

Both decoders are split into **pure functions** (`decode_unix_burst(str)` and
`decode_win_getch(bytes)`) that map input → a normalized action symbol
(`:up`, `:down`, `:enter`, `:cancel`, `[:digit, n]`, `:other`), so they can be
unit-tested without a TTY. A shared `run_menu_loop` takes the per-OS reader as
a block.

`decode_win_getch` keys off the **trailing** scancode byte and only requires
`bytes.length >= 2`, so it is robust to the console codepage re-encoding the
`0xE0` prefix (e.g. CP_UTF8 turns it into `0xC3 0xA0`); the ASCII scancode
always survives as the last byte.

Two robustness extras, free with the refactor:
- **`1`–`5` direct selection** in both decoders (and advertised in the legend),
  a bullet-proof fallback if any exotic terminal still mangles the arrows.
- `j`/`k` (already present) keep working on every host.

If the terminal cannot enter raw mode / `getch` raises, `select_profile`
already rescues `StandardError` and falls back silently to the saved/default
tier — unchanged.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Enable `ENABLE_VIRTUAL_TERMINAL_INPUT` via Win32 (`SetConsoleMode`) so `\e[A` flows through `read_nonblock` | Needs `fiddle`/FFI against `kernel32`, fragile across consoles, and in VT-input mode `getch`/reads deliver the ESC of `\e[A` separately — forcing a full escape state machine anyway. `getch`+scancode is simpler and Oracle/MS-documented. |
| Tell Windows users to navigate with `j`/`k` only | `j`/`k` already worked but were undiscoverable; the user explicitly wants the arrow keys to work. Documenting a workaround isn't fixing the bug. |
| Drop the arrow-key TUI; prompt for a number `1`–`5` on a normal line | Regresses the polished menu on Linux/macOS where it works well. We keep the TUI and *add* number selection as a fallback. |
| Vendor a TUI gem (`tty-prompt`/`tty-reader`) | Adds a runtime gem dependency to a Vagrantfile that must run on a stock Vagrant Ruby with no `bundle install`. ~50 lines of stdlib `io/console` covers our 5-item menu. |
| Leave it Unix-only | Windows is a first-class host for this box; the menu is the first thing `vagrant up` shows. |

## How it's enabled at provision time

Host-side only — this runs at `vagrant up` / `vagrant reload` *before* any
guest provisioning, while the Vagrantfile is being evaluated. No script under
`scripts/` and no asset is involved.

In `Vagrantfile`:
- `WINDOWS = !(HOST_OS =~ /mswin|mingw|cygwin/i).nil?` (just below `HOST_OS`).
- `decode_unix_burst` / `decode_win_getch` — pure input→symbol decoders.
- `next_action_unix` / `next_action_windows` — the per-OS readers.
- `run_menu_loop` — shared draw/read/update loop; takes the reader as a block.
- `interactive_profile_menu` — branches on `WINDOWS`: `getch` directly on
  Windows, `$stdin.raw { … }` + burst reader elsewhere.
- The legend line gains `1-#{profiles.length} ir`.

## Verification

1. Syntax: `ruby -c Vagrantfile` → `Syntax OK`.
2. Logic (no TTY needed): the pure decoders + loop are exercised by a test
   that `eval`s the Vagrant-free slice of the real Vagrantfile and asserts:
   - `decode_unix_burst("\e[A") == :up`, `… "\e[B" == :down`, `"\r"/"\n" == :enter`,
     `"q"/"\e" == :cancel`, `"3" == [:digit, 3]`.
   - `decode_win_getch([0xE0,0x48]) == :up`, `[0x00,0x48] == :up`,
     `[0xE0,0x50] == :down`, `[0xC3,0xA0,0x48] == :up` (re-encoded prefix),
     `[0x6B] == :up` (`k`), `[0x35] == [:digit,5]`, `[0xE0,0x4B] == :other`.
   - `run_menu_loop` navigates, wraps top↔bottom, jumps on a digit (ignoring
     out-of-range), and returns `:cancel`.
   All 26 assertions pass.
3. Windows host (manual): `vagrant up` on cmd.exe / PowerShell / Windows
   Terminal → ↑/↓ move the highlight, `1`–`5` jump to a tier, Enter confirms
   (prints `→ perfil: …` and persists to `.vagrant/last_profile`), `q`/Esc
   cancels.
4. Linux/macOS host (regression): ↑/↓, `j`/`k`, Enter, `q` behave exactly as
   before; `1`–`5` now also select.
5. Non-interactive (any host): `VM_PROFILE=3 vagrant status` and piped stdin
   skip the menu and use the override/saved/default tier — unchanged.

## Files changed

- `Vagrantfile` — `WINDOWS` constant; `read_menu_key` (Unix-only) replaced by
  `decode_unix_burst` + `decode_win_getch` + `next_action_unix` +
  `next_action_windows` + `run_menu_loop`; `interactive_profile_menu` branches
  on host; legend mentions `1-N`.
- `plans/0005-windows-console-arrow-keys.md` — this file.
- `AGENTS.md` — Common Issues bullet added.
- `.agents/skills/vagrantfile-orchestrator/SKILL.md` — description + `metadata.updated` + `source_files` refreshed for the host-aware reader.
