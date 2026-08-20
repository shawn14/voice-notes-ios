# EEON Door — Telegram Text Interface

A thin messaging front door for EEON: text a thought, get a draft back. This is the Stanley-shaped loop (chat in, draft out).

**This is not a separate product.** It's a Telegram interface to the same RewriteService templates from the EEON iOS app.

## What It Does

1. Send a text or voice note to the Telegram bot
2. Bot transcribes (if voice) and rewrites into a social post using EEON's templates
3. You get a draft back in the same chat
4. Copy & paste to post (V1 does not auto-publish)

## Quick Start

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot`
3. Choose a name (e.g., "EEON Draft")
4. Choose a username (must end in `bot`, e.g., `eeon_draft_bot`)
5. Save the token BotFather gives you

### 2. Get Your Chat ID

1. Message your new bot (any message)
2. Visit: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Find your `chat.id` in the response — it's usually a number like `123456789`

### 3. Set Environment Variables

```bash
cp .env.example .env
# Edit .env with your values:
# TELEGRAM_BOT_TOKEN=<from BotFather>
# OPENAI_API_KEY=<your OpenAI key>
# TELEGRAM_ALLOWED_CHAT_ID=<your chat ID>
```

### 4. Run Locally

```bash
cd door
npm install
npm run dev
```

The server runs on `http://localhost:3000`. To test with Telegram, you need a public URL.

### 5. Expose to Telegram (Local Testing)

Use localtunnel or ngrok:

```bash
# Option A: localtunnel (included in devDependencies)
npm run tunnel
# Copy the https URL it gives you

# Option B: ngrok
ngrok http 3000
# Copy the https URL
```

### 6. Set Webhook

```bash
curl "https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook?url=<YOUR_PUBLIC_URL>/api/telegram"
```

You should see `{"ok":true,"result":true,"description":"Webhook was set"}`.

## Deploy to Vercel

```bash
# From the door/ directory
npm install -g vercel
vercel

# Set environment variables in Vercel dashboard or CLI:
vercel env add TELEGRAM_BOT_TOKEN
vercel env add OPENAI_API_KEY
vercel env add TELEGRAM_ALLOWED_CHAT_ID

# Deploy to production
vercel --prod
```

Then set the webhook to your Vercel URL:
```bash
curl "https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook?url=https://your-project.vercel.app/api/telegram"
```

## Usage

### Default: Social Post
Just send any text — bot replies with a LinkedIn-style professional post.

```
> Building in public is underrated. Shipped 3 features this week and got real user feedback each time.

✨ Professional Post

Building in public isn't just a trend—it's a superpower.

This week, I shipped 3 features and got immediate user feedback on each one. The iteration speed is unreal when you close the loop with real humans.

Stop building in the dark. Your users want to see the journey.

What did you ship this week? 👇

#buildinpublic #startups #productdevelopment
```

### Commands

| Command | Template | Example |
|---------|----------|---------|
| (default) | Professional Post | "My thought here" |
| `tweet` | Short Post (280 chars) | "tweet: my hot take" |
| `email` | Professional Email | "email: follow up with client" |
| `bullets` | Bullet Points | "bullets: meeting notes" |
| `quick` | 2-3 Sentence Summary | "quick: summarize this ramble" |
| `enhance` | Clean Prose | "enhance: my rough draft" |

### Voice Notes
Send a voice message — bot transcribes via Whisper, then rewrites with the default template.

### Publish Request
Saying "post it" or "publish" returns a message that publish is not wired yet. V1 is drafts only.

## Tests

```bash
npm test
```

## Security

- Only responds to `TELEGRAM_ALLOWED_CHAT_ID` — all other chats are silently ignored
- No data stored — stateless request/response
- API keys never leave the server

## Files

```
door/
├── api/
│   └── telegram.js      # Vercel serverless handler
├── lib/
│   ├── auth.js          # Chat ID guard
│   ├── openai.js        # Whisper + GPT calls
│   ├── telegram.js      # Telegram API helpers
│   └── templates.js     # System prompts from iOS RewriteService
├── __tests__/
│   ├── auth.test.js     # Auth guard tests
│   └── router.test.js   # Template routing tests
├── .env.example
├── package.json
├── vercel.json
└── README.md
```

## Template Prompts

The system prompts mirror those in `voice notes/RewriteService.swift` from the iOS app. They're the same voice — this is just a different door into the same drafting engine.
