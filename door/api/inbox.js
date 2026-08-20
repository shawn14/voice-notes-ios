/**
 * EEON Door — Inbox API
 * 
 * GET /api/inbox?userId={eeonUserId}
 *   Returns: { items: [ { id, thought, draft, templateId, createdAt } ] }
 *   
 * POST /api/inbox?action=ack
 *   Body: { eeonUserId, itemIds: [...] }
 *   Returns: { acknowledged: n }
 */

import { getInbox, ackInboxItems } from '../lib/store.js';

export default async function handler(req, res) {
  // CORS for iOS app
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  try {
    if (req.method === 'GET') {
      const { userId } = req.query;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId query param required' });
      }
      
      const items = await getInbox(userId);
      
      return res.status(200).json({ items });
    }
    
    if (req.method === 'POST') {
      const action = req.query.action;
      
      if (action === 'ack') {
        const { eeonUserId, itemIds } = req.body || {};
        
        if (!eeonUserId || !itemIds || !Array.isArray(itemIds)) {
          return res.status(400).json({ error: 'eeonUserId and itemIds[] required' });
        }
        
        const count = await ackInboxItems(eeonUserId, itemIds);
        
        return res.status(200).json({ acknowledged: count });
      }
      
      return res.status(400).json({ error: 'Invalid action. Use: ack' });
    }
    
    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    console.error('[inbox] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}
