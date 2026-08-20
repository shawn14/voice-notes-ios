import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';

describe('Landing page handler', () => {
  let originalEnv;

  beforeEach(() => {
    originalEnv = process.env.TELEGRAM_BOT_USERNAME;
  });

  afterEach(() => {
    if (originalEnv !== undefined) {
      process.env.TELEGRAM_BOT_USERNAME = originalEnv;
    } else {
      delete process.env.TELEGRAM_BOT_USERNAME;
    }
  });

  test('handler returns HTML with correct content-type', async () => {
    const { default: handler } = await import('../api/index.js');
    
    let responseHeaders = {};
    let responseBody = '';
    let responseStatus = 0;
    
    const mockRes = {
      setHeader: (key, value) => { responseHeaders[key] = value; },
      status: (code) => {
        responseStatus = code;
        return {
          send: (body) => { responseBody = body; }
        };
      }
    };
    
    handler({}, mockRes);
    
    assert.strictEqual(responseStatus, 200);
    assert.strictEqual(responseHeaders['Content-Type'], 'text/html; charset=utf-8');
    assert.ok(responseBody.includes('<!DOCTYPE html>'));
  });

  test('handler uses TELEGRAM_BOT_USERNAME env var', async () => {
    process.env.TELEGRAM_BOT_USERNAME = 'test_eeon_bot';
    
    // Re-import to pick up new env
    const handlerModule = await import('../api/index.js?v=1');
    const handler = handlerModule.default;
    
    let responseBody = '';
    const mockRes = {
      setHeader: () => {},
      status: () => ({
        send: (body) => { responseBody = body; }
      })
    };
    
    handler({}, mockRes);
    
    assert.ok(responseBody.includes('https://t.me/test_eeon_bot'));
    assert.ok(responseBody.includes('Message EEON'));
  });

  test('handler uses fallback when env not set', async () => {
    delete process.env.TELEGRAM_BOT_USERNAME;
    
    const handlerModule = await import('../api/index.js?v=2');
    const handler = handlerModule.default;
    
    let responseBody = '';
    const mockRes = {
      setHeader: () => {},
      status: () => ({
        send: (body) => { responseBody = body; }
      })
    };
    
    handler({}, mockRes);
    
    assert.ok(responseBody.includes('https://t.me/EEON_BOT_USERNAME'));
  });

  test('handler includes key landing page elements', async () => {
    const { default: handler } = await import('../api/index.js?v=3');
    
    let responseBody = '';
    const mockRes = {
      setHeader: () => {},
      status: () => ({
        send: (body) => { responseBody = body; }
      })
    };
    
    handler({}, mockRes);
    
    // Headline
    assert.ok(responseBody.includes('One conversation'));
    assert.ok(responseBody.includes('Draft back'));
    
    // CTA button
    assert.ok(responseBody.includes('Message EEON'));
    
    // How it works steps
    assert.ok(responseBody.includes('Get a draft'));
    assert.ok(responseBody.includes('Copy &amp; post') || responseBody.includes('Copy & post'));
    
    // QR code
    assert.ok(responseBody.includes('qrserver.com'));
    
    // Footer / honest copy
    assert.ok(responseBody.includes('Drafts only') || responseBody.includes('drafts only'));
    assert.ok(responseBody.includes('Free to try'));
  });
});
