# Known Limitations

Honest accounting of what this system does and doesn't do, per the brief's expectation that the "owner understands" these tradeoffs of a free, self-hosted MVP.

## Infrastructure Limitations (Inherent to the Free/Self-Hosted Approach)

- **The PC must remain powered on.** All services (n8n, Ollama, Odoo, Postgres) run locally via Docker. If the machine sleeps, shuts down, or loses power, the entire pipeline stops.
- **The internet connection must remain active.** Both the Cloudflare tunnel and the Telegram Bot API calls require connectivity.
- **Cloudflare Quick Tunnel is for testing only**, not guaranteed uptime, per Cloudflare's own terms. The public URL changes every time the tunnel process restarts, requiring the workflow to be re-published in n8n each time so Telegram re-registers the new webhook URL (documented in `TROUBLESHOOTING.md` #1).
- **Local AI response speed depends on hardware.** On this deployment (~5.7GB available RAM), `gemma3:4b` responds in roughly 6–65+ seconds depending on prompt length, conversation history size, and whether the model needs to reload from a cold state. Switching between two different models on the same Ollama instance (e.g. during evaluation) can trigger unusually long load times — observed once taking several minutes, resolved by restarting the Ollama container.
- **A small local model (gemma3:4b) may be less accurate or nuanced than a large paid cloud model** — acceptable for MVP-scale lead qualification, not guaranteed to match GPT-4-class reasoning. See "AI Behavior Limitations" below for specific instances encountered.

## Telegram-Specific Notes (Compared to the Original WhatsApp Approach)

This project was originally built against the WhatsApp Cloud API and converted to Telegram partway through development at the client's request, since WhatsApp's Meta Developer setup proved substantially more complex to configure and test than necessary for this MVP's goals. Telegram removed several WhatsApp-specific limitations entirely:

- No business verification, app review, or development-mode recipient allowlist — any user can message the bot immediately.
- No 24-hour access token expiry — the bot token is permanent until manually revoked.
- No fake-sender test-button limitation — every test message is a real, full end-to-end path.

One new consideration introduced by the switch:

- **The `phone` field on each Odoo lead stores the customer's Telegram `chat.id`, not a real dialable phone number.** Telegram does not require or typically expose a user's actual phone number to bots. The AI is prompted to ask for a callback number naturally during conversation (stored in `x_customer_requirement`/lead notes context), but the structured `phone` field itself is not guaranteed to contain a dialable number unless the customer explicitly provides one in free text and the AI captures it into the `lead.phone` field.

## Security Limitations

- **The Cloudflare Quick Tunnel exposes the entire n8n application** (including its login page), not just the `/webhook/` path — a limitation of unauthenticated Quick Tunnels, which proxy the whole target port. Mitigated by n8n's own account authentication (strong password) and by never tunneling Odoo or Postgres directly. Documented in `TROUBLESHOOTING.md`.
- **`N8N_BLOCK_ENV_ACCESS_IN_NODE` is set to `"false"`**, allowing any node in this n8n instance to read environment variables (needed for the Odoo API key / DB name / bot token pattern used throughout). Acceptable for this single-purpose, single-workflow instance; would need a more scoped secrets-management approach if this n8n instance ever hosted multiple, less-trusted workflows.
- **`N8N_ENCRYPTION_KEY` was left at its initial value** rather than rotated during hardening, because rotating it would invalidate all already-stored n8n credentials (Postgres, Odoo Basic Auth, Telegram API), requiring re-entry. Documented as a deliberate tradeoff, not an oversight.

## AI Behavior Limitations

- **`gemma3:4b` does not always reliably set `lead_ready: true`**, even for messages containing explicit high-intent phrases the prompt instructs it to treat as auto-triggers (e.g., "I need a quotation, please call me"). This was observed directly during testing: identical trigger phrases sometimes correctly flipped `lead_ready` and sometimes did not, despite an unchanged prompt. Since reliable lead capture is a core business requirement, a keyword-matching safety net was added in code (`Code in JavaScript3`/`Code in JavaScript4`) that forces `leadReady: true` whenever the customer's raw message text contains one of the defined trigger phrases, independent of what the model itself decided. This guarantees the business-critical behavior without depending entirely on model compliance.
- **Language-matching required explicit code-level detection rather than relying on model inference.** The initial prompt design asked the model to "reply in the same language as the current message, ignoring earlier history" — this instruction was inspected directly in the actual prompt sent to the model (confirmed correct and unambiguous) but was still not reliably followed once a conversation had several Bangla-language turns in its history; the model would continue replying in Bangla even when the customer switched back to English. Fixed by detecting the current message's language programmatically in code (Unicode range check for Bangla script, `\u0980-\u09FF`) and injecting the result as a direct factual instruction (e.g., "reply in ENGLISH") rather than asking the model to infer it — this converts a reasoning task the model was failing at into a simple compliance task, which resolved the issue in testing.
- **A brief side-by-side comparison with `qwen3:4b` was conducted** to evaluate whether a different small model would handle instruction-following (particularly language-matching) more reliably. Two issues were found: (1) Qwen 3 operates in "thinking mode" by default, returning its answer inside a separate `thinking` field rather than the `response` field Ollama's `format: json` expects, causing every response to appear empty and trigger the fallback path until `"think": false` was added to the request body; (2) even with thinking mode disabled, Qwen 3 at this size occasionally returned degenerate output (echoing a chunk of the business-information JSON verbatim instead of a real reply) on this project's specific prompt structure. `gemma3:4b` was kept as the production model after this comparison, since it produced more consistent, on-topic responses once Rule 0 (explicit anti-repetition instruction) and the language-detection fix were applied.
- **The AI occasionally repeated its introduction instead of progressing the conversation**, even when conversation history was present, until an explicit instruction (referred to internally as "Rule 0") was added directing the model to read the history, avoid re-introducing the company, and avoid repeating any earlier reply. This was a genuine prompt-engineering gap, not a data-loading bug — the underlying history-loading logic was separately confirmed correct (see Functional/Logic Limitations below for a related but distinct bug that was also found and fixed).

## Functional / Logic Limitations

- **Error logging only captures unhandled workflow-level failures.** Nodes explicitly set to "Continue on Fail" (e.g., the Telegram send node — so a delivery failure doesn't block CRM lead logging) do not trigger an `error_logs` entry. A production system would benefit from a secondary "soft failure" logging path for these cases.
- **`Update Lead` only backfills a fixed set of fields.** If a lead is created early in a conversation (e.g., triggered by a high-intent phrase before the customer's name or other details are known), those fields remain blank until a later message causes an update. This was observed directly during testing and partially addressed by extending `Update Lead` to also backfill `contact_name`, `email_from`, and `partner_name` on every update (previously only written once, at creation) — however, any field not included in this backfill list will still remain permanently blank if it was empty at creation time.
- **The `conversations` table is defined in the schema but not actively used** in the current implementation — `contacts`, `messages`, and Odoo's own lead/activity history together cover the MVP's tracking needs. Reserved for future conversation-summary features.
- **Bangla language support is verified end-to-end** through real Telegram conversations during development (unlike the earlier WhatsApp attempt, where Meta's development-mode restrictions prevented full real-conversation testing) — both English-to-English and Bangla-to-Bangla exchanges were confirmed working after the language-detection fix described above.

## Cost Disclaimer

Electricity and internet connectivity costs to keep the PC and network running continuously are not included in "free software," per the brief's own framing (Section 19). This MVP is intended for low message volume and demonstration/pilot use, not high-throughput production traffic.
