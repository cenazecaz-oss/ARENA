// Vercel serverless function: gives a signed-in user a short-lived LiveKit token.
// The LiveKit secret stays here on the server and is never sent to the browser.
const { AccessToken } = require('livekit-server-sdk');
const { createClient } = require('@supabase/supabase-js');

module.exports = async (req, res) => {
  try {
    const jwt = (req.headers.authorization || '').replace('Bearer ', '');
    if (!jwt) return res.status(401).json({ error: 'Not signed in' });

    const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
    const { data, error } = await sb.auth.getUser(jwt);
    if (error || !data || !data.user) return res.status(401).json({ error: 'Not signed in' });

    const room = String(req.query.room || '').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 60);
    if (!room) return res.status(400).json({ error: 'Missing room' });

    const at = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, {
      identity: data.user.id,
      name: String(req.query.name || 'User').slice(0, 40),
      ttl: '1h'
    });
    at.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true });
    return res.status(200).json({ token: await at.toJwt() });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
};
