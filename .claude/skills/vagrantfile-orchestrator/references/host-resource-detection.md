# Host Resource Detection (Vagrantfile)

<constraint>
The 16 GB / 8-CPU carve-out (host_ram 14000-24000 AND host_cpus 6-9 → 6656 MB / 4 vCPU) MUST be preserved. Without it, those hosts allocate ~10 GB to the VM and starve host Chrome, Claude, and other apps.
</constraint>

## Implementation

```ruby
require 'rbconfig'
HOST_OS = RbConfig::CONFIG['host_os']

def detect_host_memory_mb
  if HOST_OS =~ /darwin/i
    `sysctl -n hw.memsize`.to_i / 1024 / 1024
  elsif HOST_OS =~ /linux/i
    `grep MemTotal /proc/meminfo`.split[1].to_i / 1024
  elsif HOST_OS =~ /mswin|mingw|cygwin/i
    `powershell -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"`.strip.to_i / 1024 / 1024
  else
    8192
  end
end

def detect_host_cpus
  if HOST_OS =~ /darwin/i
    `sysctl -n hw.ncpu`.to_i
  elsif HOST_OS =~ /linux/i
    `nproc`.to_i
  elsif HOST_OS =~ /mswin|mingw|cygwin/i
    ENV['NUMBER_OF_PROCESSORS'].to_i
  else
    2
  end
end

def detect_audio_driver
  if HOST_OS =~ /mswin|mingw|cygwin/i
    "dsound"
  elsif HOST_OS =~ /darwin/i
    "coreaudio"
  elsif HOST_OS =~ /linux/i
    "pulse"
  else
    "none"
  end
end
```

Source: `Vagrantfile:9-47`

## Resource Allocation Formula

```ruby
host_ram  = detect_host_memory_mb
host_cpus = detect_host_cpus

vm_memory, vm_cpus =
  if host_ram >= 14000 && host_ram < 24000 && host_cpus >= 6 && host_cpus <= 9
    [6656, 4]
  else
    [
      [[host_ram - 6144, 2048].max, 16384].min,
      [[host_cpus - 2,   1   ].max, 8    ].min,
    ]
  end
```

Source: `Vagrantfile:49-60`

## Allocation Table

| Host RAM | Host CPUs | VM RAM | VM CPUs | Path |
|---|---|---|---|---|
| 16 GB (14k-24k) | 8 (6-9) | 6.5 GB (6656 MB) | 4 | Carve-out |
| 8 GB | 4 | 2 GB (min) | 2 | Formula |
| 16 GB | 4 | 10 GB | 2 | Formula |
| 32 GB | 16 | 16 GB (max) | 8 (max) | Formula (clamped) |
| Unknown OS | any | 8 GB (fallback) | 2 (fallback) | Default |

## Audio Driver Mapping

| Host OS | Driver |
|---|---|
| Windows (mswin/mingw/cygwin) | dsound |
| macOS (darwin) | coreaudio |
| Linux | pulse |
| Unknown | none |

Source: `Vagrantfile:37-47`

## Gotchas

**`detect_host_memory_mb` returns 0 on unknown Linux**: if `grep MemTotal /proc/meminfo` fails or `/proc/meminfo` is absent, `.split[1].to_i` returns 0. The formula then allocates the minimum (2048 MB). This is safe — the fallback is conservative, not dangerous.

**`nproc` not available on some Linux hosts**: returns 0, giving 1 vCPU after `[[0 - 2, 1].max]`. Add a fallback if deploying on non-standard Linux hosts.

**Windows PowerShell slowness**: `Get-CimInstance Win32_ComputerSystem` spawns PowerShell which adds ~1s to `vagrant up` startup. This is acceptable — detection runs once per `vagrant up`, not per-script.

**16 GB carve-out condition is AND**: both the RAM range (14000-24000) AND the CPU range (6-9) must match. A 16 GB host with only 4 CPUs gets the standard formula (allocates ~10 GB RAM, 2 CPUs).
