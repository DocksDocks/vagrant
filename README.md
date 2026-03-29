# Debian 12 Dev Box

Ambiente de desenvolvimento completo rodando em uma VM Debian 12 (Bookworm), provisionado automaticamente pelo Vagrant. Debian é mais leve que Ubuntu (~180 MB RAM base vs ~400 MB), usa `apt` igualmente, e mantém compatibilidade total com todas as ferramentas.

## Pré-requisitos

Instale os dois programas abaixo **antes** de começar:

1. **VirtualBox** — hipervisor que roda a VM por baixo dos panos.
   Baixe em: https://www.virtualbox.org/wiki/Downloads

2. **Vagrant** — ferramenta que automatiza a criação e configuração da VM a partir do `Vagrantfile`.
   Baixe em: https://developer.hashicorp.com/vagrant/install

> Ambos estão disponíveis para Windows, macOS e Linux. Após instalar, reinicie o terminal para garantir que os comandos `vagrant` e `VBoxManage` estejam no PATH.

## O que vem instalado

| Ferramenta       | Detalhes                                                        |
|------------------|-----------------------------------------------------------------|
| **XFCE 4**       | Desktop leve com LightDM e autologin (sem goodies desnecessários) |
| **Google Chrome** | Navegador pré-instalado (repo oficial Google)                   |
| **Git**          | Direto do repositório do Debian                                 |
| **GitHub CLI**   | `gh` — PRs, issues e repo ops direto do terminal                |
| **Python 3**     | Com `pip` e `venv`                                              |
| **PHP**          | CLI + extensões comuns (curl, mbstring, xml, zip, bcmath, intl) |
| **Composer**     | Gerenciador de dependências PHP                                 |
| **Docker**       | Engine + CLI + Buildx + Compose v2 (plugin, sem hífen)          |
| **Node.js LTS**  | Via `nvm` — sempre instala o LTS vigente                        |
| **npm**          | Vem junto com o Node                                            |
| **pnpm**         | Instalado globalmente via npm                                   |
| **Claude Code**  | CLI nativa da Anthropic                                         |
| **ShellCheck**   | Linter para shell scripts                                       |
| **jq**           | Processador JSON para terminal                                  |
| **ripgrep**      | Busca ultrarrápida em código (`rg`)                             |
| **build-essential** | gcc, make e headers — compilação de extensões nativas        |
| **tmux**         | Multiplexador de terminal                                       |
| **fzf**          | Fuzzy finder para terminal                                      |
| **bat**          | `cat` com syntax highlight (alias `bat` → `batcat`)             |
| **fd-find**      | Busca rápida de arquivos (alias `fd` → `fdfind`)                |
| **htop**         | Monitor de processos                                            |
| **tree**         | Visualização de diretórios                                      |
| **direnv**       | Variáveis de ambiente por projeto                               |
| **Lazygit**      | Interface Git no terminal (TUI) — staging, commits, branches    |

## Recursos da VM (alocação dinâmica)

O Vagrantfile detecta automaticamente a RAM e os CPUs do host e aloca proporcionalmente:

| Recurso | Regra                         | Mínimo | Máximo |
|---------|-------------------------------|--------|--------|
| RAM     | 25% do host                   | 2 GB   | 8 GB   |
| CPUs    | 50% do host                   | 1      | 4      |
| VRAM    | Fixo                          | 128 MB | 128 MB |
| Desktop | XFCE 4 (via LightDM com autologin) | —  | —      |

Exemplos de como fica na prática:

| Host         | VM recebe         |
|--------------|-------------------|
| 8 GB / 4 cores  | 2 GB RAM / 2 CPUs |
| 16 GB / 8 cores | 4 GB RAM / 4 CPUs |
| 32 GB / 12 cores | 8 GB RAM / 4 CPUs |
| 64 GB / 16 cores | 8 GB RAM / 4 CPUs |

Funciona em Windows, macOS e Linux. Você pode sobrescrever os valores editando `vm_memory` e `vm_cpus` diretamente no topo do `Vagrantfile`.

## Extras configurados automaticamente

- **Desktop XFCE** com autologin — ao rodar `vagrant up`, a janela do VirtualBox abre direto no desktop sem pedir senha.
- **Layout Ubuntu-like** — barra superior (whiskermenu, relógio centralizado, systray) + dock inferior centralizado (ícones de apps fixos + janelas abertas sem labels).
- **Dock com apps fixos** — Terminal, Thunar, Chrome e Mousepad prontos para uso com um clique.
- **Tema Arc-Dark** + ícones **Papirus-Dark** + fonte **Noto Sans** + cursor **DMZ-White** — visual moderno e limpo em dark mode.
- **Clipboard bidirecional** e **drag-and-drop** entre host e VM.
- **Google Chrome** pré-instalado para navegação dentro da VM.
- **Chave SSH ED25519** gerada em `~/.ssh/id_ed25519` — a chave pública é exibida no terminal ao final do provisionamento para você copiar direto pro GitHub/GitLab.
- **`~/projects`** — diretório para seus projetos, já criado.
- **Aliases** — `pf` (~/projects), `fd` (fdfind), `bat` (batcat).
- **Docker sem sudo** — o usuário `vagrant` já está no grupo `docker`.
- **direnv** — hook ativado no `.bashrc` para carregar `.envrc` automaticamente.
- **Áudio habilitado** — saída de som via Intel HD Audio (sem microfone).
- **Git config** — `init.defaultBranch` definido como `main`. Lembre-se de configurar `user.name` e `user.email`.
- **Timezone** configurado para `America/Sao_Paulo` (UTC-3).

## Primeiro uso (após provisionamento)

Após o primeiro `vagrant up`, configure seu nome e e-mail no Git e autentique no GitHub:

```bash
git config --global user.name "Seu Nome"
git config --global user.email "seu@email.com"
gh auth login
```

## Comandos principais

### Subir a VM pela primeira vez

```bash
vagrant up
```

Na primeira execução, o Vagrant baixa a imagem do Debian 12, cria a VM no VirtualBox e roda todo o provisionamento (instalação dos pacotes e desktop XFCE). Isso leva alguns minutos dependendo da sua conexão. A janela do VirtualBox abre automaticamente com o desktop XFCE e autologin como `vagrant`.

### Acessar a VM via SSH

```bash
vagrant ssh
```

Você entra como o usuário `vagrant`. Todas as ferramentas (node, docker, pnpm, claude, etc.) já estarão disponíveis no PATH.

### Desligar a VM

```bash
vagrant halt
```

Desliga a VM preservando todo o estado do disco. Na próxima vez que rodar `vagrant up`, ela sobe em segundos sem reprovisionar.

### Reprovisionar (reinstalar tudo)

```bash
vagrant provision
```

Útil se você editou o `Vagrantfile` e quer aplicar as mudanças sem destruir a VM. O script é idempotente — rodar mais de uma vez não duplica configurações.

### Destruir a VM completamente

```bash
vagrant destroy
```

Remove a VM e todo o disco virtual. Use quando quiser começar do zero. Ao rodar `vagrant up` novamente, tudo será recriado e provisionado.

### Ver status da VM

```bash
vagrant status
```

### Suspender / Retomar

```bash
vagrant suspend   # salva o estado em memória (como hibernar)
vagrant resume    # retoma de onde parou
```

## Adicionando portas

Se precisar acessar serviços da VM no navegador do host, descomente ou adicione linhas de `forwarded_port` no `Vagrantfile`:

```ruby
config.vm.network "forwarded_port", guest: 3000, host: 3000
config.vm.network "forwarded_port", guest: 8080, host: 8080
```

Depois rode `vagrant reload` para aplicar.

## Estrutura do repositório

```
.
├── Vagrantfile   # Toda a configuração e provisionamento da VM
└── README.md     # Este arquivo
```

## Expandindo

Para adicionar novas ferramentas, edite a seção de provisionamento no `Vagrantfile` (bloco `SHELL`) e rode `vagrant provision`. O script usa `set -euo pipefail`, então qualquer erro interrompe a execução para facilitar o debug.
