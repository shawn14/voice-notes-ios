# EEON Door — Telegram Text Interface

Text a thought, get a draft back. The Stanley-shaped loop.

**This is not a separate product.** It's a Telegram door into EEON — the same user, both doors, shared drafts.

## For Users

1. Open EEON app → Settings → tap **Message EEON**
2. This opens Telegram with your account linked
3. Send a text or voice note
4. Get a polished draft back
5. The note syncs to your EEON app automatically

Copy the draft, paste to post. Done.

### Commands

| What you send | What you get |
|---------------|--------------|
| Any text | Professional post (LinkedIn style) |
| Voice note | Transcribed + drafted |
| `tweet: your thought` | Short post (280 chars) |
| `email: your thought` | Professional email |
| `bullets: your notes` | Bullet point list |
| `quick: your ramble` | 2-3 sentence summary |

---

## Architecture

### How Pairing Works

1. User taps "Message EEON" in iOS app
2. App calls `/api/pair?action=request` with Apple user ID
3. Door generates a 6-character token (expires in 5 min)
4. App opens `t.me/heyeeon_bot?start={token}`
5. Bot receives `/start {token}`, validates, saves pairing
6. User can now send messages

### How Drafts Sync

1. User sends text/voice to bot
2. Bot transcribes (if voice) and rewrites with template
3. Draft + original thought stored in user's inbox
4. iOS app polls `/api/inbox` on foreground
5. Items converted to Notes with `sourceType: .telegram`
6. Items acknowledged and removed from inbox

### Auth Model

- **Paired users**: Linked via the iOS app pairing flow
- **Operator allowlist**: `TELEGRAM_ALLOWED_CHAT_ID` as fallback
- **Unpaired users**: Get a "connect from app" message

---

## For Operators (Setup Once)

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot`
3. Choose a name (e.g., "EEON")
4. Choose a username (e.g., `heyeeon_bot`)
5. Save the token

### 2. Deploy to Vercel

```bash
cd door
npm install
vercel
```

Set environment variables in Vercel Dashboard:

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | From BotFather |
| `OPENAI_API_KEY` | For GPT + Whisper |
| `TELEGRAM_ALLOWED_CHAT_ID` | Operator fallback (optional) |
| `TELEGRAM_BOT_USERNAME` | Bot username for landing page |

Link Vercel KV for persistent storage:
```bash
vercel env pull
vercel link
# In Vercel Dashboard: Storage → Create KV → Link to project
```

Deploy to production:
```bash
vercel --prod
```

### 3. Set Webhook

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-project.vercel.app/api/telegram"
```

### 4. Update iOS App

Set the `doorBaseURL` in `TelegramService.swift` to your Vercel deployment URL.

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Landing page with "Message EEON" button |
| `/api/telegram` | POST | Telegram webhook |
| `/api/pair?action=request` | POST | Generate pairing token |
| `/api/inbox` | GET | Fetch user's inbox items |
| `/api/inbox?action=ack` | POST | Acknowledge synced items |

## Local Development

```bash
cp .env.example .env
# Fill in variables
npm install
npm run dev
```

Expose locally with ngrok/localtunnel for webhook testing:
```bash
npm run tunnel
# Set webhook to tunnel URL
```

## Tests

```bash
npm test
```

54 tests covering:
- Template routing
- Greeting/thin-content guard
- Pairing tokens
- Inbox sync
- Auth (paired vs unpaired)

## Files

```
door/
├── api/
│   ├── index.js         # Landing page
│   ├── telegram.js      # Webhook handler
│   ├── pair.js          # Pairing API
│   └── inbox.js         # Inbox API
├── lib/
│   ├── auth.js          # Chat ID guard
│   ├── openai.js        # Whisper + GPT
│   ├── store.js         # Vercel KV / memory store
│   ├── telegram.js      # Telegram API
│   └── templates.js     # Prompts from iOS RewriteService
└── __tests__/
```

## What This Is NOT

- ❌ Auto-publishing to X/LinkedIn (V1 is drafts only)
- ❌ A separate account system (uses Sign in with Apple via iOS)
- ❌ Stripe/payments
- ❌ Calendar, insights, earn features
