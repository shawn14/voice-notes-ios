import fetch from 'node-fetch';

const TELEGRAM_API = 'https://api.telegram.org/bot';

/**
 * Send a text message to a Telegram chat.
 */
export async function sendMessage(chatId, text, replyToMessageId = null) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error('TELEGRAM_BOT_TOKEN not configured');

  const body = {
    chat_id: chatId,
    text,
    parse_mode: 'Markdown'
  };
  
  if (replyToMessageId) {
    body.reply_to_message_id = replyToMessageId;
  }

  const response = await fetch(`${TELEGRAM_API}${token}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Telegram API error: ${response.status} ${error}`);
  }

  return response.json();
}

/**
 * Download a file from Telegram servers.
 * @returns {Promise<Buffer>} File contents
 */
export async function downloadFile(fileId) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error('TELEGRAM_BOT_TOKEN not configured');

  // Get file path
  const fileResponse = await fetch(`${TELEGRAM_API}${token}/getFile?file_id=${fileId}`);
  if (!fileResponse.ok) {
    throw new Error(`Failed to get file info: ${fileResponse.status}`);
  }
  
  const fileData = await fileResponse.json();
  const filePath = fileData.result?.file_path;
  if (!filePath) {
    throw new Error('No file path in Telegram response');
  }

  // Download file
  const downloadUrl = `https://api.telegram.org/file/bot${token}/${filePath}`;
  const downloadResponse = await fetch(downloadUrl);
  if (!downloadResponse.ok) {
    throw new Error(`Failed to download file: ${downloadResponse.status}`);
  }

  const arrayBuffer = await downloadResponse.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

/**
 * Set webhook URL for the bot.
 */
export async function setWebhook(webhookUrl) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error('TELEGRAM_BOT_TOKEN not configured');

  const response = await fetch(`${TELEGRAM_API}${token}/setWebhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: webhookUrl })
  });

  return response.json();
}
