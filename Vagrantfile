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

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"
  config.vm.hostname = "dev-box"

  # ── Rede ──────────────────────────────────────────────
  # config.vm.network "forwarded_port", guest: 3000, host: 3000
  # config.vm.network "forwarded_port", guest: 8080, host: 8080

  # ── Recursos da VM (alocação dinâmica) ───────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "debian12-dev"
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

  # ── Provisionamento ──────────────────────────────────
  config.vm.provision "shell", inline: <<-'SHELL'
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # ── Força dpkg não-interativo ───────────────────────────
    cat > /etc/apt/apt.conf.d/99force-conf <<'APTCONF'
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
}
APTCONF

    echo "══════════════════════════════════════════"
    echo "  Atualizando sistema base"
    echo "══════════════════════════════════════════"

    # ── Ferramentas essenciais (Debian minimal não inclui curl) ─
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq curl ca-certificates gnupg
    install -m 0755 -d /etc/apt/keyrings

    # ── Timezone (sem depender de timedatectl/dbus) ─────────
    ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
    echo "America/Sao_Paulo" > /etc/timezone

    # ── Repos externos (Chrome + Docker) ───────────────────
    echo ">> Configurando repositórios externos..."

    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | \
      gpg --batch --yes --dearmor -o /etc/apt/keyrings/google-chrome.gpg
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main' \
      > /etc/apt/sources.list.d/google-chrome.list

    curl -fsSL https://download.docker.com/linux/debian/gpg | \
      gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list

    # ── Único update com todos os repos prontos ─────────────
    apt-get update -qq

    # ── Instalação em lote ──────────────────────────────────
    echo ">> Instalando todos os pacotes..."
    apt-get install -y -qq \
      git python3 python3-pip python3-venv shellcheck unzip \
      php-cli php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl \
      xfce4 xfce4-goodies xfce4-terminal \
      lightdm lightdm-gtk-greeter \
      dbus-x11 xdg-utils xclip \
      pulseaudio xfce4-pulseaudio-plugin alsa-utils \
      fonts-noto-color-emoji \
      gnome-themes-extra adwaita-icon-theme \
      google-chrome-stable \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # ── Composer ────────────────────────────────────────────
    echo ">> Instalando composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # ── Docker (grupo) ──────────────────────────────────────
    usermod -aG docker vagrant

    # ── LightDM autologin ───────────────────────────────────
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<'LIGHTDM'
[Seat:*]
autologin-user=vagrant
autologin-user-timeout=0
user-session=xfce
LIGHTDM

    getent group autologin >/dev/null || groupadd autologin
    usermod -aG autologin vagrant
    systemctl set-default graphical.target

    # ── Dark mode (XFCE + GTK + terminal) ───────────────────
    mkdir -p /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml

    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'XSETTINGS'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
</channel>
XSETTINGS

    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'XFWM4'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default-hdpi"/>
  </property>
</channel>
XFWM4

    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml <<'XFCETERM'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-terminal" version="1.0">
  <property name="misc-default-geometry" type="string" value="120x35"/>
  <property name="color-background" type="string" value="#1e1e1e"/>
  <property name="color-foreground" type="string" value="#d4d4d4"/>
  <property name="color-use-theme" type="bool" value="false"/>
</channel>
XFCETERM

    # ── Chrome como navegador padrão ────────────────────────
    mkdir -p /home/vagrant/.config/xfce4/helpers
    cat > /home/vagrant/.config/xfce4/helpers/google-chrome.desktop <<'CHROMEHELPER'
[Desktop Entry]
X-XFCE-Binaries=google-chrome-stable;google-chrome;
X-XFCE-Category=WebBrowser
X-XFCE-Commands=%B;%B;
X-XFCE-CommandsWithParameter=%B "%s";%B "%s";
Type=X-XFCE-Helper
Name=Google Chrome
Icon=google-chrome
CHROMEHELPER

    echo "WebBrowser=google-chrome" > /home/vagrant/.config/xfce4/helpers.rc

    cat > /home/vagrant/.config/mimeapps.list <<'MIMEAPPS'
[Default Applications]
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop
text/html=google-chrome.desktop
MIMEAPPS

    cp /usr/share/applications/google-chrome.desktop \
       /usr/share/applications/exo-web-browser.desktop 2>/dev/null || true

    chown -R vagrant:vagrant /home/vagrant/.config

    # ── Node.js LTS (via nvm) + pnpm + Claude Code ──────────
    echo ">> Instalando nvm + node LTS + pnpm + claude code..."
    su - vagrant -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
    su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh && nvm install --lts && nvm alias default lts/* && npm install -g pnpm'
    su - vagrant -c 'curl -fsSL https://claude.ai/install.sh | bash'

    # ── SSH Key + alias + ~/projects ────────────────────────
    echo ">> Configurando SSH key, alias e diretório de projetos..."
    su - vagrant -c 'mkdir -p ~/projects'
    su - vagrant -c 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -C "vagrant@dev-box" -f ~/.ssh/id_ed25519 -N ""'
    su - vagrant -c 'grep -q "alias pf=" ~/.bashrc 2>/dev/null || echo "alias pf=\"cd ~/projects\"" >> ~/.bashrc'

    # ── Resumo ──────────────────────────────────────────────
    echo ""
    echo "══════════════════════════════════════════"
    echo "  Provisionamento concluído!"
    echo "══════════════════════════════════════════"
    echo "  git        : $(git --version)"
    echo "  python     : $(python3 --version)"
    echo "  php        : $(php --version | head -1)"
    echo "  composer   : $(composer --version 2>&1 | head -1)"
    echo "  docker     : $(docker --version)"
    echo "  compose    : $(docker compose version)"
    echo "  shellcheck : $(shellcheck --version | grep version:)"
    su - vagrant -c 'source /home/vagrant/.nvm/nvm.sh && echo "  node       : $(node --version)" && echo "  npm        : $(npm --version)" && echo "  pnpm       : $(pnpm --version)"'
    echo "══════════════════════════════════════════"
    echo ""
    echo "══════════════════════════════════════════"
    echo "  SSH Public Key (copie para GitHub/etc):"
    echo "══════════════════════════════════════════"
    cat /home/vagrant/.ssh/id_ed25519.pub
    echo ""
    echo "══════════════════════════════════════════"
  SHELL
end
