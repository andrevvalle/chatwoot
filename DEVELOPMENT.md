# Guia de Desenvolvimento - Chatwoot

Este documento explica como rodar o projeto em modo de desenvolvimento.

## Pré-requisitos

- Docker e Docker Compose
- Node.js e pnpm
- Ruby (via rbenv) - versão definida em `.ruby-version`

## Formas de Rodar o Projeto

Existem **duas formas** de rodar o projeto em desenvolvimento:

### Opção 1: Docker Completo (Recomendado para iniciantes)

Tudo roda dentro do Docker (Rails, Sidekiq, Vite, Redis, Postgres).

**Iniciar:**
```bash
docker compose up
```

**Parar:**
```bash
docker compose down
```

**Acessar:** http://localhost:3000

---

### Opção 2: Híbrido (Local + Docker)

Rails, Sidekiq e Vite rodam **localmente** via Overmind.
Redis e Postgres rodam no **Docker**.

Esta opção é mais rápida para desenvolvimento pois não precisa rebuildar imagens Docker.

**Iniciar:**

```bash
# 1. Subir apenas os serviços de infraestrutura (Redis, Postgres, Mailhog)
docker compose up -d redis postgres mailhog

# 2. Rodar a aplicação localmente
overmind start -f Procfile.dev
```

**Parar:**

```bash
# 1. Parar a aplicação local (em outro terminal)
overmind stop

# OU se o overmind não responder, matar os processos manualmente:
pkill -f "puma"
pkill -f "sidekiq"
pkill -f "vite"

# 2. Parar os containers Docker
docker compose down
```

**Acessar:** http://localhost:3000

---

## Comandos Úteis

| Ação | Comando |
|------|---------|
| Ver containers rodando | `docker ps` |
| Ver processos locais | `ps aux \| grep -E "(puma\|sidekiq\|vite)"` |
| Logs do Docker | `docker compose logs -f` |
| Logs do Overmind | Aparecem no terminal onde foi iniciado |
| Reiniciar um serviço (overmind) | `overmind restart backend` |
| Console Rails (local) | `bundle exec rails c` |
| Console Rails (docker) | `docker compose exec rails bundle exec rails c` |

## Problemas Comuns

### Redis::CannotConnectError

**Causa:** O Redis não está rodando.

**Solução:**
- Se usando Docker completo: `docker compose up`
- Se usando modo híbrido: `docker compose up -d redis`

### Processos órfãos após `docker compose down`

**Causa:** Você estava rodando no modo híbrido. O `docker compose down` só para containers Docker, não processos locais.

**Solução:**
```bash
pkill -f "puma"
pkill -f "sidekiq"
pkill -f "vite"
```

### Porta 3000 já em uso

**Causa:** Outro processo está usando a porta.

**Solução:**
```bash
# Descobrir o processo
lsof -i :3000

# Matar o processo
kill -9 <PID>
```
