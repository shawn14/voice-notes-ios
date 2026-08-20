/**
 * EEON Door — Telegram Webhook Handler
 * 
 * Receives text/voice messages from Telegram, rewrites them into social posts
 * using the same templates as the iOS app's RewriteService.
 * 
 * Stanley-shaped loop: chat in → draft out.
 */

import { isAllowedChat, validateEnv } from '../lib/auth.js';
import { TEMPLATES, DEFAULT_TEMPLATE, routeCommand, extractContent, isPublishRequest, isGreeting, isTooThin, HELP_MESSAGE } from '../lib/templates.js';
import { rewriteWithGPT, transcribeAudio } from '../lib/openai.js';
import { sendMessage, downloadFile } from '../lib/telegram.js';

/**
 * Main webhook handler — Vercel serverless function format.
 */
export default async function handler(req, res) {
  // Only accept POST
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Validate environment
  const envCheck = validateEnv();
  if (!envCheck.valid) {
    console.error('[webhook] Missing env vars:', envCheck.missing);
    return res.status(500).json({ error: 'Server misconfigured' });
  }

  try {
    const update = req.body;
    await handleUpdate(update);
    return res.status(200).json({ ok: true });
  } catch (error) {
    console.error('[webhook] Error:', error);
    return res.status(200).json({ ok: true }); // Always 200 to Telegram
  }
}

/**
 * Process a Telegram update.
 */
export async function handleUpdate(update) {
  const message = update.message;
  if (!message) {
    console.log('[webhook] No message in update, ignoring');
    return;
  }

  const chatId = message.chat?.id;
  const messageId = message.message_id;

  // Auth check — only respond to allowed chats
  if (!isAllowedChat(chatId)) {
    console.log(`[webhook] Ignoring message from unauthorized chat: ${chatId}`);
    return; // Silent ignore
  }

  // Determine content type and extract text
  let content = '';
  let isVoice = false;

  if (message.voice || message.audio) {
    // Voice note or audio file — transcribe with Whisper
    isVoice = true;
    const fileId = message.voice?.file_id || message.audio?.file_id;
    const filename = message.audio?.file_name || 'voice.ogg';
    
    try {
      console.log(`[webhook] Downloading voice/audio file: ${fileId}`);
      const audioBuffer = await downloadFile(fileId);
      
      console.log(`[webhook] Transcribing ${audioBuffer.length} bytes`);
      content = await transcribeAudio(audioBuffer, filename);
      console.log(`[webhook] Transcribed: "${content.slice(0, 100)}..."`);
    } catch (error) {
      console.error('[webhook] Transcription failed:', error);
      await sendMessage(chatId, '❌ Failed to transcribe voice note. Please try again.', messageId);
      return;
    }
  } else if (message.text) {
    content = message.text;
  } else {
    // Unsupported message type
    console.log('[webhook] Unsupported message type, ignoring');
    return;
  }

  if (!content.trim()) {
    return;
  }

  // Check for publish/approve request
  if (isPublishRequest(content)) {
    await sendMessage(
      chatId,
      '🚧 *Publish not wired yet*\n\nV1 drafts only — copy & paste to post. Publishing will be added in a future update.',
      messageId
    );
    return;
  }

  // Check for greetings / too-thin content (don't waste GPT on "hello")
  if (isGreeting(content) || isTooThin(content)) {
    console.log(`[webhook] Greeting or too-thin content, sending help: "${content.slice(0, 50)}"`);
    await sendMessage(chatId, HELP_MESSAGE, messageId);
    return;
  }

  // Route to template
  const templateId = routeCommand(content) || DEFAULT_TEMPLATE;
  const template = TEMPLATES[templateId];
  
  if (!template) {
    console.error(`[webhook] Unknown template: ${templateId}`);
    await sendMessage(chatId, '❌ Unknown template. Try: email, bullets, quick, tweet, linkedin', messageId);
    return;
  }

  // Extract actual content (remove command prefix if present)
  const textToRewrite = isVoice ? content : extractContent(content);

  // Generate draft
  try {
    console.log(`[webhook] Rewriting with template: ${template.name}`);
    const draft = await rewriteWithGPT(textToRewrite, template.systemPrompt);
    
    // Format response
    const response = `✨ *${template.name}*\n\n${draft}`;
    await sendMessage(chatId, response, messageId);
    
    console.log(`[webhook] Sent draft (${template.name}) to chat ${chatId}`);
  } catch (error) {
    console.error('[webhook] Rewrite failed:', error);
    await sendMessage(chatId, '❌ Failed to generate draft. Please try again.', messageId);
  }
}

// For local development — run as HTTP server
if (process.argv[1]?.endsWith('telegram.js') && !process.env.VERCEL) {
  const http = await import('http');
  
  const server = http.createServer(async (req, res) => {
    if (req.method === 'POST' && req.url === '/api/telegram') {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', async () => {
        try {
          const json = JSON.parse(body);
          await handleUpdate(json);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
        } catch (e) {
          console.error('[dev] Error:', e);
          res.writeHead(500);
          res.end(JSON.stringify({ error: e.message }));
        }
      });
    } else {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('EEON Door - Telegram Webhook\n\nPOST /api/telegram to handle updates.');
    }
  });
  
  const PORT = process.env.PORT || 3000;
  server.listen(PORT, () => {
    console.log(`[dev] EEON Door listening on http://localhost:${PORT}`);
    console.log('[dev] Webhook endpoint: POST /api/telegram');
  });
}
