# 0010 — Resource profile: round VM RAM to whole GB

**Status:** Accepted
**Branch:** `claude/vibrant-heisenberg-LuQZM`
**Scope:** `Vagrantfile` (`build_profiles` + the two display sites), `.agents/skills/vagrantfile-orchestrator/*`, `AGENTS.md`, `README.md`, `README.pt-BR.md`

## Problem

The interactive resource-profile menu offered fractional-GB RAM tiers — on a 16 GB / 8-core host the ladder was `5.0 / 6.5 / 8.0 / 9.5 / 11.0 GB`. The `6.5 GB` (and `9.5 GB`) tiers were reported as flaky: VMs created with those odd sizes were less reliable to start than the "round" `6 GB`/`8 GB` ones, and the half-GB numbers look wrong in a picker that's otherwise about whole machines.

## Root cause

`build_profiles` rounded **system RAM** to the nearest **256 MB**:

```ruby
mem = (host_ram * RAM_TIER_PCT[i] / 256).round * 256
```

The `256` was borrowed from the wrong place. 256 MB is the **VRAM / framebuffer ceiling** for the VMSVGA graphics controller (`vb.customize ["modifyvm", :id, "--vram", "256"]`, and VirtualBox silently clamps VRAM above 256 MB — [VBox forum #107806](https://forums.virtualbox.org/viewtopic.php?t=107806)). That ceiling has nothing to do with how much *system* RAM a guest may have. Applying a 256 MB grid to system RAM is what produced the 6.5 GB (6656 MB) and 9.5 GB (9728 MB) values — both exact multiples of 256 MB but not of 1 GB.

VirtualBox's real system-memory granularity is **4 MB** (any multiple of 4 is accepted), so 6656 MB is technically legal. But whole-GB sizes are what everyone uses and tests, and odd CPU/RAM combinations are a known cause of VMs failing to start ([Oracle VBox #11483 "cannot start a VM with a lot of CPUs and RAM"](https://www.virtualbox.org/ticket/11483); VirtualBox also requires one contiguous host allocation, so unusual sizes hit fragmentation/`HostMemoryLow` more readily — [#3657](https://www.virtualbox.org/ticket/3657)). The skill reference even documented the wrong rationale verbatim ("RAM MUST be a multiple of 256 MB (VMSVGA framebuffer alignment)"), cementing the confusion.

## Decision

Round VM RAM to **whole GB** (multiples of 1024 MB) and re-pick the tier percentages so the reference host lands on an even, intuitive ladder.

```ruby
GB = 1024
RAM_TIER_PCT = [0.25, 0.375, 0.5, 0.625, 0.75].freeze   # was [0.3125, 0.40625, 0.5, 0.59375, 0.6875]
CPU_TIER_PCT = [0.5, 0.625, 0.75, 0.75, 0.75].freeze     # unchanged
DEFAULT_TIER = 2                                          # now 6 GB / 5 vCPU on 16 GB / 8-core

def build_profiles(host_ram, host_cpus)
  ram_cap_gb = [(host_ram * 0.75 / GB).floor, 1].max
  cpu_cap    = [(host_cpus * 0.75).floor, 1].max
  RAM_TIER_PCT.each_index.map do |i|
    gb  = (host_ram * RAM_TIER_PCT[i] / GB).round
    gb  = [[gb, 2].max, ram_cap_gb].min
    cpu = [[(host_cpus * CPU_TIER_PCT[i]).round, 1].max, cpu_cap].min
    [gb * GB, cpu]
  end
end
```

On a 16 GB / 8-core host this yields the clean ladder **4 / 6 / 8 / 10 / 12 GB** with **4 / 5 / 6 / 6 / 6 vCPU**; the default (tier 2) is now exactly **6 GB**. Every emitted RAM value is a multiple of 1024 MB. The 75% cap is preserved and is itself floored to a whole GB (min 1 GB, so a tiny host that can't give 2 GB never exceeds 75%). The two display sites print `%d GB` instead of `%.1f`/`%5.1f`.

The 256 MB **VRAM** setting is untouched — that ceiling is real and stays.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Keep 256 MB rounding | The status quo; produces the 6.5 GB values the change is about. |
| Round to whole GB but keep old percentages | `[…0.40625…]` on 16 GB rounds 6.5→7 and 9.5→10, giving a jumpy `5 / 7 / 8 / 10 / 11` ladder; new even-step percentages give a cleaner `4 / 6 / 8 / 10 / 12` and land the default on the user's preferred 6 GB. |
| Floor instead of round to GB | More conservative but pushes tier 1 to 4 GB on realistic ~15.9 GB hosts and feels stingy; round-to-nearest tracks the intended percentages better. |
| Let the user type an arbitrary MB value | Defeats the point of a fixed, tested ladder; reintroduces odd sizes. |

## How it's enabled at provision time

This is host-side Ruby evaluated by Vagrant before any provisioner runs — there is no guest-side step. `build_profiles(build) → select_profile` resolves `[vm_memory, vm_cpus]`, which feed `vb.memory`/`vb.cpus` (VirtualBox) or `u.memory`/`u.cpus` (UTM). The menu (`render_profile_menu`) and the post-selection line (`select_profile`) display whole GB via `mem / GB`.

## Verification

1. Math, all hosts produce GB-multiples:
   ```bash
   ruby -e 'src=File.read("Vagrantfile",encoding:"UTF-8"); eval src[/^GB = 1024.*?^end/m];
     [[16384,8],[15990,8],[8192,4],[32768,16]].each{|r,c| p build_profiles(r,c)}'
   # every memory value is a multiple of 1024; 16384/8 → 4/6/8/10/12 GB
   ```
2. `ruby -c Vagrantfile` → `Syntax OK`.
3. `VM_PROFILE=2 vagrant up` on a 16 GB host, then `VBoxManage showvminfo debian13-dev | grep "Memory size"` → `6144MB`.
4. The menu (`vagrant up` in a TTY) shows `4 / 6 / 8 / 10 / 12 GB`, no `.5` rows.

## Files changed

- `Vagrantfile` — `GB` constant; `RAM_TIER_PCT`; `build_profiles` rewritten to whole-GB with a GB-floored cap; `DEFAULT_TIER` comment; two display formats `%d GB`; the tier-ladder comment.
- `.agents/skills/vagrantfile-orchestrator/SKILL.md` + `references/host-resource-detection.md` — corrected the constraint (256 MB was VRAM, not system RAM), the code snippet, the resolved-tier table, the 0-RAM gotcha; bumped `metadata.updated`.
- `AGENTS.md` — orchestration summary ladder line.
- `README.md` / `README.pt-BR.md` — "VM resources" section rewritten as the 5-tier menu with the whole-GB ladder.
