// nixy_loader v2
// Two jobs:
//   1. Spawn injector.exe to load fake_hook.dll into FXServer.
//   2. On a timer, pull JSON from fake_players exports and write cache files.

const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');

const tag = '[nixy_loader]';
const resourceName = GetCurrentResourceName();

function log(msg) { console.log(`${tag} ${msg}`); }
function resourcePath(f) { return path.join(GetResourcePath(resourceName), f); }

const CACHE_DIR = resourcePath('cache');
try { fs.mkdirSync(CACHE_DIR, { recursive: true }); } catch (_) {}

function writeCacheOnce() {
    try {
        const fp = global.exports['fake_players'];
        if (!fp) {
            log('WARN: fake_players exports not available yet');
            return;
        }

        fs.writeFileSync(path.join(CACHE_DIR, 'players.json'), fp.GetPlayersJson());
        fs.writeFileSync(path.join(CACHE_DIR, 'dynamic.json'), fp.GetDynamicJson());
        fs.writeFileSync(path.join(CACHE_DIR, 'info.json'),    fp.GetInfoJson());
    } catch (err) {
        log(`cache write failed: ${err.message}`);
    }
}

let writeCount = 0;
function startWriter() {
    writeCacheOnce();
    writeCount++;
    log(`first cache write done (count=${writeCount})`);

    setInterval(() => {
        writeCacheOnce();
        writeCount++;
        if (writeCount % 60 === 0) {
            log(`cache writer: ${writeCount} writes so far`);
        }
    }, 1000);
}

function runInjector() {
    const injectorPath = resourcePath('injector.exe');
    const dllPath      = resourcePath('fake_hook.dll');

    if (!fs.existsSync(injectorPath)) {
        log(`FATAL: injector.exe missing at ${injectorPath}`);
        return;
    }
    if (!fs.existsSync(dllPath)) {
        log(`FATAL: fake_hook.dll missing at ${dllPath}`);
        return;
    }

    // process.pid in FXServer's Node runtime is FXServer itself.
    // process.ppid would be whatever launched FXServer (e.g. PowerShell).
    const targetPid = process.pid;
    log(`spawning injector pid=${targetPid} (self)`);
    log(`dll=${dllPath}`);

    const child = spawn(injectorPath, [String(targetPid), dllPath], {
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
    });

    child.stdout.on('data', (d) => log(`out: ${d.toString().trimEnd()}`));
    child.stderr.on('data', (d) => log(`err: ${d.toString().trimEnd()}`));

    child.on('exit', (code) => {
        if (code === 0) {
            log('injector completed — hook should be active');
            log('watch fake_hook.log for hook activity');
        } else {
            log(`injector exited code=${code}`);
        }
    });

    child.on('error', (err) => log(`spawn error: ${err.message}`));
}

// Start writer first so cache exists by the time the hook needs it
setTimeout(() => {
    log('starting cache writer');
    startWriter();
}, 500);

// Then inject after HTTP server is definitely up
setTimeout(() => {
    log('spawning injector');
    runInjector();
}, 2500);
