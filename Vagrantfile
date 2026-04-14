# -*- mode: ruby -*-
# vi: set ft=ruby :

# ── Detecção automática de recursos do host ─────────────
# RAM: 25% do host, mín 2 GB, máx 8 GB
# CPUs: 50% do host, mín 1, máx 4
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

host_ram  = detect_host_memory_mb
host_cpus = detect_host_cpus

vm_memory = [[host_ram / 4, 2048].max, 8192].min
vm_cpus   = [[host_cpus / 2, 1].max, 4].min

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
  60-apps-tilix-mousepad
  70-nodejs-claude
  80-git-ssh-lazygit
  90-claude-config-sync
]

Vagrant.configure("2") do |config|
  config.vm.box = "debian/testing64"
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
    vb.customize ["modifyvm", :id, "--vram", "128"]
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
  SCRIPTS.each do |name|
    env = {
      "SCRIPTS_REPO"        => SCRIPTS_REPO,
      "SCRIPTS_REF"         => SCRIPTS_REF,
      "VAGRANT_SCRIPTS_DIR" => LOCAL_DIR,
    }.compact

    if LOCAL_DIR
      config.vm.provision name, type: "shell",
                                path: "#{LOCAL_DIR}/#{name}.sh",
                                env: env
    else
      url = "https://raw.githubusercontent.com/#{SCRIPTS_REPO}/#{SCRIPTS_REF}/scripts/#{name}.sh"
      config.vm.provision name, type: "shell", env: env, inline: <<~SH
        set -euo pipefail
        # debian/testing64 ships /tmp without sticky world-write; restore it so
        # the vagrant user can create files/sockets (dbus-launch, git clone, ...).
        chmod 1777 /tmp
        # Debian minimal ships without curl; bootstrap it on first use.
        if ! command -v curl >/dev/null 2>&1; then
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -qq
          apt-get install -y -qq curl ca-certificates
        fi
        curl -fsSL --retry 4 --retry-delay 2 "#{url}" -o /tmp/#{name}.sh
        bash /tmp/#{name}.sh
      SH
    end
  end

  # ── Finalize: resumo + reboot no primeiro provisionamento ──
  config.vm.provision "99-finalize", type: "shell", inline: <<-'SHELL'
    set -euo pipefail

    echo ""
    echo "══════════════════════════════════════════"
    echo "  Provisionamento concluído!"
    echo "══════════════════════════════════════════"
    echo "  git        : $(git --version)"
    echo "  gh         : $(gh --version | head -1)"
    echo "  python     : $(python3 --version)"
    echo "  php        : $(php --version | head -1)"
    echo "  composer   : $(composer --version 2>&1 | head -1)"
    echo "  docker     : $(docker --version)"
    echo "  compose    : $(docker compose version)"
    echo "  shellcheck : $(shellcheck --version | grep version:)"
    echo "  jq         : $(jq --version)"
    echo "  ripgrep    : $(rg --version | head -1)"
    echo "  tilix      : $(tilix --version 2>&1 | head -1)"
    echo "  bat        : $(batcat --version | head -1)"
    echo "  fzf        : $(fzf --version)"
    echo "  htop       : $(htop --version | head -1)"
    echo "  lazygit    : $(lazygit --version | head -1)"
    su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh && echo "  node       : $(node --version)" && echo "  npm        : $(npm --version)" && echo "  pnpm       : $(pnpm --version)"'
    echo "══════════════════════════════════════════"
    echo ""
    echo "══════════════════════════════════════════"
    echo "  SSH Public Key (copie para GitHub/etc):"
    echo "══════════════════════════════════════════"
    cat /home/vagrant/.ssh/id_ed25519.pub
    echo ""
    echo "══════════════════════════════════════════"
    echo ""
    echo "  ⚠ Lembre-se de configurar:"
    echo "    git config --global user.name \"Seu Nome\""
    echo "    git config --global user.email \"seu@email.com\""
    echo "    gh auth login"
    echo "══════════════════════════════════════════"

    # ── Reboot para ativar graphical.target + autologin (só no primeiro provisionamento) ────
    if [ ! -f /var/lib/vagrant-provisioned ]; then
      touch /var/lib/vagrant-provisioned
      echo ">> Reiniciando para ativar desktop com autologin..."
      nohup bash -c 'sleep 5 && reboot' &>/dev/null &
    fi
  SHELL
end
