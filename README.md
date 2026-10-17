# Arena (test app)

Files:
- index.html          the whole app (front-end)
- config.js           PUBLIC settings (Supabase URL + anon key, LiveKit URL)
- api/livekit-token.js  server function that creates LiveKit call tokens
- supabase/schema.sql   database tables + coin rules (run once in Supabase)
- package.json        tells Vercel which server libraries to install
- .env.example        names of the SECRET settings you add in Vercel

With config.js left empty the app runs in DEMO mode (nothing is saved, calls are simulated).

Setup guide: see the chat answer (Steps 1 to 6). Quick order:
1. GitHub: upload this folder as a repository
2. Supabase: create project, run supabase/schema.sql, copy URL + anon key
3. LiveKit Cloud: create project, copy wss URL, API key, API secret
4. Vercel: import the repository, add the 4 environment variables from .env.example, deploy
5. Put the 3 public values in config.js, commit, Vercel redeploys
6. Supabase > Authentication > URL Configuration: add your Vercel address

Security (before real users): rewards are decided by the browser in this test (capped at 500 per call).
Move reward calculation to a server function before launch. Never put the service_role key or the LiveKit secret in config.js.
