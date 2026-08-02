# Telegram Bot Webhook Setup Guide

## 1. Create the Telegram Bot

1. Open Telegram and search for **@BotFather** (official bot-creation account, verified with a blue checkmark)
2. Send `/start`, then `/newbot`
3. Choose a display name (e.g. "NNSEL AI Lead Assistant") and a unique username ending in `bot` (e.g. `nnsel_ai_assistant_bot`)
4. BotFather replies with a **bot token** — copy it immediately

Unlike WhatsApp's Meta App setup, there is no business verification, no app review, and no naming/trademark restrictions.

## 2. Generate and Store the Bot Token

1. Store the token in `.env` as `TELEGRAM_BOT_TOKEN` — never hardcode it directly into n8n nodes (see Security notes below)
2. **This token does not expire** — unlike WhatsApp's 24-hour temporary access token, it remains valid indefinitely until manually revoked via BotFather
3. If the token is ever exposed (e.g. accidentally pasted somewhere insecure), revoke and regenerate immediately: BotFather → `/mybots` → select the bot → Bot Settings → API Token → Revoke current token

## 3. Set Up the Public Webhook (Cloudflare Quick Tunnel)

Telegram, like Meta, requires a public HTTPS endpoint for webhook delivery:

```bash
cd scripts
./cloudflared.exe tunnel --url http://localhost:5678
```

Copy the generated `https://XXXX.trycloudflare.com` URL.

**Important:** this URL changes every time the tunnel restarts. See `TROUBLESHOOTING.md` #1.

## 4. Configure n8n to Use the Tunnel URL

Unlike WhatsApp, Telegram's webhook registration is handled automatically by n8n itself — no manual dashboard configuration is needed. n8n just needs to know its own public address.

1. Add to `.env`: WEBHOOK_URL=https://cache-location-featuring-pearl.trycloudflare.com/

2. Ensure `docker-compose.yml`'s `n8n` service environment block includes:

```yaml
WEBHOOK_URL: ${WEBHOOK_URL}
TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN}
```

3. Restart n8n to apply:

```bash
docker compose up -d n8n
```

## 5. Add the Telegram Credential in n8n

1. n8n → Credentials → Add Credential → search **Telegram API**
2. Paste the bot token directly into the **Access Token** field (n8n encrypts credentials at rest)
3. Save as `Telegram - NNSEL Bot`

## 6. Add the Telegram Trigger Node

1. In the workflow, add a **Telegram Trigger** node
2. Set **Credential** to `Telegram - NNSEL Bot`
3. Set **Trigger On** to `Message`
4. Save and **Publish** the workflow

Publishing automatically registers the production webhook URL with Telegram — no manual "Verify and Save" step like Meta requires.

## 7. Verify the Webhook Registered Correctly

```bash
source .env
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

Expect a response with `"ok": true` and a `"url"` field matching your tunnel address, e.g.:

```json
{"ok":true,"result":{"url":"https://YOUR-TUNNEL-URL.trycloudflare.com/webhook/...","pending_update_count":0,...}}
```

If `"url"` is empty, the webhook did not register — re-publish the workflow and check that `WEBHOOK_URL` in `.env` is correct and the tunnel is running.

## 8. Testing During Development

Unlike WhatsApp, Telegram has **no development-mode restrictions** — any user can message the bot immediately after it's created, and there is no recipient allowlist or app-review requirement to receive real messages.

**To test the pipeline:**

1. Open `t.me/YOUR_BOT_USERNAME` in Telegram (or search the bot's username directly)
2. Send `/start`, then any message
3. Check n8n → Executions tab to confirm the message triggered a workflow run
4. Check the bot's reply arrives directly in the same Telegram chat

This tests the real, full production path every time — there is no equivalent to WhatsApp's fake-sender Test button limitation.

## 9. Moving to Production

Telegram bots are production-ready immediately upon creation — there is no equivalent to WhatsApp's App Review / Live Mode process. The only production consideration is the Cloudflare Quick Tunnel's lack of uptime guarantee and its URL changing on restart (see `LIMITATIONS.md`); for genuine production use, a persistent named tunnel or fixed public IP/domain would be recommended instead of Quick Tunnel.

## Security Notes

- Never commit the bot token to git.
- The bot token is stored only in `.env` (gitignored) and referenced via `{{ $env.TELEGRAM_BOT_TOKEN }}` where possible, or pasted directly into n8n's encrypted Credential store (not into node configuration fields).
- The exported workflow JSON has all token/credential references redacted before being committed to version control.
- If the bot token is ever exposed in chat logs, screenshots, or version control history, revoke and regenerate it immediately via BotFather.
