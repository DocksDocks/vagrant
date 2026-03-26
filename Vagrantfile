# -*- mode: ruby -*-
# vi: set ft=ruby :

# ── Detecção automática de recursos do host ─────────────
# RAM: 25% do host, mín 2 GB, máx 8 GB
# CPUs: 50% do host, mín 1, máx 4
require 'rbconfig'

def detect_host_memory_mb
  host_os = RbConfig::CONFIG['host_os']
  if host_os =~ /darwin/i
    `sysctl -n hw.memsize`.to_i / 1024 / 1024
  elsif host_os =~ /linux/i
    `grep MemTotal /proc/meminfo`.split[1].to_i / 1024
  elsif host_os =~ /mswin|mingw|cygwin/i
    `powershell -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"`.strip.to_i / 1024 / 1024
  else
    8192 # fallback: assume 8 GB
  end
end

def detect_host_cpus
  host_os = RbConfig::CONFIG['host_os']
  if host_os =~ /darwin/i
    `sysctl -n hw.ncpu`.to_i
  elsif host_os =~ /linux/i
    `nproc`.to_i
  elsif host_os =~ /mswin|mingw|cygwin/i
    ENV['NUMBER_OF_PROCESSORS'].to_i
  else
    2 # fallback
  end
end

host_ram  = detect_host_memory_mb
host_cpus = detect_host_cpus

vm_memory = [[host_ram / 4, 2048].max, 8192].min  # 25% do host, entre 2 GB e 8 GB
vm_cpus   = [[host_cpus / 2, 1].max, 4].min       # 50% do host, entre 1 e 4

# ════════════════════════════════════════════════════════
# Host detectado: #{host_ram} MB RAM, #{host_cpus} CPUs
# VM alocada:     #{vm_memory} MB RAM, #{vm_cpus} CPUs
# ════════════════════════════════════════════════════════

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "dev-box"

  # ── Rede ──────────────────────────────────────────────
  # Porta SSH padrão já é encaminhada automaticamente (2222 → 22)
  # Adicione portas extras conforme necessário:
  # config.vm.network "forwarded_port", guest: 3000, host: 3000
  # config.vm.network "forwarded_port", guest: 8080, host: 8080

  # ── Recursos da VM (alocação dinâmica) ───────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "ubuntu24-dev"
    vb.gui    = true
    vb.memory = vm_memory
    vb.cpus   = vm_cpus
    vb.customize ["modifyvm", :id, "--vram", "128"]
    vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
    vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
    vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
  end

  # ── Provisionamento ──────────────────────────────────
  config.vm.provision "shell", inline: <<-SHELL
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # Evita prompts interativos do dpkg em arquivos de configuração
    cat > /etc/apt/apt.conf.d/99force-conf <<EOF
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
}
EOF

    echo "══════════════════════════════════════════"
    echo "  Atualizando sistema base"
    echo "══════════════════════════════════════════"
    apt-get update -qq
    apt-get upgrade -y -qq

    # ── Desktop XFCE ──────────────────────────────────────
    echo ">> Instalando XFCE desktop + utilitários..."
    apt-get install -y -qq \
      xfce4 xfce4-goodies xfce4-terminal \
      lightdm lightdm-gtk-greeter \
      dbus-x11 xdg-utils xclip \
      fonts-noto-color-emoji

    # Google Chrome
    echo ">> Instalando google chrome..."
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | \
      gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] \
      https://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list
    apt-get update -qq
    apt-get install -y -qq google-chrome-stable

    # Configura o LightDM como display manager padrão e habilita autologin
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=vagrant
autologin-user-timeout=0
user-session=xfce
EOF

    # Adiciona vagrant ao grupo autologin (necessário no LightDM)
    groupadd -f autologin
    usermod -aG autologin vagrant

    systemctl set-default graphical.target

    # Guest Additions para clipboard bidirecional e resize de tela
    apt-get install -y -qq virtualbox-guest-utils virtualbox-guest-x11

    # ── Git ─────────────────────────────────────────────
    echo ">> Instalando git..."
    apt-get install -y -qq git

    # ── Python ──────────────────────────────────────────
    echo ">> Instalando python..."
    apt-get install -y -qq python3 python3-pip python3-venv

    # ── ShellCheck ──────────────────────────────────────
    echo ">> Instalando shellcheck..."
    apt-get install -y -qq shellcheck

    # ── PHP + Composer ──────────────────────────────────
    echo ">> Instalando php + extensões comuns..."
    apt-get install -y -qq \
      php-cli php-common php-curl php-mbstring php-xml php-zip php-bcmath php-intl unzip

    echo ">> Instalando composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # ── Docker Engine + Docker Compose v2 ───────────────
    echo ">> Instalando docker..."
    apt-get install -y -qq ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Adiciona o usuário vagrant ao grupo docker (sem precisar de sudo)
    usermod -aG docker vagrant

    # ── Node.js LTS (via nvm) + npm + pnpm + Claude Code ─
    # Tudo instalado como vagrant user para manter PATH e permissões corretos.
    # nvm install --lts sempre resolve para o LTS vigente (hoje 24.x, amanhã o que for).
    echo ">> Instalando nvm + node LTS + pnpm + claude code (como vagrant)..."
    su - vagrant -c 'bash -c "\
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \
      export NVM_DIR=\"\$HOME/.nvm\" && \
      [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\" && \
      nvm install --lts && \
      nvm alias default lts/* && \
      npm install -g pnpm && \
      curl -fsSL https://claude.ai/install.sh | bash \
    "'

    # ── SSH Key + alias + ~/projects ──────────────────────
    echo ">> Configurando SSH key, alias e diretório de projetos..."
    su - vagrant -c 'bash -c "\
      mkdir -p ~/projects && \
      ssh-keygen -t ed25519 -C \"vagrant@dev-box\" -f ~/.ssh/id_ed25519 -N \"\" && \
      grep -qxF \"alias pf=\\\"cd ~/projects\\\"\" ~/.bashrc || \
        echo \"alias pf=\\\"cd ~/projects\\\"\" >> ~/.bashrc \
    "'

    # ── Resumo ──────────────────────────────────────────
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
    su - vagrant -c 'bash -c "
      export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
      echo \"  node       : \$(node --version)\"
      echo \"  npm        : \$(npm --version)\"
      echo \"  pnpm       : \$(pnpm --version)\"
    "'
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
