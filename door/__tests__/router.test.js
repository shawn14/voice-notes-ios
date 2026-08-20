import { test, describe } from 'node:test';
import assert from 'node:assert';
import { routeCommand, extractContent, isPublishRequest, isGreeting, isTooThin, HELP_MESSAGE, TEMPLATES, DEFAULT_TEMPLATE } from '../lib/templates.js';

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

describe('isGreeting', () => {
  test('recognizes common greetings', () => {
    assert.strictEqual(isGreeting('hello'), true);
    assert.strictEqual(isGreeting('Hello'), true);
    assert.strictEqual(isGreeting('hi'), true);
    assert.strictEqual(isGreeting('hey'), true);
    assert.strictEqual(isGreeting('yo'), true);
    assert.strictEqual(isGreeting('hola'), true);
  });

  test('recognizes bot commands', () => {
    assert.strictEqual(isGreeting('/start'), true);
    assert.strictEqual(isGreeting('/help'), true);
    assert.strictEqual(isGreeting('/stop'), true);
    assert.strictEqual(isGreeting('/anything'), true);
  });

  test('recognizes thanks and acknowledgments', () => {
    assert.strictEqual(isGreeting('thanks'), true);
    assert.strictEqual(isGreeting('thank you'), true);
    assert.strictEqual(isGreeting('ok'), true);
    assert.strictEqual(isGreeting('okay'), true);
    assert.strictEqual(isGreeting('cool'), true);
    assert.strictEqual(isGreeting('nice'), true);
  });

  test('recognizes test messages', () => {
    assert.strictEqual(isGreeting('test'), true);
    assert.strictEqual(isGreeting('testing'), true);
    assert.strictEqual(isGreeting('hello world'), true);
  });

  test('rejects real content', () => {
    assert.strictEqual(isGreeting('Building in public is underrated'), false);
    assert.strictEqual(isGreeting('I just shipped a new feature'), false);
    assert.strictEqual(isGreeting('hello world this is my thought about startups'), false);
  });
});

describe('isTooThin', () => {
  test('rejects messages under 6 words without command', () => {
    assert.strictEqual(isTooThin('hello'), true);
    assert.strictEqual(isTooThin('this is short'), true);
    assert.strictEqual(isTooThin('only five words here now'), true);
  });

  test('accepts messages with 6+ words', () => {
    assert.strictEqual(isTooThin('this message has exactly six words'), false);
    assert.strictEqual(isTooThin('Building in public taught me something important'), false);
    assert.strictEqual(isTooThin('I shipped three features this week and got user feedback'), false);
  });

  test('accepts short messages with explicit command', () => {
    assert.strictEqual(isTooThin('tweet: my take'), false);
    assert.strictEqual(isTooThin('email: follow up'), false);
    assert.strictEqual(isTooThin('bullets: ideas'), false);
    assert.strictEqual(isTooThin('quick: summary'), false);
    assert.strictEqual(isTooThin('enhance: draft'), false);
  });

  test('handles edge cases', () => {
    assert.strictEqual(isTooThin(''), true);
    assert.strictEqual(isTooThin('   '), true);
    assert.strictEqual(isTooThin('word'), true);
  });
});

describe('HELP_MESSAGE', () => {
  test('exists and contains guidance', () => {
    assert.ok(HELP_MESSAGE, 'HELP_MESSAGE is defined');
    assert.ok(HELP_MESSAGE.includes('real thought'), 'mentions real thought');
    assert.ok(HELP_MESSAGE.includes('voice note') || HELP_MESSAGE.includes('sentences'), 'mentions input types');
  });
});
