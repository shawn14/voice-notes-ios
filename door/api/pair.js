/**
 * EEON Door — Pairing API
 * 
 * POST /api/pair?action=request
 *   Body: { eeonUserId }
 *   Returns: { token, telegramUrl }
 *   
 * POST /api/pair?action=status  
 *   Body: { eeonUserId }
 *   Returns: { paired, chatId? }
 */

import { createPairingToken, getPairing } from '../lib/store.js';

const BOT_USERNAME = process.env.TELEGRAM_BOT_USERNAME || 'heyeeon_bot';

export default async function handler(req, res) {
  // CORS for iOS app
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  
  const action = req.query.action;
  const { eeonUserId } = req.body || {};
  
  if (!eeonUserId) {
    return res.status(400).json({ error: 'eeonUserId required' });
  }
  
  try {
    switch (action) {
      case 'request': {
        // Generate pairing token
        const token = await createPairingToken(eeonUserId);
        const telegramUrl = `https://t.me/${BOT_USERNAME}?start=${token}`;
        
        console.log(`[pair] Created token ${token} for user ${eeonUserId.slice(0, 8)}...`);
        
        return res.status(200).json({
          token,
          telegramUrl,
          expiresInSeconds: 300
        });
      }
      
      case 'status': {
        // Check if user has any paired chats
        // Note: This is a simple check; in production you might want user→chat mapping
        return res.status(200).json({
          paired: false, // Can't easily reverse-lookup without additional index
          message: 'Use /api/inbox to check for messages'
        });
      }
      
      default:
        return res.status(400).json({ error: 'Invalid action. Use: request, status' });
    }
  } catch (error) {
    console.error('[pair] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
