# Ubuntu 24.04 Dev Box

Ambiente de desenvolvimento completo rodando em uma VM Ubuntu 24.04 (Noble Numbat), provisionado automaticamente pelo Vagrant.

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
| **Git**          | Direto do repositório do Ubuntu                                 |
| **Python 3**     | Com `pip` e `venv`                                              |
| **PHP**          | CLI + extensões comuns (curl, mbstring, xml, zip, bcmath, intl) |
| **Composer**     | Gerenciador de dependências PHP                                 |
| **Docker**       | Engine + CLI + Buildx + Compose v2 (plugin, sem hífen)          |
| **Node.js LTS**  | Via `nvm` — sempre instala o LTS vigente                        |
| **npm**          | Vem junto com o Node                                            |
| **pnpm**         | Instalado globalmente via npm                                   |
| **Claude Code**  | CLI nativa da Anthropic                                         |
| **ShellCheck**   | Linter para shell scripts                                       |

## Recursos da VM

| Recurso | Valor padrão |
|---------|-------------|
| RAM     | 4 GB        |
| CPUs    | 2           |
| OS      | Ubuntu 24.04 LTS (Noble Numbat) |

Você pode ajustar RAM e CPUs editando `vb.memory` e `vb.cpus` no `Vagrantfile`.

## Extras configurados automaticamente

- **Chave SSH ED25519** gerada em `~/.ssh/id_ed25519` — a chave pública é exibida no terminal ao final do provisionamento para você copiar direto pro GitHub/GitLab.
- **`~/projects`** — diretório para seus projetos, já criado.
- **Alias `pf`** — digitar `pf` no terminal leva direto para `~/projects`.
- **Docker sem sudo** — o usuário `vagrant` já está no grupo `docker`.

## Comandos principais

### Subir a VM pela primeira vez

```bash
vagrant up
```

Na primeira execução, o Vagrant baixa a imagem do Ubuntu 24.04, cria a VM no VirtualBox e roda todo o provisionamento (instalação dos pacotes). Isso leva alguns minutos dependendo da sua conexão.

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
