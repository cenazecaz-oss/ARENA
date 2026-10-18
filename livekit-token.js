// Vercel serverless function: gives a signed-in user a short-lived LiveKit ticket for one battle.
// Host and contenders can publish video/audio. Everyone else can only watch and listen.
const { AccessToken } = require('livekit-server-sdk');
const { createClient } = require('@supabase/supabase-js');

module.exports = async (req, res) => {
  try {
    const jwt = (req.headers.authorization || '').replace('Bearer ', '');
    if (!jwt) return res.status(401).json({ error: 'Not signed in' });
    const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: 'Bearer ' + jwt } }
    });
    const { data: u, error } = await sb.auth.getUser(jwt);
    if (error || !u || !u.user) return res.status(401).json({ error: 'Not signed in' });

    const battle = String(req.query.battle || '').replace(/[^a-fA-F0-9-]/g, '');
    if (!battle) return res.status(400).json({ error: 'Missing battle' });
    const { data: b } = await sb.from('battles').select('id,host_id,status').eq('id', battle).single();
    if (!b) return res.status(404).json({ error: 'Battle not found' });
    const { data: en } = await sb.from('battle_entries').select('user_id').eq('battle_id', battle).eq('user_id', u.user.id);
    const canPublish = b.host_id === u.user.id || (en && en.length > 0);

    const { data: p } = await sb.from('profiles').select('name').eq('id', u.user.id).single();
    const at = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, {
      identity: u.user.id, name: (p && p.name) || 'User', ttl: '2h'
    });
    at.addGrant({ roomJoin: true, room: 'battle-' + battle, canPublish, canSubscribe: true });
    return res.status(200).json({ token: await at.toJwt(), canPublish });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
};
