# Telegram AI + Odoo CRM — Setup & Operations Guide

## Prerequisites

- Windows 10/11 or Ubuntu
- Docker Desktop (with WSL2 on Windows)
- Git
- A Telegram account (to create the bot via @BotFather — no business verification or app review required)
- ~6GB free RAM for the Ollama model (gemma3:4b)

## First-Time Installation

1. Clone the repository:

```bash
   git clone https://github.com/ShafinRME/telegram-ai-odoo-crm.git
   cd telegram-ai-odoo-crm
```

2. Copy the environment template and fill in real values:

```bash
   cp .env.example .env
```

Edit `.env` and set: `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`, `ODOO_API_KEY`, `TELEGRAM_BOT_TOKEN`, `WEBHOOK_URL`, `ODOO_DB_NAME`, `ODOO_AUTOMATION_UID`.

3. Start all services:

```bash
   docker compose up -d
   docker compose ps
```

Confirm all 4 containers (`crm_postgres`, `crm_odoo`, `crm_n8n`, `crm_ollama`) show as running/healthy, and that `crm_ollama` shows its port mapping (`0.0.0.0:11434->11434/tcp`) — on Windows, a fresh restart can occasionally leave this port unbound due to a WSL2/Hyper-V NAT reservation issue; if so, run `net stop winnat && net start winnat` as Administrator, then retry `docker compose up -d` (see `TROUBLESHOOTING.md`).

4. Pull the Ollama model (first time only):

```bash
   docker exec crm_ollama ollama pull gemma3:4b
```

5. Set up Odoo:
   - Visit `http://localhost:8069`
   - Create database `nn_crm` (or your chosen name, matching `ODOO_DB_NAME` in `.env`)
   - Activate the CRM module
   - Create a least-privilege automation user, generate its API key (see `ODOO_FIELDS_AND_SCHEMA.md`)
   - Add the 12 custom `x_` fields to `crm.lead` (see `ODOO_FIELDS_AND_SCHEMA.md`)

6. Set up n8n:
   - Visit `http://localhost:5678`
   - Complete first-time owner account setup
   - Import the workflow from `n8n/workflows/telegram-ai-odoo-crm-main.json`
   - Re-enter credentials (Postgres, Odoo Basic Auth, Telegram API) since these are not exported for security
   - Publish the workflow — this automatically registers the webhook with Telegram, no manual dashboard step required

7. Set up the Cloudflare tunnel and Telegram bot — see `TELEGRAM_BOT_SETUP.md`.

## Daily "Start Everything" Routine

Every time you restart your PC or the services stop, run this sequence:

```bash
# 1. Start Docker services
cd telegram-ai-odoo-crm
docker compose up -d
docker compose ps

# 2. In a SEPARATE terminal window (keep it open):
cd scripts
./cloudflared.exe tunnel --url http://localhost:5678
```

3. Copy the new tunnel URL from the output.
4. Update `.env`: `WEBHOOK_URL=https://NEW-URL.trycloudflare.com/` (trailing slash required)
5. Restart n8n to pick up the new URL:

```bash
   docker compose up -d n8n
```

6. Re-publish the workflow in the n8n UI (Editor → Publish) — this re-registers the webhook against the new tunnel URL. Unlike WhatsApp, there is no separate dashboard step to update a callback URL.
7. Confirm the webhook registered correctly:

```bash
   source .env
   curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

Expect `"ok": true` with `"url"` matching the new tunnel address and `"pending_update_count": 0`.

8. If Ollama has been idle a while, warm it up before testing:

```bash
   curl -X POST http://localhost:11434/api/generate -d "{\"model\": \"gemma3:4b\", \"prompt\": \"hello\", \"stream\": false}"
```

Expect a response within roughly 20-90 seconds on cold start (longer if the container was just restarted or a different model was recently loaded — see `TROUBLESHOOTING.md`).

## Stopping Everything

```bash
docker compose down
```

(Use `docker compose stop` instead if you want to keep containers without removing them.)

Close the cloudflared terminal window to stop the tunnel.

## Backup

**Postgres backup:**

```bash
docker exec crm_postgres pg_dump -U odoo postgres > db/backups/postgres_backup_$(date +%Y%m%d).sql
```

**Odoo database backup:**

```bash
docker exec crm_postgres pg_dump -U odoo nn_crm > db/backups/odoo_backup_$(date +%Y%m%d).sql
```

**n8n workflow backup:**
Export the workflow from the n8n UI (Editor → "..." menu → Export) periodically, save to `n8n/workflows/`.

## Restore

**Postgres restore:**

```bash
cat db/backups/postgres_backup_YYYYMMDD.sql | docker exec -i crm_postgres psql -U odoo -d postgres
```

**Odoo restore:**

```bash
cat db/backups/odoo_backup_YYYYMMDD.sql | docker exec -i crm_postgres psql -U odoo -d nn_crm
```

## Manually Disabling the AI Assistant

To stop the bot from responding to a specific customer (required by brief Section 15):

```bash
docker exec -it crm_postgres psql -U odoo -d postgres -c "UPDATE contacts SET ai_enabled = false WHERE phone_number = 'CUSTOMER_CHAT_ID';"
```

(`phone_number` column stores the Telegram `chat.id` — find it in the `contacts` table or from an n8n execution's Telegram Trigger output.)

To re-enable:

```bash
docker exec -it crm_postgres psql -U odoo -d postgres -c "UPDATE contacts SET ai_enabled = true WHERE phone_number = 'CUSTOMER_CHAT_ID';"
```

## Resetting a Test Conversation

Useful during development/demo prep to clear a specific chat's history and reset its handoff status without affecting other customers or existing Odoo leads:

```bash
docker exec -it crm_postgres psql -U odoo -d postgres -c "DELETE FROM messages WHERE phone_number = 'CUSTOMER_CHAT_ID'; DELETE FROM processed_messages WHERE whatsapp_message_id IN (SELECT whatsapp_message_id FROM messages WHERE phone_number = 'CUSTOMER_CHAT_ID'); UPDATE contacts SET human_handoff = false WHERE phone_number = 'CUSTOMER_CHAT_ID';"
```
