/**
 * System prompts mirrored from iOS RewriteService.swift
 * These are the canonical voices — do not invent new tones.
 */

export const TEMPLATES = {
  // Default: social post (LinkedIn style, adapted for general social)
  linkedin_post: {
    id: 'linkedin_post',
    name: 'Professional Post',
    systemPrompt: `Rewrite this voice note as an engaging LinkedIn post. Start with a compelling hook line, use short paragraphs, include relevant insights or lessons, and end with a question or call-to-action. Keep it concise and professional. Add 2-3 relevant hashtags at the end.`
  },

  // Tweet/X post — short form
  tweet: {
    id: 'tweet',
    name: 'Short Post',
    systemPrompt: `Rewrite this voice note as a single short post (max 280 characters). Make it punchy, engaging, and shareable. Capture the core idea in the most compelling way possible.`
  },

  // Email format
  email: {
    id: 'email',
    name: 'Email',
    systemPrompt: `Rewrite this voice note as a professional email. Include a subject line (on its own line prefixed with 'Subject:'), appropriate greeting, well-structured body paragraphs, and a professional sign-off. Keep the tone professional but warm.`
  },

  // Bullet points
  bullets: {
    id: 'bullets',
    name: 'Bullet Points',
    systemPrompt: `Convert this voice note into a clean, organized bullet point list. Group related items under headers if appropriate. Each bullet should be concise and actionable. Preserve all key information.`
  },

  // Quick take / brief summary
  quick: {
    id: 'quick',
    name: 'Quick Take',
    systemPrompt: `Summarize this voice note in 2-3 sentences. Capture only the most essential point(s). Be extremely concise.`
  },

  // Default enhance (magic)
  enhance: {
    id: 'enhance',
    name: 'Enhance',
    systemPrompt: `Rewrite this voice note into clear, well-structured prose. Expand on ideas, remove filler words, fix grammar, and make it read professionally while preserving the original meaning, intent, and voice. Keep a natural tone.`
  }
};

// Default template for social posting
export const DEFAULT_TEMPLATE = 'linkedin_post';

/**
 * Route user command to a template.
 * Returns template id or null if no match (use default).
 */
export function routeCommand(text) {
  const lower = text.toLowerCase().trim();
  
  // Check for explicit template commands at start of message
  if (lower.startsWith('email')) return 'email';
  if (lower.startsWith('bullet') || lower.startsWith('bullets')) return 'bullets';
  if (lower.startsWith('quick')) return 'quick';
  if (lower.startsWith('tweet') || lower.startsWith('x post') || lower.startsWith('short')) return 'tweet';
  if (lower.startsWith('linkedin') || lower.startsWith('professional')) return 'linkedin_post';
  if (lower.startsWith('enhance') || lower.startsWith('improve') || lower.startsWith('polish')) return 'enhance';
  
  // No explicit command — use default
  return null;
}

/**
 * Extract content after command prefix (if any).
 * Returns original text if no command found.
 */
export function extractContent(text) {
  const lower = text.toLowerCase().trim();
  const commands = ['email', 'bullets', 'bullet', 'quick', 'tweet', 'x post', 'short', 'linkedin', 'professional', 'enhance', 'improve', 'polish'];
  
  for (const cmd of commands) {
    if (lower.startsWith(cmd)) {
      // Remove command prefix and optional colon/dash
      let content = text.slice(cmd.length).trim();
      if (content.startsWith(':') || content.startsWith('-')) {
        content = content.slice(1).trim();
      }
      return content || text; // If nothing after command, use full text
    }
  }
  
  return text;
}

/**
 * Check if message is a publish/approve request.
 */
export function isPublishRequest(text) {
  const lower = text.toLowerCase().trim();
  return lower.startsWith('post it') || 
         lower.startsWith('publish') || 
         lower.startsWith('approve') ||
         lower.startsWith('send it') ||
         lower === 'post' ||
         lower === 'publish';
}
