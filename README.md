Here's the complete `README.md` in one file — everything tied together.

```markdown
# Telegram AI + Odoo CRM Lead Automation

A free, self-hosted customer service and lead-qualification system built for **NN Services & Engineering Ltd. (NNSEL)**, a real estate company in Dhaka, Bangladesh.

A customer messages the business on Telegram → a locally-hosted AI assistant (Ollama, no paid API) chats with them, answers common questions, and collects lead information naturally → the system automatically creates or updates the lead in **Odoo CRM (Community Edition)** and schedules a follow-up activity for the sales team.

Everything except Telegram's own Bot API runs on a single local PC via Docker — no paid AI API, no paid automation platform, no paid hosting, no Odoo Enterprise license.

---

## Architecture
```

Customer sends a Telegram message
↓
Telegram Bot API delivers it to n8n via webhook (public URL via Cloudflare Quick Tunnel)
↓
n8n checks for duplicate delivery, loads conversation history from PostgreSQL
↓
n8n sends the message + history + business knowledge to Ollama (local AI, gemma3:4b)
↓
Ollama returns structured JSON: reply text, lead readiness, human-handoff status, extracted lead fields
↓
n8n sends the reply back via Telegram, logs the conversation to PostgreSQL
↓
If enough lead information is available:
↓
n8n searches Odoo CRM for an existing lead (by Telegram chat ID)
↓
Creates a new lead, or updates the existing one — never duplicates
↓
Creates a follow-up "Call" activity for the salesperson

```

**Stack:** Docker & Docker Compose · n8n (Community Edition) · Ollama (`gemma3:4b`) · Odoo 17 (Community Edition) · PostgreSQL 15 · Cloudflare Quick Tunnel · Telegram Bot API

---

## Project History

This project was originally built against the **WhatsApp Cloud API** (Meta Developer platform) and later converted to **Telegram** at the client's request, since Telegram's bot setup proved significantly simpler — no business verification, no app review process, no 24-hour token expiry, and no development-mode recipient restrictions.

Every bug found and fixed during both the original build and the Telegram conversion is documented honestly in `docs/TROUBLESHOOTING.md` and `docs/LIMITATIONS.md`, including real issues like silent `$json` reference bugs that caused conversation history to load empty, an Odoo JSON escaping crash fixed by switching to native object expressions, and AI instruction-following limitations (language-matching, lead-readiness detection) that required code-level safety nets rather than relying on prompt engineering alone.

---

## Repository Structure

```

telegram-ai-odoo-crm/
├── docker-compose.yml # All 4 services: postgres, odoo, n8n, ollama
├── .env.example # Environment variable template
├── business-knowledge/
│ ├── company_info.json # NNSEL business info (editable without touching the workflow)
│ └── system_prompt.txt # AI system prompt reference
├── db/
│ ├── init/01_schema.sql # Postgres schema (contacts, messages, conversations, etc.)
│ └── backups/
├── docs/
│ ├── SETUP_AND_OPERATIONS.md # Install, start/stop, backup/restore, daily routine
│ ├── TROUBLESHOOTING.md # 13 real issues encountered, with root causes and fixes
│ ├── TELEGRAM_BOT_SETUP.md # Bot creation, webhook setup, verification
│ ├── ODOO_FIELDS_AND_SCHEMA.md # Field list, DB schema, search/create/update logic
│ └── LIMITATIONS.md # Honest accounting of what this MVP does and doesn't do
├── n8n/
│ └── workflows/
│ └── telegram-ai-odoo-crm-main.json # Exported workflow, credentials redacted
├── media/
│ └── demo_video.mp4 # Full end-to-end demo
└── scripts/
└── cloudflared.exe # Cloudflare Quick Tunnel binary (gitignored)

````

---

## Quick Start

```bash
git clone https://github.com/ShafinRME/telegram-ai-odoo-crm.git
cd telegram-ai-odoo-crm
cp .env.example .env
# edit .env with real values (see below)
docker compose up -d
docker compose ps        # confirm all 4 containers running/healthy
docker exec crm_ollama ollama pull gemma3:4b
````

Then:

1. **Set up Odoo** — visit `http://localhost:8069`, create a database, activate the CRM module, create a least-privilege automation user, add the 12 custom `x_` fields. Full details: `docs/ODOO_FIELDS_AND_SCHEMA.md`.
2. **Create the Telegram bot** — via @BotFather, get a token, set up the Cloudflare tunnel and webhook. Full details: `docs/TELEGRAM_BOT_SETUP.md`.
3. **Set up n8n** — visit `http://localhost:5678`, import `n8n/workflows/telegram-ai-odoo-crm-main.json`, re-enter credentials (Postgres, Odoo, Telegram API — not exported for security), publish the workflow.

Full step-by-step instructions, including the daily "start everything" routine after a PC restart, are in `docs/SETUP_AND_OPERATIONS.md`.

### Required `.env` values

See `.env.example` for the full template. Key variables:

| Variable                                              | Purpose                                                   |
| ----------------------------------------------------- | --------------------------------------------------------- |
| `POSTGRES_PASSWORD`                                   | Postgres database password                                |
| `N8N_ENCRYPTION_KEY`                                  | n8n credential encryption key                             |
| `WEBHOOK_URL`                                         | Current Cloudflare tunnel URL (changes on tunnel restart) |
| `TELEGRAM_BOT_TOKEN`                                  | Bot token from @BotFather                                 |
| `ODOO_DB_NAME`, `ODOO_AUTOMATION_UID`, `ODOO_API_KEY` | Odoo automation user credentials                          |

---

## AI Behavior

The assistant:

- Replies in the customer's language (English or Bangla), detected programmatically per message
- Asks one or two questions at a time, never re-asking for information already given
- Never invents prices, features, policies, or delivery dates — only uses the approved business knowledge in `business-knowledge/company_info.json`
- Collects lead details naturally: name, phone, company, product interest, requirement, location, budget, timeline, email, preferred contact time
- Returns structured JSON (reply, lead readiness, human-handoff status, extracted lead fields, lead score) — validated in code, with an automatic retry and safe fallback reply if the AI ever returns invalid JSON
- Hands off to a human team member on request, complaint, anger, final-pricing questions, legal/payment questions, or repeated AI failure

See `docs/LIMITATIONS.md` for honest notes on where the local model (`gemma3:4b`) needed code-level safety nets to reliably follow instructions — specifically around language-matching and lead-readiness detection.

---

## Security

- All credentials (Postgres, Odoo, Telegram) live in `.env` (gitignored) or n8n's encrypted Credential store — never hardcoded into workflow nodes
- The exported workflow JSON has all token/credential references redacted before being committed
- Odoo automation uses a dedicated least-privilege user (Sales-only access, no Administration rights) rather than the Administrator account
- Only n8n's port is exposed via the Cloudflare tunnel — Odoo and Postgres are never publicly reachable
- A manual per-customer AI kill-switch exists (`ai_enabled` flag in the `contacts` table) — see `docs/SETUP_AND_OPERATIONS.md`

---

## Known Limitations

This is a free, self-hosted MVP, not a production-scale deployment. Full details in `docs/LIMITATIONS.md`, but in short:

- The PC and internet connection must stay on and connected for the system to work
- Cloudflare Quick Tunnel has no uptime guarantee and its URL changes on restart
- Local AI response speed and accuracy depend on hardware and model size
- Suitable for low message volume and demonstration/pilot use

---

## Deliverables Checklist (per project brief)

- [x] Working n8n workflow
- [x] Exported n8n workflow JSON (tokens redacted)
- [x] Docker Compose file
- [x] Ollama model and configuration details
- [x] AI system prompt
- [x] Odoo field list and configuration
- [x] Database table structure
- [x] Environment variable example file
- [x] Setup instructions
- [x] Start and stop instructions
- [x] Backup and restore instructions
- [x] Error troubleshooting guide
- [x] Telegram bot / webhook setup guide
- [x] Short demo video
- [x] All source code

---

## Demo Video

[Watch the full demo on Google Drive] https://drive.google.com/file/d/1nChlWrGU9lJEMOgABP_wtodAjVXR2cQU/view?usp=sharing

## Author

**Md. Shafin Ahmed**
Full Stack Web Developer · BSc & MSc, Robotics & Mechatronics Engineering, University of Dhaka
GitHub: [ShafinRME](https://github.com/ShafinRME)

```

```
