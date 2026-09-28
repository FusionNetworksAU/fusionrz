const hud = document.getElementById('hud');
const $ = id => document.getElementById(id);
const labels = { running: 'LIVE', countdown: 'GET READY', intermission: 'NEXT ROUND' };
window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'show') {
        hud.classList.remove('hidden');
        $('arena').textContent = data.arena || 'RAMPS ARENA';
        $('mode').textContent = data.mode || '1V1';
        $('result').textContent = '';
        $('blue').textContent = '0';
        $('red').textContent = '0';
        $('round').textContent = 'ROUND 1';
        $('status').textContent = 'GET READY';
        $('timer').textContent = '0:00';
    }
    if (data.action === 'state') {
        hud.classList.remove('hidden');
        $('round').textContent = `ROUND ${data.round || 1} · FIRST TO 3`;
        $('status').textContent = labels[data.status] || 'READY';
        $('blue').textContent = data.scores?.[0] ?? 0;
        $('red').textContent = data.scores?.[1] ?? 0;
        const seconds = Math.max(0, Number(data.time) || 0);
        $('timer').textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
    }
    if (data.action === 'finish') {
        $('blue').textContent = data.scores?.[0] ?? 0;
        $('red').textContent = data.scores?.[1] ?? 0;
        $('status').textContent = 'FINISHED';
        $('timer').textContent = '0:00';
        $('result').textContent = data.winner === 1 ? 'BLUE TEAM WINS' : data.winner === 2 ? 'RED TEAM WINS' : data.winner === 0 ? 'MATCH DRAWN' : 'SPECTATOR SESSION ENDED';
    }
    if (data.action === 'hide') hud.classList.add('hidden');
});
