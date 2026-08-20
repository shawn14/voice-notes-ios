import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { isAllowedChat, validateEnv } from '../lib/auth.js';

describe('isAllowedChat', () => {
  let originalEnv;

  beforeEach(() => {
    originalEnv = process.env.TELEGRAM_ALLOWED_CHAT_ID;
  });

  afterEach(() => {
    if (originalEnv !== undefined) {
      process.env.TELEGRAM_ALLOWED_CHAT_ID = originalEnv;
    } else {
      delete process.env.TELEGRAM_ALLOWED_CHAT_ID;
    }
  });

  test('rejects when TELEGRAM_ALLOWED_CHAT_ID is not set', () => {
    delete process.env.TELEGRAM_ALLOWED_CHAT_ID;
    assert.strictEqual(isAllowedChat(12345), false);
  });

  test('allows matching chat ID', () => {
    process.env.TELEGRAM_ALLOWED_CHAT_ID = '12345';
    assert.strictEqual(isAllowedChat(12345), true);
    assert.strictEqual(isAllowedChat('12345'), true);
  });

  test('rejects non-matching chat ID', () => {
    process.env.TELEGRAM_ALLOWED_CHAT_ID = '12345';
    assert.strictEqual(isAllowedChat(99999), false);
    assert.strictEqual(isAllowedChat('99999'), false);
  });

  test('allows multiple chat IDs (comma-separated)', () => {
    process.env.TELEGRAM_ALLOWED_CHAT_ID = '12345, 67890, 11111';
    assert.strictEqual(isAllowedChat(12345), true);
    assert.strictEqual(isAllowedChat(67890), true);
    assert.strictEqual(isAllowedChat(11111), true);
    assert.strictEqual(isAllowedChat(99999), false);
  });

  test('handles string and number chat IDs', () => {
    process.env.TELEGRAM_ALLOWED_CHAT_ID = '12345';
    assert.strictEqual(isAllowedChat(12345), true);
    assert.strictEqual(isAllowedChat('12345'), true);
  });
});

describe('validateEnv', () => {
  let originalEnv;

  beforeEach(() => {
    originalEnv = {
      TELEGRAM_BOT_TOKEN: process.env.TELEGRAM_BOT_TOKEN,
      OPENAI_API_KEY: process.env.OPENAI_API_KEY,
      TELEGRAM_ALLOWED_CHAT_ID: process.env.TELEGRAM_ALLOWED_CHAT_ID
    };
  });

  afterEach(() => {
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value !== undefined) {
        process.env[key] = value;
      } else {
        delete process.env[key];
      }
    }
  });

  test('returns valid when all env vars are set', () => {
    process.env.TELEGRAM_BOT_TOKEN = 'test-token';
    process.env.OPENAI_API_KEY = 'test-key';
    process.env.TELEGRAM_ALLOWED_CHAT_ID = '12345';

    const result = validateEnv();
    assert.strictEqual(result.valid, true);
    assert.deepStrictEqual(result.missing, []);
  });

  test('returns invalid with missing vars list', () => {
    delete process.env.TELEGRAM_BOT_TOKEN;
    delete process.env.OPENAI_API_KEY;
    process.env.TELEGRAM_ALLOWED_CHAT_ID = '12345';

    const result = validateEnv();
    assert.strictEqual(result.valid, false);
    assert.ok(result.missing.includes('TELEGRAM_BOT_TOKEN'));
    assert.ok(result.missing.includes('OPENAI_API_KEY'));
  });

  test('returns all missing vars when none are set', () => {
    delete process.env.TELEGRAM_BOT_TOKEN;
    delete process.env.OPENAI_API_KEY;
    delete process.env.TELEGRAM_ALLOWED_CHAT_ID;

    const result = validateEnv();
    assert.strictEqual(result.valid, false);
    assert.strictEqual(result.missing.length, 3);
  });
});
