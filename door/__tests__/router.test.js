import { test, describe } from 'node:test';
import assert from 'node:assert';
import { routeCommand, extractContent, isPublishRequest, TEMPLATES, DEFAULT_TEMPLATE } from '../lib/templates.js';

describe('routeCommand', () => {
  test('routes "email" to email template', () => {
    assert.strictEqual(routeCommand('email this is my note'), 'email');
    assert.strictEqual(routeCommand('Email: formal message'), 'email');
    assert.strictEqual(routeCommand('EMAIL'), 'email');
  });

  test('routes "bullets" to bullets template', () => {
    assert.strictEqual(routeCommand('bullets: list of things'), 'bullets');
    assert.strictEqual(routeCommand('bullet points please'), 'bullets');
  });

  test('routes "quick" to quick template', () => {
    assert.strictEqual(routeCommand('quick summary needed'), 'quick');
    assert.strictEqual(routeCommand('Quick: just the gist'), 'quick');
  });

  test('routes "tweet" to tweet template', () => {
    assert.strictEqual(routeCommand('tweet this thought'), 'tweet');
    assert.strictEqual(routeCommand('x post about AI'), 'tweet');
    assert.strictEqual(routeCommand('short version'), 'tweet');
  });

  test('routes "linkedin" to linkedin_post template', () => {
    assert.strictEqual(routeCommand('linkedin style post'), 'linkedin_post');
    assert.strictEqual(routeCommand('professional post about leadership'), 'linkedin_post');
  });

  test('routes "enhance" to enhance template', () => {
    assert.strictEqual(routeCommand('enhance my rambling'), 'enhance');
    assert.strictEqual(routeCommand('improve this note'), 'enhance');
    assert.strictEqual(routeCommand('polish my draft'), 'enhance');
  });

  test('returns null for plain text (uses default)', () => {
    assert.strictEqual(routeCommand('Just a random thought about product design'), null);
    assert.strictEqual(routeCommand('I was thinking about the roadmap...'), null);
  });
});

describe('extractContent', () => {
  test('removes email prefix', () => {
    assert.strictEqual(extractContent('email: this is the content'), 'this is the content');
    assert.strictEqual(extractContent('email this is the content'), 'this is the content');
  });

  test('removes bullets prefix', () => {
    assert.strictEqual(extractContent('bullets: list of items'), 'list of items');
    assert.strictEqual(extractContent('bullet - my ideas'), 'my ideas');
  });

  test('removes quick prefix', () => {
    assert.strictEqual(extractContent('quick: summary'), 'summary');
  });

  test('removes tweet prefix', () => {
    assert.strictEqual(extractContent('tweet my hot take'), 'my hot take');
  });

  test('preserves text without command prefix', () => {
    assert.strictEqual(extractContent('This is just regular text'), 'This is just regular text');
  });

  test('handles command-only input (returns original)', () => {
    assert.strictEqual(extractContent('email'), 'email');
  });
});

describe('isPublishRequest', () => {
  test('recognizes publish commands', () => {
    assert.strictEqual(isPublishRequest('post it'), true);
    assert.strictEqual(isPublishRequest('Post it!'), true);
    assert.strictEqual(isPublishRequest('publish'), true);
    assert.strictEqual(isPublishRequest('Publish'), true);
    assert.strictEqual(isPublishRequest('approve'), true);
    assert.strictEqual(isPublishRequest('send it'), true);
    assert.strictEqual(isPublishRequest('post'), true);
  });

  test('rejects non-publish messages', () => {
    assert.strictEqual(isPublishRequest('draft a post'), false);
    assert.strictEqual(isPublishRequest('I want to post about AI'), false);
    assert.strictEqual(isPublishRequest('email my publisher'), false);
  });
});

describe('TEMPLATES', () => {
  test('has required templates', () => {
    assert.ok(TEMPLATES.linkedin_post, 'linkedin_post template exists');
    assert.ok(TEMPLATES.tweet, 'tweet template exists');
    assert.ok(TEMPLATES.email, 'email template exists');
    assert.ok(TEMPLATES.bullets, 'bullets template exists');
    assert.ok(TEMPLATES.quick, 'quick template exists');
    assert.ok(TEMPLATES.enhance, 'enhance template exists');
  });

  test('templates have required fields', () => {
    for (const [id, template] of Object.entries(TEMPLATES)) {
      assert.ok(template.id, `${id} has id`);
      assert.ok(template.name, `${id} has name`);
      assert.ok(template.systemPrompt, `${id} has systemPrompt`);
      assert.ok(template.systemPrompt.length > 50, `${id} systemPrompt is substantial`);
    }
  });

  test('default template exists', () => {
    assert.ok(TEMPLATES[DEFAULT_TEMPLATE], `default template ${DEFAULT_TEMPLATE} exists`);
  });
});
