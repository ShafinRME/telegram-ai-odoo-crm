# Odoo CRM Fields & Database Schema

## Odoo Automation User (Least-Privilege Setup)

A dedicated Odoo user is used for all API access, rather than the Administrator account, to limit blast radius if credentials leak.

| Setting                        | Value                                                                           |
| ------------------------------ | ------------------------------------------------------------------------------- |
| Name                           | Telegram AI Automation                                                          |
| Login                          | automation@nnsel.local                                                          |
| Access Rights → Sales          | User: All Documents                                                             |
| Access Rights → Administration | (none — blank)                                                                  |
| Auth method                    | API Key (generated via user's own Preferences → Account Security → New API Key) |

**Why not the Administrator account:** the automation only needs to create/read/update CRM leads and activities. Scoping to "Sales: All Documents" with no Administration rights means a leaked key cannot touch users, settings, invoicing, inventory, or any other module — verified during development when this user correctly received an `AccessError` attempting to query `ir.model`, a resource outside its granted scope.

## Standard `crm.lead` Fields Used

| Field          | Purpose                                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `name`         | Lead title, format: `Telegram Lead - {Customer Name} - {Product Interest}`                                               |
| `contact_name` | Customer's name (backfilled on every `Update Lead` call, not just at creation — see note below)                          |
| `phone`        | Telegram `chat.id` (numeric identifier, stored as text — not a real dialable phone number; see `LIMITATIONS.md`)         |
| `email_from`   | Customer's email (note: NOT `email` — see Troubleshooting #8)                                                            |
| `partner_name` | Company name, when provided (backfilled on every `Update Lead` call)                                                     |
| `description`  | Formatted summary (source, requirement, budget, timeline, location, AI score, conversation summary)                      |
| `user_id`      | Salesperson (defaults to Administrator, uid 2, for immediate visibility/follow-up in this single-salesperson deployment) |
| `priority`     | Lead priority (`"1"` = Medium, default)                                                                                  |

**Note on `contact_name`/`email_from`/`partner_name`:** during testing, leads were sometimes created before the AI had collected the customer's name (e.g., triggered early by a high-intent phrase like "I need a quotation"). The original design only wrote these fields at creation time, leaving them permanently blank even after the customer provided their name later in the conversation. Fixed by having `Update Lead` also backfill these three fields on every update, not just AI-extracted custom fields.

## Custom Fields Added to `crm.lead`

Added via Settings → Technical → Database Structure → Models → `crm.lead` → Fields tab (Odoo Studio is Enterprise-only; this method works on Community Edition).

| Field Name                 | Label                  | Type     | Purpose                                                                                                                        |
| -------------------------- | ---------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `x_telegram_chat_id`       | Telegram Chat ID       | Char     | Primary lookup key for search/update logic (renamed from `x_whatsapp_number` when the project moved from WhatsApp to Telegram) |
| `x_telegram_message_id`    | Telegram Message ID    | Char     | Traceability to originating message (renamed from `x_whatsapp_message_id`)                                                     |
| `x_product_interest`       | Product Interest       | Char     | AI-extracted product/service interest                                                                                          |
| `x_customer_requirement`   | Customer Requirement   | Text     | AI-extracted requirement details                                                                                               |
| `x_customer_budget`        | Customer Budget        | Char     | AI-extracted budget (free text, since customers rarely give exact figures)                                                     |
| `x_required_timeline`      | Required Timeline      | Char     | AI-extracted timeline                                                                                                          |
| `x_customer_location`      | Customer Location      | Char     | AI-extracted location                                                                                                          |
| `x_preferred_contact_time` | Preferred Contact Time | Char     | AI-extracted contact preference                                                                                                |
| `x_ai_lead_score`          | AI Lead Score          | Integer  | 0-100 score from the AI's assessment                                                                                           |
| `x_ai_summary`             | AI Summary             | Text     | AI-generated conversation summary                                                                                              |
| `x_handoff_reason`         | Handoff Reason         | Char     | Why human handoff was triggered, if applicable                                                                                 |
| `x_last_message_time`      | Last Message Time      | Datetime | Timestamp of the most recent customer message                                                                                  |

**Migration note:** `x_whatsapp_number` and `x_whatsapp_message_id` were renamed (technical name and label both changed) rather than recreated as new fields, to preserve the underlying database column and any existing data. All other custom fields are channel-agnostic and required no changes.

## Search / Create / Update Logic

- **Search:** `search_read` on `crm.lead` filtered by `x_telegram_chat_id`, ordered `id desc`, limit 1 — finds the most recent lead for that chat if multiple exist.
- **Create:** triggered when no existing lead is found and `lead_ready` or `human_handoff` is true.
- **Update:** triggered when a matching lead is found — writes both the AI-extracted custom fields and, as of the fix above, `contact_name`/`email_from`/`partner_name`, so a lead created with incomplete info self-heals as the conversation continues.

**Note on `lead_ready` reliability:** during testing, `gemma3:4b` occasionally failed to set `lead_ready: true` even when the customer used an explicit high-intent phrase covered by the AI rules (e.g., "I need a quotation, please call me"). To guarantee this critical business behavior isn't dependent on model compliance alone, a keyword-matching safety net was added in code (`Code in JavaScript3`/`Code in JavaScript4`): if the customer's message contains phrases like "call me", "quotation", "I am interested", etc., `leadReady` is forced `true` regardless of what the model returned. This is documented further in `LIMITATIONS.md`.

## Follow-up Activity Creation

Uses the `mail.activity` model, requiring both:

- `res_model` (string, `"crm.lead"`)
- `res_model_id` (integer — the `ir.model` table's ID for `crm.lead`; a stable technical constant, looked up once via Settings → Technical → Models)

Activity type: "Call" (`activity_type_id: 2`), assigned to the same default salesperson (uid 2), due the next day.

**Bug fixed during testing:** the original expression for `res_id` (`$('Create Lead').first().json.result || $('Extract Lead Match').first().json.existingLeadId`) crashed with a hard n8n error whenever the workflow took the `Update Lead` path instead of `Create Lead`, because referencing an unexecuted node's output throws before the `||` fallback can apply. Fixed using `$('Create Lead').isExecuted ? ... : ...` to safely check execution status first.

---

## PostgreSQL Database Schema

Five tables, defined in `db/init/01_schema.sql`, auto-applied on first Postgres container start. Table and column names were retained as-is from the original WhatsApp design (e.g. `phone_number`, `whatsapp_message_id`) rather than renamed, since they now generically store the Telegram `chat.id` and `message_id` respectively — renaming would have required a corresponding migration with no functional benefit.

### `contacts`

One row per unique Telegram customer. Tracks bot-control flags.

| Column                     | Type               | Notes                                                                                             |
| -------------------------- | ------------------ | ------------------------------------------------------------------------------------------------- |
| `id`                       | SERIAL PK          |                                                                                                   |
| `phone_number`             | VARCHAR(20) UNIQUE | Stores the Telegram `chat.id` (numeric, cast to text)                                             |
| `customer_name`            | VARCHAR(255)       |                                                                                                   |
| `email`                    | VARCHAR(255)       |                                                                                                   |
| `company`                  | VARCHAR(255)       |                                                                                                   |
| `language`                 | VARCHAR(10)        | default `'en'`                                                                                    |
| `ai_enabled`               | BOOLEAN            | default `true` — manual kill-switch per customer                                                  |
| `human_handoff`            | BOOLEAN            | default `false` — set true when AI hands off; bot then skips AI on future messages from this chat |
| `created_at`, `updated_at` | TIMESTAMPTZ        |                                                                                                   |

### `messages`

Full raw log of every inbound/outbound message.

| Column                | Type                | Notes                            |
| --------------------- | ------------------- | -------------------------------- |
| `id`                  | SERIAL PK           |                                  |
| `whatsapp_message_id` | VARCHAR(255) UNIQUE | Stores the Telegram `message_id` |
| `phone_number`        | VARCHAR(20)         | Stores the Telegram `chat.id`    |
| `direction`           | VARCHAR(10)         | `'inbound'` or `'outbound'`      |
| `message_text`        | TEXT                |                                  |
| `message_type`        | VARCHAR(20)         | default `'text'`                 |
| `created_at`          | TIMESTAMPTZ         |                                  |

### `conversations`

(Reserved for future use — summary/state tracking beyond raw message log; not actively written to in current implementation, as `contacts` + `messages` + Odoo's own lead history cover the MVP's needs.)

### `processed_messages`

Prevents duplicate processing when Telegram resends a webhook event.

| Column                | Type            | Notes                            |
| --------------------- | --------------- | -------------------------------- |
| `whatsapp_message_id` | VARCHAR(255) PK | Stores the Telegram `message_id` |
| `processed_at`        | TIMESTAMPTZ     |                                  |

Checked at the start of the message-handling chain (`Check Duplicate` → `Is Duplicate` IF node); written at the end (`Mark as Processed`), only after the full pipeline (AI reply, logging, and any Odoo action) completes — ensuring a message is never marked "processed" if the pipeline failed partway through.

**Bug fixed during testing:** the `Execute a SQL query` node that loads conversation history was referencing `$json.senderPhone`, which by that point in the chain no longer carried that field (it had been overwritten by the intervening `Check Duplicate` Postgres node's output). This silently caused conversation history to always return empty, making the AI repeat its introduction instead of progressing the conversation. Fixed by explicitly referencing `$('Code in JavaScript1').first().json.senderPhone` instead of relying on `$json`.

### `error_logs`

Captures unhandled workflow-level failures via a dedicated n8n Error Workflow.

| Column          | Type         | Notes                             |
| --------------- | ------------ | --------------------------------- |
| `id`            | SERIAL PK    |                                   |
| `workflow_name` | VARCHAR(255) |                                   |
| `node_name`     | VARCHAR(255) | last node executed before failure |
| `error_message` | TEXT         |                                   |
| `execution_id`  | VARCHAR(255) |                                   |
| `occurred_at`   | TIMESTAMPTZ  |                                   |

Note: only catches _unhandled_ failures. Nodes explicitly configured with "Continue on Fail" (e.g., the Telegram send node, so a delivery failure doesn't block CRM logging) do not trigger this log — a deliberate tradeoff documented in `LIMITATIONS.md`.
