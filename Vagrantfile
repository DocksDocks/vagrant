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
WINDOWS = !(HOST_OS =~ /mswin|mingw|cygwin/i).nil?

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
  lines << "  \e[2m↑/↓\e[0m mover   \e[2m1-#{profiles.length}\e[0m ir   \e[1;92m↵ Enter\e[0m confirmar   \e[2mq\e[0m cancelar"
  $stdout.print "\e[H\e[2J" + lines.join("\r\n") + "\r\n"
  $stdout.flush
end

# ── Leitura de teclas: por que dois caminhos ────────────
# As setas chegam ao processo de formas diferentes conforme o host:
#   • Unix/macOS (e Windows Terminal em modo VT): rajada ANSI "\e[A"/"\e[B",
#     que um IO.select + read_nonblock captura inteira.
#   • Console clássico do Windows (cmd.exe/PowerShell em conhost, o padrão):
#     as setas NÃO viram bytes no stdin lido por read_nonblock — só aparecem
#     via getch, como tecla estendida = prefixo 0x00/0xE0 + scancode ASCII
#     (H=0x48 cima, P=0x50 baixo). Por isso, no Windows, "q"/"j"/"k"/Enter
#     (caracteres normais) funcionavam mas as setas não faziam nada.
# Refs.: ruby/io-console console.c (getch devolve prefixo+scancode numa só
# chamada) e docs Oracle/MS sobre o prefixo 0xE0 de teclas estendidas.
# Os decodificadores são puros (entrada -> símbolo) p/ serem testáveis sem
# TTY; veja plans/0005-windows-console-arrow-keys.md.

# Decodifica a rajada Unix (string ANSI) numa ação normalizada.
def decode_unix_burst(burst)
  case burst
  when "\e[A", "\eOA", "k"     then :up
  when "\e[B", "\eOB", "j"     then :down
  when "\r", "\n"              then :enter
  when "q", "\e", "", 3.chr    then :cancel  # q / Esc / EOF / Ctrl-C
  else
    burst =~ /\A[1-9]\z/ ? [:digit, burst.to_i] : :other
  end
end

# Decodifica os bytes devolvidos por getch (Windows) numa ação. Uma tecla
# estendida vem como 2+ bytes terminando no scancode ASCII; analisamos por
# bytes para não depender da codepage, que pode reencodar o prefixo 0xE0.
def decode_win_getch(bytes)
  if bytes.length >= 2
    case bytes.last
    when 0x48 then :up      # scancode 'H' (seta para cima)
    when 0x50 then :down    # scancode 'P' (seta para baixo)
    else :other            # esquerda/direita/PgUp/F-keys -- ignorado
    end
  else
    case bytes.first
    when 0x0D, 0x0A       then :enter            # Enter (CR/LF)
    when 0x6B             then :up               # k
    when 0x6A             then :down             # j
    when 0x71, 0x1B, 0x03 then :cancel           # q / Esc / Ctrl-C
    when 0x31..0x39       then [:digit, bytes.first - 0x30]
    else :other
    end
  end
end

# Leitor Unix: bloqueia até haver entrada e devolve a ação da rajada.
def next_action_unix
  IO.select([$stdin])
  decode_unix_burst($stdin.read_nonblock(16))
rescue IO::WaitReadable
  retry
rescue EOFError
  :cancel
end

# Leitor Windows: getch (read_nonblock não enxerga as setas). getch já gere o
# modo do console, então não precisa do bloco raw.
def next_action_windows
  decode_win_getch($stdin.getch.bytes)
end

# Laço comum do menu: redesenha, lê uma ação (via bloco) e atualiza o cursor.
# Recebe o leitor como bloco para servir tanto Unix quanto Windows. Retorna o
# índice 1-based escolhido (Enter) ou :cancel.
def run_menu_loop(profiles, host_ram, host_cpus, cursor, saved_idx)
  loop do
    render_profile_menu(profiles, host_ram, host_cpus, cursor, saved_idx)
    case (action = yield)
    when :up     then cursor = (cursor - 1) % profiles.length
    when :down   then cursor = (cursor + 1) % profiles.length
    when :enter  then return cursor + 1
    when :cancel then return :cancel
    else
      if action.is_a?(Array) && action.first == :digit &&
         (1..profiles.length).cover?(action.last)
        cursor = action.last - 1
      end
    end
  end
end

# Abre o menu na tela alternativa. No Unix usa raw mode + leitor de rajada; no
# Windows usa getch direto. Pode levantar exceção se o terminal não suportar
# (o chamador trata como fallback silencioso ao padrão).
def interactive_profile_menu(profiles, host_ram, host_cpus, initial_idx, saved_idx)
  cursor = initial_idx - 1
  $stdout.print "\e[?1049h\e[?25l"  # tela alternativa + esconde cursor
  begin
    if WINDOWS
      run_menu_loop(profiles, host_ram, host_cpus, cursor, saved_idx) { next_action_windows }
    else
      $stdin.raw do
        run_menu_loop(profiles, host_ram, host_cpus, cursor, saved_idx) { next_action_unix }
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
  15-grub-quickboot
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
  80-git-ssh
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
