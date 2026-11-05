# Sentinel's Journal - Critical Security Learnings

## 2026-03-31 - Cross-Site Scripting (XSS) in Server-Rendered Auth Callback HTML
**Vulnerability:** In `GET /api/auth/callback`, the account holder's name (`session.user_name`) returned from external YouTube Music authentication was directly interpolated into an HTML string template rendered via FastAPI's `HTMLResponse`. If an attacker or malicious provider returned crafted HTML/JavaScript in the user name or session payload, arbitrary script execution could occur when a browser opens the callback landing page.
**Learning:** Even in API-first applications that serve SPAs (like Flutter Web), secondary landing pages, callbacks, or redirect pages implemented with server-side HTML responses might inadvertently interpolate dynamic data into HTML string templates without context-aware escaping.
**Prevention:** Always sanitize any untrusted or external data using `html.escape(value, quote=True)` prior to interpolating into `HTMLResponse` strings, or use a templating engine with auto-escaping enabled.
