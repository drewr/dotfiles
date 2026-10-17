// Spike 3: exercise exactly the Node facilities an agent needs.
// Step A: does node start and print? (no fork)
// Step B: can it spawn a child process? (the known risk)
// Step C: can it read the filesystem and env? (agent prerequisites)
const { execSync, spawnSync } = require('child_process');
const fs = require('fs');

console.log('[node] hello from node', process.version, 'pid', process.pid);
console.log('[node] platform', process.platform, 'arch', process.arch);
console.log('[node] env PATH =', process.env.PATH);
console.log('[node] cwd', process.cwd());

// filesystem
try {
  const ents = fs.readdirSync('/');
  console.log('[node] readdir / =', JSON.stringify(ents.slice(0, 20)));
} catch (e) {
  console.log('[node] readdir / FAILED:', e.message);
}

// child process via spawnSync (uses posix_spawn / fork+exec depending on platform)
console.log('[node] attempting spawnSync(/bin/echo)...');
try {
  const r = spawnSync('/bin/echo', ['spawn-child-ok'], { encoding: 'utf8' });
  console.log('[node] spawnSync status=', r.status, 'stdout=', JSON.stringify(r.stdout), 'err=', r.error && r.error.message);
} catch (e) {
  console.log('[node] spawnSync THREW:', e.message);
}

// the classic shell path (what agents use for tool calls)
console.log('[node] attempting execSync(...)...');
try {
  const out = execSync('/bin/echo exec-ok', { encoding: 'utf8' });
  console.log('[node] execSync out=', JSON.stringify(out));
} catch (e) {
  console.log('[node] execSync FAILED:', e.message);
}
console.log('[node] done');
