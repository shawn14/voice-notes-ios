/**
 * EEON Door Store — Pairings and Inbox
 * 
 * Uses Vercel KV (Upstash Redis) when available, falls back to in-memory for local dev.
 * 
 * Data structures:
 * - pairing:{chatId} → { eeonUserId, pairedAt }
 * - pairing_token:{token} → { eeonUserId, createdAt, expiresAt }
 * - inbox:{eeonUserId} → [ { id, thought, draft, templateId, createdAt } ]
 */

// In-memory fallback for local development (not persistent across restarts)
const memoryStore = {
  pairings: new Map(),       // chatId → { eeonUserId, pairedAt }
  tokens: new Map(),         // token → { eeonUserId, createdAt, expiresAt }
  inboxes: new Map()         // eeonUserId → [ inboxItem ]
};

// Token expiry: 5 minutes
const TOKEN_EXPIRY_MS = 5 * 60 * 1000;

// Check if Vercel KV is available
function hasKV() {
  return !!(process.env.KV_REST_API_URL && process.env.KV_REST_API_TOKEN);
}

// Lazy import for Vercel KV (only if available)
let kv = null;
async function getKV() {
  if (kv) return kv;
  if (!hasKV()) return null;
  
  try {
    const { kv: vercelKV } = await import('@vercel/kv');
    kv = vercelKV;
    return kv;
  } catch (e) {
    console.warn('[store] Vercel KV not available, using memory store');
    return null;
  }
}

// ============================================================================
// PAIRINGS
// ============================================================================

/**
 * Create a pairing token for a user.
 * Returns the token string.
 */
export async function createPairingToken(eeonUserId) {
  const token = generateToken();
  const now = Date.now();
  const data = {
    eeonUserId,
    createdAt: now,
    expiresAt: now + TOKEN_EXPIRY_MS
  };
  
  const store = await getKV();
  if (store) {
    await store.set(`pairing_token:${token}`, data, { ex: Math.ceil(TOKEN_EXPIRY_MS / 1000) });
  } else {
    memoryStore.tokens.set(token, data);
  }
  
  return token;
}

/**
 * Validate and consume a pairing token.
 * Returns { valid: true, eeonUserId } or { valid: false, reason }.
 */
export async function consumePairingToken(token) {
  const store = await getKV();
  let data;
  
  if (store) {
    data = await store.get(`pairing_token:${token}`);
    if (data) {
      await store.del(`pairing_token:${token}`);
    }
  } else {
    data = memoryStore.tokens.get(token);
    if (data) {
      memoryStore.tokens.delete(token);
    }
  }
  
  if (!data) {
    return { valid: false, reason: 'Token not found or already used' };
  }
  
  if (Date.now() > data.expiresAt) {
    return { valid: false, reason: 'Token expired' };
  }
  
  return { valid: true, eeonUserId: data.eeonUserId };
}

/**
 * Complete pairing: link a Telegram chat to an EEON user.
 */
export async function savePairing(chatId, eeonUserId) {
  const data = {
    eeonUserId,
    pairedAt: Date.now()
  };
  
  const store = await getKV();
  if (store) {
    await store.set(`pairing:${chatId}`, data);
  } else {
    memoryStore.pairings.set(String(chatId), data);
  }
}

/**
 * Get the EEON user ID for a paired chat.
 * Returns eeonUserId or null.
 */
export async function getPairing(chatId) {
  const store = await getKV();
  let data;
  
  if (store) {
    data = await store.get(`pairing:${chatId}`);
  } else {
    data = memoryStore.pairings.get(String(chatId));
  }
  
  return data?.eeonUserId || null;
}

/**
 * Check if a chat is paired.
 */
export async function isPaired(chatId) {
  return (await getPairing(chatId)) !== null;
}

/**
 * Remove pairing for a chat.
 */
export async function removePairing(chatId) {
  const store = await getKV();
  if (store) {
    await store.del(`pairing:${chatId}`);
  } else {
    memoryStore.pairings.delete(String(chatId));
  }
}

// ============================================================================
// INBOX
// ============================================================================

/**
 * Add an item to a user's inbox.
 */
export async function addToInbox(eeonUserId, item) {
  const inboxItem = {
    id: generateId(),
    ...item,
    createdAt: Date.now()
  };
  
  const store = await getKV();
  if (store) {
    const key = `inbox:${eeonUserId}`;
    const existing = (await store.get(key)) || [];
    existing.push(inboxItem);
    await store.set(key, existing);
  } else {
    const existing = memoryStore.inboxes.get(eeonUserId) || [];
    existing.push(inboxItem);
    memoryStore.inboxes.set(eeonUserId, existing);
  }
  
  return inboxItem;
}

/**
 * Get all inbox items for a user.
 */
export async function getInbox(eeonUserId) {
  const store = await getKV();
  
  if (store) {
    return (await store.get(`inbox:${eeonUserId}`)) || [];
  } else {
    return memoryStore.inboxes.get(eeonUserId) || [];
  }
}

/**
 * Acknowledge (remove) inbox items by IDs.
 */
export async function ackInboxItems(eeonUserId, itemIds) {
  const idsSet = new Set(itemIds);
  const store = await getKV();
  
  if (store) {
    const key = `inbox:${eeonUserId}`;
    const existing = (await store.get(key)) || [];
    const remaining = existing.filter(item => !idsSet.has(item.id));
    await store.set(key, remaining);
    return existing.length - remaining.length;
  } else {
    const existing = memoryStore.inboxes.get(eeonUserId) || [];
    const remaining = existing.filter(item => !idsSet.has(item.id));
    memoryStore.inboxes.set(eeonUserId, remaining);
    return existing.length - remaining.length;
  }
}

// ============================================================================
// HELPERS
// ============================================================================

function generateToken() {
  // 6-character alphanumeric token (easy to type if needed)
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed confusing chars
  let token = '';
  for (let i = 0; i < 6; i++) {
    token += chars[Math.floor(Math.random() * chars.length)];
  }
  return token;
}

function generateId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

// ============================================================================
// EXPORTS FOR TESTING
// ============================================================================

export const __testing = {
  memoryStore,
  clearMemoryStore() {
    memoryStore.pairings.clear();
    memoryStore.tokens.clear();
    memoryStore.inboxes.clear();
  }
};
