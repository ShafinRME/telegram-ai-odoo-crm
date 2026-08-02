Here's the fully rewritten `TROUBLESHOOTING.md` — removed the WhatsApp/Meta-only issues that no longer apply (fake sender allowlist, temp token expiry, dev-mode message blocking), rewrote the Telegram equivalents, and added the four real bugs we found and fixed during this session's Telegram conversion that future maintainers would genuinely hit.

````markdown
# Troubleshooting Guide

This guide documents real issues encountered during development, their root causes, and verified fixes — not hypothetical scenarios.

---

## 1. Cloudflare Tunnel URL Changed / Webhook Stopped Working

**Symptom:** `curl: (6) Could not resolve host` when checking the webhook, or sending a message to the bot produces no execution in n8n.

**Root cause:** Cloudflare Quick Tunnels generate a new random subdomain every time the tunnel process restarts (by design — Cloudflare states these are for testing only, with no persistence guarantee). If the terminal running `cloudflared` was closed, crashed, or the PC slept, the tunnel dies and any new tunnel gets a different URL.

**Fix:**

1. Restart the tunnel: `./cloudflared.exe tunnel --url http://localhost:5678`
2. Copy the new URL from the output
3. Update `.env`: `WEBHOOK_URL=https://NEW-URL.trycloudflare.com/` (trailing slash required)
4. Restart n8n: `docker compose up -d n8n`
5. Re-publish the workflow in the n8n UI (Editor → Publish) — this re-registers the webhook with Telegram
6. Verify with: `curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"` — confirm `"url"` matches the new tunnel address

**Prevention:** Keep the cloudflared terminal window open and undisturbed for the entire working session. Do not rely on it surviving a sleep/hibernate cycle.

---

## 2. "duplicate key value violates unique constraint messages_whatsapp_message_id_key"

**Symptom:** `Execute a SQL query1` (or `Execute a SQL query`) node fails with a Postgres unique constraint violation.

**Root cause:** Repeated testing with the same conversation can attempt to insert a row with a message ID that's already present, which the `messages` table's UNIQUE constraint on `whatsapp_message_id` (this column stores Telegram's `message_id` — retained under its original name from the WhatsApp version rather than renamed, since it's purely internal) correctly rejects.

**Fix (during testing only), to reset a specific chat's history:**

```bash
docker exec -it crm_postgres psql -U odoo -d postgres -c "DELETE FROM messages WHERE phone_number = 'CUSTOMER_CHAT_ID';"
docker exec -it crm_postgres psql -U odoo -d postgres -c "DELETE FROM processed_messages WHERE whatsapp_message_id IN (SELECT whatsapp_message_id FROM messages WHERE phone_number = 'CUSTOMER_CHAT_ID');"
```
````

**Why this isn't a production bug:** Real Telegram messages have unique, sequential message IDs per chat. This collision only occurs when deliberately re-testing without cleanup. The `processed_messages` dedup table (see below) is the _correct_ mechanism for handling genuine duplicate webhook deliveries in production.

---

## 3. Ollama Times Out / "Connection was aborted, perhaps the server is offline"

**Symptom:** `HTTP Request1` (or `HTTP Request2`) to Ollama fails after several minutes.

**Root cause:** Ollama unloads the model from memory after a period of inactivity (`OLLAMA_KEEP_ALIVE=30m` in our config). The first request after this window has to reload the ~3-4GB model into RAM, which on modest hardware (this deployment: ~5.7GB available RAM) can take longer than n8n's default HTTP timeout.

**Fix:** Warm up Ollama before testing:

```bash
curl -X POST http://localhost:11434/api/generate -d "{\"model\": \"gemma3:4b\", \"prompt\": \"hello\", \"stream\": false}"
```

Wait for a response (10-65s typical after a cold start), then proceed with the actual test.

**Mitigation built into the workflow:** Both Ollama HTTP Request nodes have "Continue on Fail" enabled, so a timeout triggers the retry logic and eventually the safe fallback reply rather than crashing the entire execution.

**Related issue — abnormally long hangs after switching models:** during development, a model switch (evaluating `qwen3:4b` as an alternative, then reverting to `gemma3:4b`) once caused a single request to hang for roughly 8 minutes instead of the normal cold-start window. Restarting the Ollama container (`docker compose restart ollama`) resolved it immediately, and a subsequent warm-up completed in the normal ~65 seconds. Suspected cause: memory pressure from Ollama holding a previous model in RAM while attempting to load a different one. If a request hangs well beyond the normal cold-start range, restart the Ollama container rather than waiting further.

---

## 4. n8n Expression Shows Literal `{{ $env.VARIABLE }}` Text Instead of the Value

**Symptom:** Postgres/Odoo errors reference the literal string `{{ $env.ODOO_DB_NAME }}` instead of the actual database name.

**Root cause:** Two possible causes, both encountered during development:

- The field was in "Fixed" mode, not "Expression" mode — n8n only evaluates `{{ }}` syntax in Expression mode.
- `N8N_BLOCK_ENV_ACCESS_IN_NODE` was not set to `"false"` — by default, recent n8n versions block node-level access to environment variables as a security default.

**Fix:**

1. Confirm the field shows the purple "Expression" toggle active, not "Fixed."
2. Confirm `docker-compose.yml`'s n8n service includes:

```yaml
N8N_BLOCK_ENV_ACCESS_IN_NODE: "false"
```

3. Restart n8n after any docker-compose change: `docker compose up -d n8n`

**Security note:** This flag broadens env var access to all nodes in the instance, not just the ones that need it. Acceptable for this single-workflow deployment; would need a more scoped secrets approach (e.g., per-credential storage) in a multi-workflow production environment.

**Related note — credential fields specifically do NOT evaluate `{{ $env.* }}` expressions.** Unlike node parameter fields, n8n's Credential UI (e.g., the Telegram API credential's Access Token field) shows `[ERROR: not accessible via UI, please run node]` if given an environment-variable expression — credential fields require the literal resolved value pasted directly. This is by design (n8n encrypts credential values at rest) and is a different mechanism from the node-level env access controlled by the flag above.

---

## 5. Telegram Bot Token Compromised or Needs Rotation

**Symptom:** Bot stops authenticating, or the token was accidentally exposed (e.g., pasted somewhere it shouldn't have been).

**Fix:**

1. Telegram → message @BotFather → `/mybots` → select the bot → Bot Settings → API Token → "Revoke current token"
2. BotFather issues a new token immediately
3. Update `TELEGRAM_BOT_TOKEN` in `.env`
4. Update the Telegram API credential in n8n (Credentials → Telegram - NNSEL Bot → paste the new token directly into the Access Token field — see note in #4 above about why this can't use an env expression)
5. `docker compose up -d n8n`

**Design note, and how this differs from the original WhatsApp setup:** Telegram bot tokens do not expire on their own (unlike Meta's WhatsApp temporary access tokens, which required regeneration roughly every 24 hours during development). Rotation is only needed if the token is compromised, not on any routine schedule.

---

## 6. Webhook Registers with an Empty `"url"` Field / "Bad Request: bad webhook: An HTTPS URL must be provided for webhook"

**Symptom:** Testing the Telegram Trigger node fails with this exact error, or `getWebhookInfo` shows `"url": ""`.

**Root cause:** Telegram requires webhooks to be registered over a public HTTPS URL. If n8n's `WEBHOOK_URL` environment variable is unset, or still points to `http://localhost:5678`, n8n attempts to register that invalid address with Telegram, which rejects it outright.

**Fix:**

1. Ensure `.env` has `WEBHOOK_URL=https://YOUR-TUNNEL-URL.trycloudflare.com/` (trailing slash required) set to the currently-live tunnel address
2. Ensure `docker-compose.yml`'s n8n service passes this through: `WEBHOOK_URL: ${WEBHOOK_URL}`
3. Restart n8n: `docker compose up -d n8n`
4. Re-publish the workflow (not just "Test this trigger" — see #7 below for why this distinction matters)

---

## 7. Telegram Trigger Works During "Test this trigger" But Stops Receiving Messages Afterward

**Symptom:** Clicking "Test this trigger" and sending a message works once, but no further messages are received, and `getWebhookInfo` shows `"url": ""` again afterward.

**Root cause:** In n8n, "Test this trigger" (or "Stop Listening") registers the webhook with Telegram only for the duration that specific test panel is open. Closing it or clicking "Stop Listening" causes n8n to **delete** the webhook registration from Telegram entirely — this is different behavior from a fully **activated/published** workflow, which registers the webhook persistently.

**Fix:** For continuous, real listening (not just a one-off test), the workflow must be **Published** (or Activated, depending on n8n version), not just tested via the node's live-listening panel. After publishing, verify with `getWebhookInfo` that `"url"` is populated and stays populated even after closing the workflow editor tab.

---

## 8. `Invalid field 'email' on model 'crm.lead'`

**Symptom:** Odoo `create` call on `crm.lead` fails with this error.

**Root cause:** Odoo 17's `crm.lead` model does not have a field literally named `email` — the correct field name is `email_from`.

**Fix:** Use `"email_from"` as the JSON key when creating/updating leads via the Odoo JSON-RPC API.

**Lesson:** Always verify actual field names against the live model schema (`Settings → Technical → Database Structure → Models`) rather than assuming standard/intuitive names — Odoo's internal naming doesn't always match UI labels.

---

## 9. `Create Follow-up Activity` Fails: "Invalid field 'res_model_id'... not-null constraint"

**Symptom:** `mail.activity` create call fails, complaining `res_model_id` is required.

**Root cause:** `mail.activity` requires both `res_model` (string, e.g. `"crm.lead"`) AND `res_model_id` (integer, the `ir.model` table's internal ID for that model) — passing only the string is insufficient.

**Fix:** Look up the numeric model ID once via Odoo UI (`Settings → Technical → Models → search "crm.lead"` → check the ID in the URL), then hardcode it (`401` in this deployment) since it's a stable technical constant, not user data.

---

## 10. Duplicate-Check Always Returns `cnt: 0` Even Though the Row Exists

**Symptom:** `Is Duplicate` always takes the "not a duplicate" branch, even on repeated test runs with the same message ID.

**Root cause:** The `Check Duplicate` SQL node referenced `{{ $json.messageId }}`, but by that point in the chain `$json` referred to the **previous node's** output (`Upsert Contact`, which returns `phone_number`/`ai_enabled`/`human_handoff`, not `messageId`). The expression silently resolved to an empty string, so the query effectively checked for an empty message ID that never matches anything.

**Fix:** Use an explicit node reference instead of the implicit `$json`:

```sql
WHERE whatsapp_message_id = '{{ $('Code in JavaScript1').first().json.messageId }}'
```

**Lesson:** In multi-node n8n chains, `$json` always means "immediately preceding node's output," not "any earlier node's output you might have in mind." When in doubt, use explicit `$('Node Name').first().json.field` references — verbose, but unambiguous and safe against future rewiring.

**A second instance of the identical bug class was found later** in `Execute a SQL query` (the conversation-history loader), which also referenced `$json.senderPhone` instead of `$('Code in JavaScript1').first().json.senderPhone`. This silently caused conversation history to always load empty, making the AI repeat its introduction instead of progressing the conversation — a much harder bug to diagnose than a hard error, since the workflow "succeeded" on every run with no visible failure. Confirmed and fixed the same way.

---

## 11. n8n Login Page Publicly Reachable via Tunnel

**Symptom / Finding:** `curl -I https://<tunnel-url>/` returns `200 OK` for the root n8n path, not just `/webhook/...`.

**Root cause:** Cloudflare Quick Tunnels proxy the entire target port (5678), not specific paths. There is no path-based routing without a paid/configured named Cloudflare tunnel with Access rules.

**Mitigation in place:**

- n8n's own account authentication (not the deprecated `N8N_BASIC_AUTH_*` env vars, which n8n newer versions ignore in favor of built-in user management) is the actual access gate — verified with a strong, unique password.
- Odoo (8069) and Postgres (5432) are never tunneled — only n8n's port is exposed.
- This is documented as an accepted limitation of the free/Quick-Tunnel architecture, not something silently overlooked.

**Recommendation for anyone extending this project:** Stop the tunnel when not actively testing, and/or enable n8n 2FA before any extended public-facing testing window.

---

## 12. Odoo `Update Lead` Crashes When the Lead Was Just Created in the Same Execution

**Symptom:** `Create Follow-up Activity` fails with an n8n error: _"An expression references this node, but the node is unexecuted... There is no connection back to the node 'Create Lead', but it's used in an expression here."_

**Root cause:** The `res_id` expression used a fallback pattern (`$('Create Lead').first().json.result || $('Extract Lead Match').first().json.existingLeadId`), intending "use Create Lead's result if it ran, otherwise fall back to the existing lead ID." However, in n8n, referencing `.first().json` on a node that did not execute in this run throws an error immediately — the `||` never gets a chance to apply, because the left-hand side itself fails to evaluate.

This only surfaces when the workflow takes the `Update Lead` path (an existing lead was found) rather than `Create Lead` — meaning it can pass testing repeatedly if early tests always create new leads, and only appear once a genuine repeat-customer scenario is tested.

**Fix:** Use `.isExecuted` to safely check before accessing the node's output:

```
"res_id": $('Create Lead').isExecuted ? $('Create Lead').first().json.result : $('Extract Lead Match').first().json.existingLeadId
```

**Lesson:** In n8n, conditional branches that only sometimes execute a given node require `.isExecuted` checks before dereferencing that node's output — a plain `||` fallback is not sufficient, since the error occurs at expression-evaluation time, before the `||` operator can short-circuit.

---

## 13. Odoo HTTP Request Fails: "The value in the \"JSON Body\" field is not valid JSON"

**Symptom:** `Create Lead`, `Update Lead`, or `Create Follow-up Activity` fails with this error, intermittently — often only on some conversations, not others.

**Root cause:** The original JSON bodies were built as raw strings with AI-generated text values interpolated directly (e.g., `"contact_name": "{{ ...lead.name }}"`). Whenever the AI's extracted text happened to contain a double quote, apostrophe, or newline (e.g., a customer's message containing an apostrophe), it broke the surrounding JSON string syntax, since nothing was escaping those characters before insertion.

**Fix:** Rewrote the affected nodes' bodies as native JavaScript object expressions instead of raw JSON strings — i.e., the entire "JSON Body" field becomes a single `{{ {...} }}` expression returning a JS object, which n8n automatically serializes to valid JSON with correct escaping, rather than a string with `{{ }}` values spliced in. This eliminates the entire bug class rather than patching individual cases.

**Example (before → after) for one field:**

Before (string interpolation, breaks on special characters):

```
"contact_name": "{{ $('Code in JavaScript3').first().json.lead.name }}"
```

After (native object expression, entire body is one `{{ }}` block):

```
{{ {
  ...
  "contact_name": $('Code in JavaScript3').first().json.lead.name,
  ...
} }}
```

**Lesson:** For any n8n HTTP node embedding AI-generated or user-generated free text into a JSON body, prefer native object expressions over string interpolation — this is a general-purpose fix that prevents an entire category of intermittent, hard-to-reproduce failures.

```

```
