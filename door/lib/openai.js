import fetch from 'node-fetch';
import FormData from 'form-data';

const OPENAI_API_URL = 'https://api.openai.com/v1';

/**
 * Transcribe audio using OpenAI Whisper API.
 * @param {Buffer} audioBuffer - Raw audio data
 * @param {string} filename - Original filename (for format detection)
 * @returns {Promise<string>} Transcribed text
 */
export async function transcribeAudio(audioBuffer, filename = 'audio.ogg') {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY not configured');

  const form = new FormData();
  form.append('file', audioBuffer, { filename });
  form.append('model', 'whisper-1');
  form.append('response_format', 'text');

  const response = await fetch(`${OPENAI_API_URL}/audio/transcriptions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      ...form.getHeaders()
    },
    body: form
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Whisper API error: ${response.status} ${error}`);
  }

  const text = await response.text();
  return text.trim();
}

/**
 * Rewrite text using GPT with the given system prompt.
 * @param {string} content - User's original text
 * @param {string} systemPrompt - Template system prompt
 * @returns {Promise<string>} Rewritten text
 */
export async function rewriteWithGPT(content, systemPrompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY not configured');

  const response = await fetch(`${OPENAI_API_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content }
      ],
      max_tokens: 1500,
      temperature: 0.4
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenAI API error: ${response.status} ${error}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content?.trim() || 'No response generated';
}
