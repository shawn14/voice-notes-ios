import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  createPairingToken,
  consumePairingToken,
  savePairing,
  getPairing,
  isPaired,
  removePairing,
  addToInbox,
  getInbox,
  ackInboxItems,
  __testing
} from '../lib/store.js';

describe('Pairing tokens', () => {
  beforeEach(() => {
    __testing.clearMemoryStore();
  });

  test('createPairingToken generates a 6-char token', async () => {
    const token = await createPairingToken('user-123');
    assert.ok(token, 'token is generated');
    assert.strictEqual(token.length, 6, 'token is 6 characters');
    assert.ok(/^[A-Z0-9]+$/.test(token), 'token is alphanumeric uppercase');
  });

  test('consumePairingToken validates and returns user ID', async () => {
    const token = await createPairingToken('user-abc');
    
    const result = await consumePairingToken(token);
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.eeonUserId, 'user-abc');
  });

  test('consumePairingToken fails on second use', async () => {
    const token = await createPairingToken('user-xyz');
    
    // First use succeeds
    const first = await consumePairingToken(token);
    assert.strictEqual(first.valid, true);
    
    // Second use fails
    const second = await consumePairingToken(token);
    assert.strictEqual(second.valid, false);
    assert.ok(second.reason.includes('not found'));
  });

  test('consumePairingToken fails for unknown token', async () => {
    const result = await consumePairingToken('NOTREAL');
    assert.strictEqual(result.valid, false);
  });
});

describe('Pairings', () => {
  beforeEach(() => {
    __testing.clearMemoryStore();
  });

  test('savePairing and getPairing work together', async () => {
    await savePairing(12345, 'user-paired');
    
    const userId = await getPairing(12345);
    assert.strictEqual(userId, 'user-paired');
  });

  test('isPaired returns true for paired chats', async () => {
    await savePairing(99999, 'user-test');
    
    assert.strictEqual(await isPaired(99999), true);
    assert.strictEqual(await isPaired(88888), false);
  });

  test('getPairing returns null for unpaired chats', async () => {
    const userId = await getPairing(11111);
    assert.strictEqual(userId, null);
  });

  test('removePairing removes the pairing', async () => {
    await savePairing(55555, 'user-temp');
    assert.strictEqual(await isPaired(55555), true);
    
    await removePairing(55555);
    assert.strictEqual(await isPaired(55555), false);
  });
});

describe('Inbox', () => {
  beforeEach(() => {
    __testing.clearMemoryStore();
  });

  test('addToInbox creates items with IDs', async () => {
    const item = await addToInbox('user-inbox', {
      thought: 'Building in public is great',
      draft: 'Building in public unlocks...',
      templateId: 'linkedin_post'
    });
    
    assert.ok(item.id, 'item has an ID');
    assert.strictEqual(item.thought, 'Building in public is great');
    assert.strictEqual(item.draft, 'Building in public unlocks...');
    assert.ok(item.createdAt, 'item has createdAt');
  });

  test('getInbox returns all items for a user', async () => {
    await addToInbox('user-multi', { thought: 'First', draft: 'Draft 1' });
    await addToInbox('user-multi', { thought: 'Second', draft: 'Draft 2' });
    
    const items = await getInbox('user-multi');
    assert.strictEqual(items.length, 2);
  });

  test('getInbox returns empty array for unknown user', async () => {
    const items = await getInbox('user-nonexistent');
    assert.deepStrictEqual(items, []);
  });

  test('ackInboxItems removes acknowledged items', async () => {
    const item1 = await addToInbox('user-ack', { thought: 'A' });
    const item2 = await addToInbox('user-ack', { thought: 'B' });
    const item3 = await addToInbox('user-ack', { thought: 'C' });
    
    const count = await ackInboxItems('user-ack', [item1.id, item3.id]);
    assert.strictEqual(count, 2);
    
    const remaining = await getInbox('user-ack');
    assert.strictEqual(remaining.length, 1);
    assert.strictEqual(remaining[0].thought, 'B');
  });
});

describe('Auth: paired vs unpaired', () => {
  beforeEach(() => {
    __testing.clearMemoryStore();
  });

  test('unpaired chat is not authorized by pairing', async () => {
    const userId = await getPairing(77777);
    assert.strictEqual(userId, null);
  });

  test('paired chat is authorized', async () => {
    await savePairing(66666, 'user-auth');
    
    const userId = await getPairing(66666);
    assert.strictEqual(userId, 'user-auth');
  });
});
