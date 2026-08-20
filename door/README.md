# EEON Door — Telegram Text Interface

Text a thought, get a draft back. The Stanley-shaped loop.

## For Users

Visit the landing page → tap "Message EEON" → send a text or voice note → get a polished draft.

That's it. No app to install, no account to create.

### Commands

| What you send | What you get |
|---------------|--------------|
| Any text | Professional post (LinkedIn style) |
| Voice note | Transcribed + drafted |
| `tweet: your thought` | Short post (280 chars) |
| `email: your thought` | Professional email |
| `bullets: your notes` | Bullet point list |
| `quick: your ramble` | 2-3 sentence summary |

Copy the draft, paste to post. Done.

---

## For Operators (Setup Once)

This section is for setting up the bot. Users never see this.

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot`
3. Choose a name (e.g., "EEON")
4. Choose a username (must end in `bot`, e.g., `eeon_bot`)
5. Save the token

### 2. Get Your Chat ID (for testing)

1. Message your new bot
2. Visit: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Find `chat.id` in the response

### 3. Deploy to Vercel

```bash
cd door
npm install
vercel
```

Set environment variables in Vercel Dashboard → Settings → Environment Variables:

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | From BotFather |
| `OPENAI_API_KEY` | For GPT + Whisper |
| `TELEGRAM_ALLOWED_CHAT_ID` | Your chat ID (or comma-separated list) |
| `TELEGRAM_BOT_USERNAME` | Bot username without @ (for landing page CTA) |

Deploy to production:
```bash
vercel --prod
```

### 4. Set Webhook

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-project.vercel.app/api/telegram"
```

### 5. Share the Landing Page

Give users your Vercel URL. They see:
- Clean landing page at `/`
- "Message EEON" button → opens Telegram
- QR code for mobile

They never see BotFather, tokens, or webhooks.

---

## Local Development

```bash
cp .env.example .env
# Fill in TELEGRAM_BOT_TOKEN, OPENAI_API_KEY, TELEGRAM_ALLOWED_CHAT_ID, TELEGRAM_BOT_USERNAME
npm install
npm run dev
```

Expose locally with ngrok/localtunnel for webhook testing:
```bash
npm run tunnel
# Then set webhook to the tunnel URL
```

## Tests

```bash
npm test
```

## Architecture

```
door/
├── api/
│   ├── index.js         # Landing page (consumer-facing)
│   └── telegram.js      # Webhook handler
├── lib/
│   ├── auth.js          # Chat ID guard
│   ├── openai.js        # Whisper + GPT
│   ├── telegram.js      # Telegram API
│   └── templates.js     # Prompts from iOS RewriteService
└── __tests__/
```

## What This Is NOT

- ❌ Auto-publishing to X/LinkedIn (V1 is drafts only)
- ❌ Account system or login
- ❌ Stripe/payments (free trial for now)
- ❌ Calendar, insights, earn features
