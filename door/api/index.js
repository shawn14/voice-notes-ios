/**
 * EEON Door — Landing Page
 * 
 * Consumer-facing on-ramp: one CTA to message the bot.
 * No BotFather, no tokens, no developer setup.
 */

export default function handler(req, res) {
  const botUsername = process.env.TELEGRAM_BOT_USERNAME || 'heyeeon_bot';
  const telegramUrl = `https://t.me/${botUsername}`;
  
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>EEON Door — Text a thought, get a draft</title>
  <meta name="description" content="Send a voice note or text. Get a polished draft back. No app needed.">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    :root {
      --bg: #0a0a0b;
      --surface: #141416;
      --border: #27272a;
      --text: #fafafa;
      --text-muted: #a1a1aa;
      --accent: #3b82f6;
      --accent-hover: #2563eb;
    }
    
    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
      line-height: 1.6;
    }
    
    .container {
      max-width: 480px;
      width: 100%;
      text-align: center;
    }
    
    .logo {
      font-size: 48px;
      margin-bottom: 32px;
    }
    
    h1 {
      font-size: 2.5rem;
      font-weight: 700;
      margin-bottom: 16px;
      letter-spacing: -0.02em;
      line-height: 1.2;
    }
    
    .tagline {
      font-size: 1.25rem;
      color: var(--text-muted);
      margin-bottom: 40px;
    }
    
    .how-it-works {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 32px;
      margin-bottom: 32px;
      text-align: left;
    }
    
    .step {
      display: flex;
      align-items: flex-start;
      gap: 16px;
      margin-bottom: 20px;
    }
    
    .step:last-child {
      margin-bottom: 0;
    }
    
    .step-number {
      background: var(--accent);
      color: white;
      width: 28px;
      height: 28px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      font-weight: 600;
      flex-shrink: 0;
    }
    
    .step-content h3 {
      font-size: 1rem;
      font-weight: 600;
      margin-bottom: 4px;
    }
    
    .step-content p {
      font-size: 0.9rem;
      color: var(--text-muted);
    }
    
    .cta-button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 12px;
      background: var(--accent);
      color: white;
      font-size: 1.125rem;
      font-weight: 600;
      padding: 18px 40px;
      border-radius: 12px;
      text-decoration: none;
      transition: background 0.2s, transform 0.2s;
      margin-bottom: 24px;
    }
    
    .cta-button:hover {
      background: var(--accent-hover);
      transform: translateY(-2px);
    }
    
    .cta-button svg {
      width: 24px;
      height: 24px;
    }
    
    .qr-section {
      margin-bottom: 40px;
    }
    
    .qr-label {
      font-size: 0.875rem;
      color: var(--text-muted);
      margin-bottom: 12px;
    }
    
    .qr-code {
      background: white;
      padding: 16px;
      border-radius: 12px;
      display: inline-block;
    }
    
    .qr-code img {
      display: block;
      width: 140px;
      height: 140px;
    }
    
    .footer {
      color: var(--text-muted);
      font-size: 0.875rem;
    }
    
    .footer p {
      margin-bottom: 8px;
    }
    
    .footer-note {
      font-size: 0.8rem;
      opacity: 0.7;
    }
    
    @media (max-width: 480px) {
      h1 {
        font-size: 2rem;
      }
      
      .tagline {
        font-size: 1.1rem;
      }
      
      .how-it-works {
        padding: 24px;
      }
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="logo">✨</div>
    
    <h1>One conversation.<br>Draft back.</h1>
    
    <p class="tagline">Text a thought or send a voice note. Get a polished post ready to share.</p>
    
    <div class="how-it-works">
      <div class="step">
        <div class="step-number">1</div>
        <div class="step-content">
          <h3>Message EEON</h3>
          <p>Send a text or voice note — brain dump welcome.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-number">2</div>
        <div class="step-content">
          <h3>Get a draft</h3>
          <p>AI rewrites it into a polished post in seconds.</p>
        </div>
      </div>
      <div class="step">
        <div class="step-number">3</div>
        <div class="step-content">
          <h3>Copy & post</h3>
          <p>Paste to LinkedIn, X, or wherever you share.</p>
        </div>
      </div>
    </div>
    
    <a href="${telegramUrl}" class="cta-button" target="_blank" rel="noopener">
      <svg viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm4.64 6.8c-.15 1.58-.8 5.42-1.13 7.19-.14.75-.42 1-.68 1.03-.58.05-1.02-.38-1.58-.75-.88-.58-1.38-.94-2.23-1.5-.99-.65-.35-1.01.22-1.59.15-.15 2.71-2.48 2.76-2.69a.2.2 0 00-.05-.18c-.06-.05-.14-.03-.21-.02-.09.02-1.49.95-4.22 2.79-.4.27-.76.41-1.08.4-.36-.01-1.04-.2-1.55-.37-.63-.2-1.12-.31-1.08-.66.02-.18.27-.36.74-.55 2.92-1.27 4.86-2.11 5.83-2.51 2.78-1.16 3.35-1.36 3.73-1.36.08 0 .27.02.39.12.1.08.13.19.14.27-.01.06.01.24 0 .37z"/>
      </svg>
      Message EEON
    </a>
    
    <div class="qr-section">
      <p class="qr-label">or scan to open Telegram</p>
      <div class="qr-code">
        <img src="https://api.qrserver.com/v1/create-qr-code/?size=140x140&data=${encodeURIComponent(telegramUrl)}" alt="QR code to message EEON">
      </div>
    </div>
    
    <footer class="footer">
      <p>Free to try. Drafts only — you copy & paste to post.</p>
      <p class="footer-note">EEON processes your message with AI. No account needed.</p>
    </footer>
  </div>
</body>
</html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.status(200).send(html);
}
