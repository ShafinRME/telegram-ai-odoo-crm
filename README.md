# Telegram AI + Odoo CRM Lead Automation

> A free, self-hosted AI customer service and lead qualification system — no paid APIs, no paid hosting, no Odoo Enterprise license required.

Built for **NN Services & Engineering Ltd. (NNSEL)**, a real estate company in Dhaka, Bangladesh.

---

## How It Works

```
Customer sends a Telegram message
        ↓
Telegram Bot API delivers it to n8n via webhook (Cloudflare Quick Tunnel)
        ↓
n8n checks for duplicate delivery, loads conversation history from PostgreSQL
        ↓
n8n sends message + history + business knowledge to Ollama (local AI — gemma3:4b)
        ↓
Ollama returns structured JSON:
  reply text · lead readiness · human-handoff status · extracted lead fields
        ↓
n8n sends the reply back via Telegram and logs the conversation to PostgreSQL
        ↓
If enough lead information is available:
        ↓
n8n searches Odoo CRM for an existing lead (by Telegram chat ID)
        ↓
Creates a new lead or updates the existing one — never duplicates
        ↓
Creates a follow-up "Call" activity for the salesperson
```

---

## Technology Stack

| Layer               | Tool                      |
| ------------------- | ------------------------- |
| Containerisation    | Docker & Docker Compose   |
| Workflow Automation | n8n Community Edition     |
| Local AI            | Ollama (`gemma3:4b`)      |
| CRM                 | Odoo 17 Community Edition |
| Database            | PostgreSQL 15             |
| Public Webhook      | Cloudflare Quick Tunnel   |
| Messaging           | Telegram Bot API          |

Everything runs on a single local PC. No paid services are required.

---

## Project Background

This project was originally built against the **WhatsApp Cloud API** (Meta Developer platform) and later converted to **Telegram** at the client's request. Telegram proved significantly simpler to set up — no business verification, no app review process, no 24-hour token expiry, and no development-mode recipient restrictions.

Every bug found and fixed during both the original build and the Telegram conversion is documented honestly in [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md), including real issues such as:

- Silent `$json` reference bugs that caused conversation history to load empty
- An Odoo JSON escaping crash fixed by switching to native object expressions
- AI instruction-following limitations (language-matching, lead-readiness detection) that required code-level safety nets rather than relying on prompt engineering alone

---

## Repository Structure

```
telegram-ai-odoo-crm/
├── docker-compose.yml                        # All 4 services: postgres, odoo, n8n, ollama
├── .env.example                              # Environment variable template
│
├── business-knowledge/
│   ├── company_info.json                     # NNSEL business info (editable without touching the workflow)
│   └── system_prompt.txt                     # AI system prompt reference
│
├── db/
│   ├── init/
│   │   └── 01_schema.sql                     # PostgreSQL schema (contacts, messages, conversations, etc.)
│   └── backups/
│
├── docs/
│   ├── SETUP_AND_OPERATIONS.md               # Install, start/stop, backup/restore, daily routine
│   ├── TROUBLESHOOTING.md                    # 13 real issues encountered, with root causes and fixes
│   ├── TELEGRAM_BOT_SETUP.md                 # Bot creation, webhook setup, verification
│   ├── ODOO_FIELDS_AND_SCHEMA.md             # Field list, DB schema, search/create/update logic
│   └── LIMITATIONS.md                        # Honest accounting of what this MVP does and does not do
│
├── n8n/
│   └── workflows/
│       └── telegram-ai-odoo-crm-main.json    # Exported workflow (credentials redacted)
│
├── media/
│   └── demo_video.mp4                        # Full end-to-end demo
│
└── scripts/
    └── cloudflared.exe                       # Cloudflare Quick Tunnel binary (gitignored)
```

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/ShafinRME/telegram-ai-odoo-crm.git
cd telegram-ai-odoo-crm
cp .env.example .env
# Edit .env with your real values — see the table below
```

### 2. Start all services

```bash
docker compose up -d
docker compose ps        # Confirm all 4 containers are running/healthy
```

### 3. Pull the AI model

```bash
docker exec crm_ollama ollama pull gemma3:4b
```

### 4. Complete setup

| Step     | What to do                                                                                                                              | Reference                                                          |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Odoo     | Visit `http://localhost:8069`, create a database, activate CRM, create a least-privilege automation user, add the 12 custom `x_` fields | [`docs/ODOO_FIELDS_AND_SCHEMA.md`](docs/ODOO_FIELDS_AND_SCHEMA.md) |
| Telegram | Create a bot via @BotFather, get the token, set up the Cloudflare tunnel and webhook                                                    | [`docs/TELEGRAM_BOT_SETUP.md`](docs/TELEGRAM_BOT_SETUP.md)         |
| n8n      | Visit `http://localhost:5678`, import the workflow JSON, re-enter credentials, publish the workflow                                     | [`docs/SETUP_AND_OPERATIONS.md`](docs/SETUP_AND_OPERATIONS.md)     |

---

## Environment Variables

See `.env.example` for the full template. Key variables:

| Variable              | Purpose                                                   |
| --------------------- | --------------------------------------------------------- |
| `POSTGRES_PASSWORD`   | PostgreSQL database password                              |
| `N8N_ENCRYPTION_KEY`  | n8n credential encryption key                             |
| `WEBHOOK_URL`         | Current Cloudflare tunnel URL (changes on tunnel restart) |
| `TELEGRAM_BOT_TOKEN`  | Bot token from @BotFather                                 |
| `ODOO_DB_NAME`        | Odoo database name                                        |
| `ODOO_AUTOMATION_UID` | Odoo automation user ID                                   |
| `ODOO_API_KEY`        | Odoo automation user API key                              |

---

## AI Behaviour

The assistant:

- Replies in the customer's language (English or Bangla), detected programmatically per message
- Asks one or two questions at a time and never re-asks for information already provided
- Never invents prices, features, policies, or delivery dates — only uses approved business knowledge from `business-knowledge/company_info.json`
- Collects lead details naturally: name, phone, company, product interest, requirement, location, budget, timeline, email, and preferred contact time
- Returns structured JSON (reply, lead readiness, human-handoff status, extracted lead fields, lead score), validated in code with an automatic retry and safe fallback reply if the AI returns invalid JSON
- Hands off to a human team member on request, complaint, anger, final-pricing questions, legal or payment questions, or repeated AI failure

See [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) for honest notes on where the local model (`gemma3:4b`) required code-level safety nets — specifically around language-matching and lead-readiness detection.

---

## Security

- All credentials (PostgreSQL, Odoo, Telegram) are stored in `.env` (gitignored) or n8n's encrypted Credential store — never hardcoded into workflow nodes
- The exported workflow JSON has all token and credential references redacted before being committed
- Odoo automation uses a dedicated least-privilege user (Sales-only access, no Administration rights)
- Only n8n's port is exposed via the Cloudflare tunnel — Odoo and PostgreSQL are never publicly reachable
- A manual per-customer AI kill-switch exists via the `ai_enabled` flag in the `contacts` table — see [`docs/SETUP_AND_OPERATIONS.md`](docs/SETUP_AND_OPERATIONS.md)

---

## Known Limitations

This is a free, self-hosted MVP, not a production-scale deployment. Full details are in [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md). In summary:

- The PC and internet connection must remain on for the system to work
- Cloudflare Quick Tunnel has no uptime guarantee and its URL changes on restart
- Local AI response speed and accuracy depend on PC hardware and model size
- Suitable for low message volume and demonstration or pilot use

---

## Deliverables Checklist

| #   | Deliverable                                  | Status |
| --- | -------------------------------------------- | ------ |
| 1   | Working n8n workflow                         | ✅     |
| 2   | Exported n8n workflow JSON (tokens redacted) | ✅     |
| 3   | Docker Compose file                          | ✅     |
| 4   | Ollama model and configuration details       | ✅     |
| 5   | AI system prompt                             | ✅     |
| 6   | Odoo field list and configuration            | ✅     |
| 7   | Database table structure                     | ✅     |
| 8   | Environment variable example file            | ✅     |
| 9   | Setup instructions                           | ✅     |
| 10  | Start and stop instructions                  | ✅     |
| 11  | Backup and restore instructions              | ✅     |
| 12  | Error troubleshooting guide                  | ✅     |
| 13  | Telegram bot and webhook setup guide         | ✅     |
| 14  | Short demo video                             | ✅     |
| 15  | All source code and configuration files      | ✅     |

---

## Demo Video

[▶ Watch the full end-to-end demo on Google Drive](https://drive.google.com/file/d/1nChlWrGU9lJEMOgABP_wtodAjVXR2cQU/view?usp=sharing)

---

## Author

**Md. Shafin Ahmed**  
Full Stack Web Developer  
BSc & MSc, Robotics & Mechatronics Engineering, University of Dhaka  
GitHub: [ShafinRME](https://github.com/ShafinRME)
