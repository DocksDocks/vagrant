# Host Resource Detection (Vagrantfile)

<constraint>
Every resolved tier MUST stay ≤75% of host RAM and ≤75% of host CPUs
(`ram_cap`/`cpu_cap`), and RAM MUST be a multiple of 256 MB (VMSVGA framebuffer
alignment). Without the 75% cap a high tier on a small host starves host
Chrome/Claude; without the 256 MB rounding VirtualBox silently clamps the value.
</constraint>

## Host detection

```ruby
def detect_host_memory_mb   # darwin: sysctl hw.memsize; linux: /proc/meminfo;
  ...                       # mswin: powershell TotalPhysicalMemory; else 8192
def detect_host_cpus        # darwin: hw.ncpu; linux: nproc;
  ...                       # mswin: NUMBER_OF_PROCESSORS; else 2
```

Source: `Vagrantfile:14-36`. `detect_audio_driver` (`Vagrantfile:38-48`) maps
OS → audio driver; unchanged by the profile rework.

## 5-tier resource profile (math unchanged)

```ruby
RAM_TIER_PCT = [0.3125, 0.40625, 0.5, 0.59375, 0.6875].freeze
CPU_TIER_PCT = [0.5, 0.625, 0.75, 0.75, 0.75].freeze
DEFAULT_TIER = 2  # base-1; 6.5 GB / 5 vCPU on a 16 GB / 8-core host

def build_profiles(host_ram, host_cpus)
  ram_cap = (host_ram  * 0.75).floor
  cpu_cap = [(host_cpus * 0.75).floor, 1].max
  RAM_TIER_PCT.each_index.map do |i|
    mem = (host_ram * RAM_TIER_PCT[i] / 256).round * 256
    mem = [[mem, 2048].max, ram_cap].min
    cpu = [[(host_cpus * CPU_TIER_PCT[i]).round, 1].max, cpu_cap].min
    [mem, cpu]
  end
end
```

Source: `RAM_TIER_PCT`/`CPU_TIER_PCT`/`DEFAULT_TIER` at `Vagrantfile:61-63`,
`build_profiles` at `Vagrantfile:69-79`. Each tier scales off host totals, rounds
RAM to 256 MB, then clamps RAM to `[2048, ram_cap]` and CPU to `[1, cpu_cap]`
(caps = 75% of host, floored). These percentages, the rounding, the 75% cap, and
`DEFAULT_TIER` are unchanged from the original numbered-prompt version.

## Persistence (`.vagrant/last_profile`)

```ruby
PROFILE_STATE_FILE = File.join(File.dirname(File.expand_path(__FILE__)),
                               ".vagrant", "last_profile")  # Vagrantfile:67
load_saved_tier(num_tiers)  # read+validate 1..n, rescue→nil   Vagrantfile:81-87
save_tier(idx)              # FileUtils.mkdir_p + File.write    Vagrantfile:90-95
```

The chosen tier index (1-5) is written to `.vagrant/last_profile` — machine-local
state, gitignored via the root `.gitignore` (`.vagrant/`). `load_saved_tier`
validates the stored value is in `1..num_tiers` (else `nil`); `save_tier` is
best-effort (`rescue StandardError → nil`) so I/O failure never aborts the boot.
The saved tier is both the pre-selected cursor row and the silent non-tty
fallback.

## Resolution order (`select_profile`, `Vagrantfile:155-194`)

1. `$vm_profile` memoization (`:156`) — Vagrant re-evaluates the file per command;
   the global cache means the menu fires at most once.
2. `VM_PROFILE=1..5` env (`:163-167`) — one-shot non-interactive override; out of
   range falls back to `default_idx`. Does NOT write `.vagrant/last_profile`.
3. Saved tier → `DEFAULT_TIER` (`:158-159`) — `default_idx = saved || DEFAULT_TIER`.
4. Prompt guard (`:171-174`): the menu renders only when ARGV includes `up`/`reload`
   AND both stdin and stdout are TTYs; every other case returns `default_idx`.

On an Integer choice → `save_tier` + use (`:184-188`); on `:cancel` →
`abort("Cancelado…")` (exit 1, VM not started, `:189-190`); on `:failed` (raw-mode
exception) → `default_idx` fallback (`:191-192`).

## Key reading — host-aware (alternate screen)

```ruby
render_profile_menu(...)        # Vagrantfile:100-121 alt-screen redraw + legend
decode_unix_burst / decode_win_getch   # :137-169 input -> action symbol (pure)
next_action_unix / next_action_windows # :171-185 per-OS readers
run_menu_loop(...) { reader }   # :187-205 draw/read/update; returns Int|:cancel
interactive_profile_menu(...)   # :207-225 branches on WINDOWS
```

- **Why two readers** (plans/0005): on a classic Windows console arrow keys never
  reach `read_nonblock` — they arrive only via `getch` as a `0x00`/`0xE0` prefix +
  ASCII scancode (`H`=up, `P`=down), so the burst reader saw `q`/`j`/`k` but not
  ↑/↓. `WINDOWS` (`Vagrantfile:13`) selects the reader.
- **Alt screen** (`:212`,`:222`): `\e[?1049h\e[?25l` on entry, `\e[?25h\e[?1049l`
  in an `ensure` (restored on exception); raw mode (`$stdin.raw`) wraps the loop on Unix only.
- **Unix** `decode_unix_burst`: `\e[A`/`k`→`:up`, `\e[B`/`j`→`:down`, `\r`/`\n`→
  `:enter`, `q`/`\e`/Ctrl-C/EOF→`:cancel`, `1-9`→`[:digit,n]`.
- **Windows** `decode_win_getch`: keys off the **trailing** scancode byte with
  `bytes.length >= 2`, robust to the codepage re-encoding the `0xE0` prefix.
- **Highlight bar** (`:114`): cursor row `\e[1;97;44m ❯…\e[0m`; labels `(padrão)`/
  `(último)` for `DEFAULT_TIER`/saved (`:110-112`).

## Resolved tiers (verified by running the code)

| Host | Cap (75%) | T1 | T2 (default) | T3 | T4 | T5 |
|---|---|---|---|---|---|---|
| 16 GB / 8 CPU | 12288 MB / 6 | 5.0 GB / 4 | 6.5 GB / 5 | 8.0 GB / 6 | 9.5 GB / 6 | 11.0 GB / 6 |
| 8 GB / 4 CPU | 6144 MB / 3 | 2.5 GB / 2 | 3.2 GB / 3 | 4.0 GB / 3 | 4.8 GB / 3 | 5.5 GB / 3 |
| 32 GB / 16 CPU | 24576 MB / 12 | 10 GB / 8 | 13 GB / 10 | 16 GB / 12 | 19 GB / 12 | 22 GB / 12 |
| Unknown OS | — | falls back to 8192 MB / 2 CPU host defaults, then tiered |

CPU tiers 3-5 share `CPU_TIER_PCT = 0.75`, so they resolve to the same vCPU count
(capped at the host's own 75%); only RAM keeps climbing across tiers 3-5.

## Audio driver mapping

| Host OS | Driver |
|---|---|
| Windows (mswin/mingw/cygwin) | dsound |
| macOS (darwin) | coreaudio |
| Linux | pulse |
| Unknown | none |

Source: `Vagrantfile:38-48`.

## Gotchas

**Higher tier does not mean more CPU**: tiers 3-5 all use 0.75 of host CPUs, so
raising the tier past 3 only adds RAM. On a 16 GB / 8-core host every tier from 3
up is 6 vCPU.

**`detect_host_memory_mb` returns 0 on broken Linux**: if `/proc/meminfo` is
missing, `ram_cap` becomes 0 and every tier clamps to 0 MB — guard host detection
on non-standard Linux.

**`VM_PROFILE` out of range**: `VM_PROFILE=9`/`0`/non-numeric falls back to the
saved tier or `DEFAULT_TIER` rather than erroring, and never writes the state file.

**Cancel aborts the boot**: `q`/Esc/Ctrl-C → `:cancel` → `abort` → vagrant exits 1
and the VM is NOT started. This is intentional; it is the only path that stops the
run. A non-tty invocation can never reach it (guard returns the default first).

**Raw mode unavailable**: a terminal that rejects `$stdin.raw` raises inside the
menu; `select_profile` rescues `StandardError → :failed` and silently uses
`default_idx`. The menu never crashes a provision over terminal capability.

**Stale `.vagrant/last_profile`**: editing the tier count (e.g. dropping to 4
tiers) invalidates a saved `5`; `load_saved_tier` returns `nil` for out-of-range
values, so it quietly falls back to `DEFAULT_TIER` rather than indexing past the
array.
