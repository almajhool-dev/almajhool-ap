// اختبار حقيقي لقناة الإشارة (Realtime Broadcast) على خادم التطبيق نفسه
import { createClient } from '@supabase/supabase-js';
const URL = 'https://smjkxsqvdpywumghvnfv.supabase.co';
const KEY = 'sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV';
const room = 'call-room-selftest-' + Date.now();
const a = createClient(URL, KEY), b = createClient(URL, KEY);
const got = { offer: 0, ice: 0, answer: 0, offerSize: 0 };
const join = (client, setup) => new Promise((res, rej) => {
  const ch = setup(client.channel(room));
  ch.subscribe((s, e) => { console.log('status', s, e?.message || ''); if (s === 'SUBSCRIBED') res(ch); if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT') rej(new Error(s)); });
});
const chB = await join(b, ch => ch
  .on('broadcast', { event: 'offer' }, m => { got.offer++; got.offerSize = JSON.stringify(m.payload).length; })
  .on('broadcast', { event: 'ice' }, () => got.ice++));
const chA = await join(a, ch => ch.on('broadcast', { event: 'answer' }, () => got.answer++));
const sdp = 'a=candidate:' + 'x'.repeat(6000);
console.log('send offer', await chA.send({ type: 'broadcast', event: 'offer', payload: { sdp, type: 'offer' } }));
for (let i = 0; i < 15; i++) console.log('ice', i, await chA.send({ type: 'broadcast', event: 'ice', payload: { candidate: 'c' + i } }));
console.log('send answer', await chB.send({ type: 'broadcast', event: 'answer', payload: { sdp: 'y'.repeat(4000), type: 'answer' } }));
await new Promise(r => setTimeout(r, 4000));
console.log('RESULT', JSON.stringify(got));
process.exit(0);
