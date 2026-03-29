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

    # ── Repos externos (Chrome + Docker + GitHub CLI) ───────
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

    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
      gpg --batch --yes --dearmor -o /etc/apt/keyrings/githubcli.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list

    # ── Único update com todos os repos prontos ─────────────
    apt-get update -qq

    # ── Instalação em lote ──────────────────────────────────
    echo ">> Instalando todos os pacotes..."
    apt-get install -y -qq \
      git jq ripgrep build-essential tmux wget unzip shellcheck \
      fd-find fzf bat htop tree direnv \
      python3 python3-pip python3-venv \
      php-cli php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl \
      xfce4 xfce4-terminal \
      xfce4-notifyd xfce4-screenshooter xfce4-clipman-plugin \
      xfce4-whiskermenu-plugin xfce4-taskmanager mousepad \
      lightdm lightdm-gtk-greeter \
      dbus-x11 xdg-utils xclip \
      fonts-noto-color-emoji \
      arc-theme papirus-icon-theme fonts-noto fonts-noto-core dmz-cursor-theme \
      google-chrome-stable gh \
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

    # LightDM greeter com Arc-Dark + Papirus (tela de login)
    cat > /etc/lightdm/lightdm-gtk-greeter.conf <<'GREETER'
[greeter]
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 10
cursor-theme-name=DMZ-White
cursor-theme-size=24
background=#2b2b2b
GREETER

    # ── Tema visual (Arc-Dark + Papirus + Noto Sans) ────────
    mkdir -p /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml

    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml <<'XSETTINGS'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 10"/>
    <property name="CursorThemeName" type="string" value="DMZ-White"/>
    <property name="CursorThemeSize" type="int" value="24"/>
  </property>
</channel>
XSETTINGS

    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml <<'XFWM4'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
    <property name="title_font" type="string" value="Noto Sans Bold 10"/>
  </property>
</channel>
XFWM4

    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml <<'XFCETERM'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-terminal" version="1.0">
  <property name="misc-default-geometry" type="string" value="120x35"/>
  <property name="font-name" type="string" value="Noto Sans Mono 11"/>
  <property name="font-use-system" type="bool" value="false"/>
  <property name="color-background" type="string" value="#2b2b2b"/>
  <property name="color-foreground" type="string" value="#d3dae3"/>
  <property name="color-use-theme" type="bool" value="false"/>
  <property name="scrolling-unlimited" type="bool" value="true"/>
</channel>
XFCETERM

    # ── Painel XFCE (layout Ubuntu-like: top bar + bottom dock) ──
    cat > /home/vagrant/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml <<'XFCEPANEL'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <value type="int" value="2"/>
  </property>

  <!-- Panel 1: Top bar (GNOME-style) -->
  <property name="panels" type="empty">
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="28"/>
      <property name="length" type="uint" value="100"/>
      <property name="length-adjust" type="bool" value="false"/>
      <property name="background-style" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>

    <!-- Panel 2: Bottom dock (Ubuntu dash-style) -->
    <property name="panel-2" type="empty">
      <property name="position" type="string" value="p=12;x=0;y=0"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="48"/>
      <property name="length" type="uint" value="0"/>
      <property name="length-adjust" type="bool" value="true"/>
      <property name="background-style" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
        <value type="int" value="14"/>
      </property>
    </property>
  </property>

  <!-- Plugin definitions -->
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>

    <property name="plugin-2" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>

    <property name="plugin-3" type="string" value="clock">
      <property name="digital-format" type="string" value="%a %d %b  %H:%M"/>
      <property name="mode" type="uint" value="2"/>
    </property>

    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>

    <property name="plugin-5" type="string" value="clipman"/>

    <property name="plugin-6" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>

    <property name="plugin-7" type="string" value="notification-plugin"/>

    <property name="plugin-8" type="string" value="power-manager-plugin"/>

    <property name="plugin-9" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="terminal.desktop"/>
      </property>
    </property>

    <property name="plugin-10" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="filemanager.desktop"/>
      </property>
    </property>

    <property name="plugin-11" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="chrome.desktop"/>
      </property>
    </property>

    <property name="plugin-12" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="mousepad.desktop"/>
      </property>
    </property>

    <property name="plugin-13" type="string" value="separator">
      <property name="expand" type="bool" value="false"/>
      <property name="style" type="uint" value="0"/>
    </property>

    <property name="plugin-14" type="string" value="tasklist">
      <property name="show-labels" type="bool" value="false"/>
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="grouping" type="uint" value="1"/>
      <property name="show-handle" type="bool" value="false"/>
    </property>
  </property>
</channel>
XFCEPANEL

    # ── Launchers do dock (terminal, file manager, chrome, mousepad) ──
    mkdir -p /home/vagrant/.config/xfce4/panel/launcher-{9,10,11,12}

    cat > /home/vagrant/.config/xfce4/panel/launcher-9/terminal.desktop <<'LAUNCH1'
[Desktop Entry]
Type=Application
Name=Terminal
Icon=org.xfce.terminal
Exec=xfce4-terminal
StartupNotify=true
LAUNCH1

    cat > /home/vagrant/.config/xfce4/panel/launcher-10/filemanager.desktop <<'LAUNCH2'
[Desktop Entry]
Type=Application
Name=File Manager
Icon=org.xfce.thunar
Exec=thunar
StartupNotify=true
LAUNCH2

    cat > /home/vagrant/.config/xfce4/panel/launcher-11/chrome.desktop <<'LAUNCH3'
[Desktop Entry]
Type=Application
Name=Google Chrome
Icon=google-chrome
Exec=google-chrome-stable
StartupNotify=true
LAUNCH3

    cat > /home/vagrant/.config/xfce4/panel/launcher-12/mousepad.desktop <<'LAUNCH4'
[Desktop Entry]
Type=Application
Name=Mousepad
Icon=org.xfce.mousepad
Exec=mousepad
StartupNotify=true
LAUNCH4

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
    su - vagrant -c 'grep -q "alias fd=" ~/.bashrc 2>/dev/null || echo "alias fd=fdfind" >> ~/.bashrc'
    su - vagrant -c 'grep -q "alias bat=" ~/.bashrc 2>/dev/null || echo "alias bat=batcat" >> ~/.bashrc'
    su - vagrant -c 'grep -q "direnv hook" ~/.bashrc 2>/dev/null || echo "eval \"\$(direnv hook bash)\"" >> ~/.bashrc'

    # ── Git config ──────────────────────────────────────────
    su - vagrant -c 'git config --global init.defaultBranch main'
    su - vagrant -c 'git config --global user.name "Your Name"'
    su - vagrant -c 'git config --global user.email "you@example.com"'

    # ── Resumo ──────────────────────────────────────────────
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
    echo "  tmux       : $(tmux -V)"
    echo "  bat        : $(batcat --version | head -1)"
    echo "  fzf        : $(fzf --version)"
    echo "  htop       : $(htop --version | head -1)"
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
  SHELL
end
