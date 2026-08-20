/**
 * Simple auth guard — only respond to allowed chat IDs.
 * TELEGRAM_ALLOWED_CHAT_ID can be a single ID or comma-separated list.
 */

export function isAllowedChat(chatId) {
  const allowedRaw = process.env.TELEGRAM_ALLOWED_CHAT_ID;
  
  if (!allowedRaw) {
    console.warn('[auth] TELEGRAM_ALLOWED_CHAT_ID not set — rejecting all');
    return false;
  }
  
  const allowedIds = allowedRaw.split(',').map(id => id.trim());
  const chatIdStr = String(chatId);
  
  return allowedIds.includes(chatIdStr);
}

/**
 * Validate required environment variables.
 * Returns { valid: boolean, missing: string[] }
 */
export function validateEnv() {
  const required = ['TELEGRAM_BOT_TOKEN', 'OPENAI_API_KEY', 'TELEGRAM_ALLOWED_CHAT_ID'];
  const missing = required.filter(key => !process.env[key]);
  
  return {
    valid: missing.length === 0,
    missing
  };
}
