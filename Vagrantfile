# -*- mode: ruby -*-
# vi: set ft=ruby :

# ── Detecção de recursos do host + menu de perfis ───────
# Detecta RAM/CPUs do host; `vagrant up`/`reload` num terminal interativo
# abre um menu de 5 perfis com navegação por setas (↑/↓, Enter, q). Teto
# fixo de 75% do host; a última escolha é lembrada e pré-selecionada.
require 'rbconfig'
require 'io/console'
require 'fileutils'

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

host_ram  = detect_host_memory_mb
host_cpus = detect_host_cpus

# ── Perfis de recursos (menu interativo) ────────────────
# Cinco níveis escalados a partir de uma referência de 16 GB / 8 núcleos,
# cada um limitado a 75% da RAM e das CPUs do host. Num host 16 GB / 8 CPU
# resolvem para a escada canônica:
#   5.0 / 6.5 / 8.0 / 9.5 / 11.0 GB   e   4 / 5 / 6 / 6 / 6 vCPU
# `vagrant up`/`reload` interativo abre o menu de setas; fora disso (status,
# ssh, provision, CI, stdin não-tty) usa o nível lembrado/padrão em silêncio.
# Pule o menu com VM_PROFILE=1..5 (one-shot; não altera a escolha lembrada).
RAM_TIER_PCT = [0.3125, 0.40625, 0.5, 0.59375, 0.6875].freeze
CPU_TIER_PCT = [0.5, 0.625, 0.75, 0.75, 0.75].freeze
DEFAULT_TIER = 2  # base-1; 6.5 GB / 5 vCPU num host de 16 GB / 8 núcleos

# Estado persistente da última escolha (índice 1-5). Fica em .vagrant/
# (estado local da máquina, fora do git) e é pré-selecionado no próximo up.
PROFILE_STATE_FILE = File.join(File.dirname(File.expand_path(__FILE__)), ".vagrant", "last_profile")

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

# Lê o índice lembrado (1..num_tiers) do arquivo de estado, ou nil.
def load_saved_tier(num_tiers)
  return nil unless File.file?(PROFILE_STATE_FILE)
  idx = File.read(PROFILE_STATE_FILE).strip.to_i
  (1..num_tiers).include?(idx) ? idx : nil
rescue StandardError
  nil
end

# Grava a escolha. Best-effort: nunca aborta o boot por falha de I/O.
def save_tier(idx)
  FileUtils.mkdir_p(File.dirname(PROFILE_STATE_FILE))
  File.write(PROFILE_STATE_FILE, "#{idx}\n")
rescue StandardError
  nil
end

# Redesenha o menu na tela alternativa: caixa de título, linhas de perfil
# (a do cursor vira uma barra destacada) e a legenda de teclas.
def render_profile_menu(profiles, host_ram, host_cpus, cursor, saved_idx)
  lines = [
    "",
    "  \e[1;96m╔══════════════════════════════════════╗\e[0m",
    "  \e[1;96m║        PERFIL DE RECURSOS DA VM        ║\e[0m",
    "  \e[1;96m╚══════════════════════════════════════╝\e[0m",
    "  \e[2mhost: #{host_ram} MB / #{host_cpus} CPU  ·  teto 75%\e[0m",
    "",
  ]
  profiles.each_with_index do |(mem, cpu), i|
    tags = []
    tags << "padrão" if i + 1 == DEFAULT_TIER
    tags << "último" if i + 1 == saved_idx
    ann  = tags.empty? ? "" : "  (#{tags.join(' · ')})"
    text = format(" %5.1f GB   /  %d vCPU%s", mem / 1024.0, cpu, ann)
    lines << (i == cursor ? "  \e[1;97;44m ❯#{text.ljust(36)}\e[0m" : "    #{text}")
  end
  lines << ""
  lines << "  \e[2m↑/↓\e[0m mover   \e[1;92m↵ Enter\e[0m confirmar   \e[2mq\e[0m cancelar"
  $stdout.print "\e[H\e[2J" + lines.join("\r\n") + "\r\n"
  $stdout.flush
end

# Lê uma tecla em raw mode. Setas chegam como rajada "\e[A"/"\e[B".
def read_menu_key
  IO.select([$stdin])
  $stdin.read_nonblock(8)
rescue IO::WaitReadable
  retry
rescue EOFError
  "q"
end

# Loop do menu. Retorna o índice 1-based escolhido ou :cancel. Pode levantar
# exceção se o terminal não suportar raw mode (o chamador trata como fallback).
def interactive_profile_menu(profiles, host_ram, host_cpus, initial_idx, saved_idx)
  cursor = initial_idx - 1
  $stdout.print "\e[?1049h\e[?25l"  # tela alternativa + esconde cursor
  begin
    $stdin.raw do
      loop do
        render_profile_menu(profiles, host_ram, host_cpus, cursor, saved_idx)
        case read_menu_key
        when "\e[A", "k" then cursor = (cursor - 1) % profiles.length
        when "\e[B", "j" then cursor = (cursor + 1) % profiles.length
        when "\r", "\n"  then return cursor + 1
        when "q", "\e", "" then return :cancel
        end
      end
    end
  ensure
    $stdout.print "\e[?25h\e[?1049l"  # mostra cursor + sai da tela alternativa
    $stdout.flush
  end
end

def select_profile(profiles, host_ram, host_cpus)
  return $vm_profile if $vm_profile

  saved       = load_saved_tier(profiles.length)
  default_idx = saved || DEFAULT_TIER

  # Override não-interativo (automação/CI): VM_PROFILE=1..5. One-shot — não
  # sobrescreve a escolha lembrada.
  if (env = ENV["VM_PROFILE"])
    idx = env.to_i
    idx = default_idx unless (1..profiles.length).include?(idx)
    return ($vm_profile = profiles[idx - 1])
  end

  # Só abre o menu num `up`/`reload` interativo. Demais comandos (status, ssh,
  # provision) e stdin/stdout não-tty caem no nível lembrado/padrão sem prompt.
  booting = !(ARGV & %w[up reload]).empty?
  unless booting && $stdin.tty? && $stdout.tty?
    return ($vm_profile = profiles[default_idx - 1])
  end

  choice =
    begin
      interactive_profile_menu(profiles, host_ram, host_cpus, default_idx, saved)
    rescue StandardError
      :failed  # terminal sem raw mode → fallback silencioso ao padrão
    end

  case choice
  when Integer
    save_tier(choice)
    mem, cpu = profiles[choice - 1]
    $stdout.printf("  → perfil: %.1f GB / %d vCPU\n\n", mem / 1024.0, cpu)
    $vm_profile = [mem, cpu]
  when :cancel
    abort("\n  Cancelado — a VM não foi iniciada.\n")
  else
    $vm_profile = profiles[default_idx - 1]
  end
end

vm_memory, vm_cpus = select_profile(build_profiles(host_ram, host_cpus), host_ram, host_cpus)

# ── Provisioning source config ──────────────────────────
# Scripts live in this repo under scripts/ and assets/. At provision time
# the Vagrantfile fetches them from raw.githubusercontent.com at $SCRIPTS_REF
# (overridable via VAGRANT_SCRIPTS_REF). For local development, set
# VAGRANT_SCRIPTS_DIR=./scripts to use on-disk files without pushing.
# See plans/0002-split-vagrantfile.md for the design rationale.
SCRIPTS_REPO = "docksdocks/vagrant"
SCRIPTS_REF  = ENV.fetch("VAGRANT_SCRIPTS_REF", "main")
LOCAL_DIR    = ENV["VAGRANT_SCRIPTS_DIR"]

SCRIPTS = %w[
  10-apt-repos
  20-packages
  30-guest-additions
  40-xfce-base
  41-xfce-theme
  50-vboxclient-supervisor
  51-vbox-autoresize
  55-permissions
  60-apps-tilix-mousepad
  65-superfile-fonts
  70-nodejs-claude
  80-git-ssh-lazygit
  85-secrets-env
  90-claude-config-sync
  99-finalize
]

Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-13"
  config.vm.hostname = "dev-box"

  # ── Rede ──────────────────────────────────────────────
  # config.vm.network "forwarded_port", guest: 3000, host: 3000
  # config.vm.network "forwarded_port", guest: 8080, host: 8080

  # ── Recursos da VM (alocação dinâmica) ───────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "debian13-dev"
    vb.gui    = true
    vb.memory = vm_memory
    vb.cpus   = vm_cpus
    vb.customize ["modifyvm", :id, "--vram", "256"]
    vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
    vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
    vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
    vb.customize ["modifyvm", :id, "--audio-driver", detect_audio_driver]
    vb.customize ["modifyvm", :id, "--audio-controller", "hda"]
    vb.customize ["modifyvm", :id, "--audio-enabled", "on"]
    vb.customize ["modifyvm", :id, "--audio-out", "on"]
    vb.customize ["modifyvm", :id, "--audio-in", "off"]
  end

  # ── Provisionamento: um shell provisioner por concern ──
  # Each script sources scripts/_lib.sh for shared helpers (currently just
  # fetch_asset). The inline runner below resolves the lib path for both
  # modes — local-dev uses /vagrant/scripts/_lib.sh, remote uses /tmp.
  SCRIPTS.each do |name|
    env = {
      "SCRIPTS_REPO"        => SCRIPTS_REPO,
      "SCRIPTS_REF"         => SCRIPTS_REF,
      "VAGRANT_SCRIPTS_DIR" => LOCAL_DIR,
      # Forward FORCE_REINSTALL so `FORCE_REINSTALL=1 vagrant provision`
      # bypasses the idempotency guards in 30-guest-additions.sh and
      # 70-nodejs-claude.sh.
      "FORCE_REINSTALL"     => ENV["FORCE_REINSTALL"],
    }.compact

    config.vm.provision name, type: "shell", env: env, inline: <<~SH
      set -euo pipefail
      # Defensive: ensure /tmp is sticky+world-write. bento/debian-13 ships
      # this correctly, but earlier base boxes (debian/testing64) did not, and
      # several scripts assume the vagrant user can create files/sockets there
      # (dbus-launch, git clone, fetch_asset's curl temp dir, ...).
      chmod 1777 /tmp

      if [ -n "${VAGRANT_SCRIPTS_DIR:-}" ]; then
        # Local-dev mode: the repo is mounted at /vagrant.
        export VAGRANT_LIB_PATH=/vagrant/scripts/_lib.sh
        bash /vagrant/scripts/#{name}.sh
      else
        # Debian minimal ships without curl; bootstrap it on first use.
        if ! command -v curl >/dev/null 2>&1; then
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -qq
          apt-get install -y -qq curl ca-certificates
        fi
        # Fetch _lib.sh once per provisioning run — cached at /tmp.
        export VAGRANT_LIB_PATH=/tmp/vagrant-_lib.sh
        if [ ! -f "$VAGRANT_LIB_PATH" ]; then
          curl -fsSL --retry 4 --retry-delay 2 \
            "https://raw.githubusercontent.com/#{SCRIPTS_REPO}/#{SCRIPTS_REF}/scripts/_lib.sh" \
            -o "$VAGRANT_LIB_PATH"
        fi
        curl -fsSL --retry 4 --retry-delay 2 \
          "https://raw.githubusercontent.com/#{SCRIPTS_REPO}/#{SCRIPTS_REF}/scripts/#{name}.sh" \
          -o /tmp/#{name}.sh
        bash /tmp/#{name}.sh
      fi
    SH
  end

end
