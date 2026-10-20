// Dev-only workaround: inside the DSH sandbox, Vite 8's config loader probes
// Windows network mounts with `net use`, which is denied (EPERM). Failing that
// single probe makes Vite fall back to fs.realpathSync and start normally.
// In a normal terminal this shim is NOT needed.
const cp = require('child_process');
const orig = cp.exec;
cp.exec = function (cmd, opts, cb) {
  if (typeof opts === 'function') { cb = opts; opts = undefined; }
  if (typeof cmd === 'string' && cmd.includes('net use')) {
    if (typeof cb === 'function') process.nextTick(() => cb(new Error('net use disabled by dev shim')));
    return { on() {}, kill() {} };
  }
  return orig.call(this, cmd, opts, cb);
};
