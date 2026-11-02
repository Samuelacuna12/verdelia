const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.join(__dirname, '..', 'dist');
const origin = 'https://samuelacuna12.github.io';
const manifestUrl = origin + '/verdelia/manifest.webmanifest';
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.webmanifest')));
assert.equal(new URL(manifest.id, manifestUrl).pathname, '/verdelia/');
assert.equal(new URL(manifest.start_url, manifestUrl).pathname, '/verdelia/');
assert.equal(new URL(manifest.scope, manifestUrl).pathname, '/verdelia/');
for (const icon of manifest.icons) assert(fs.existsSync(path.join(root, icon.src)));
for (const shortcut of manifest.shortcuts) assert(new URL(shortcut.url, manifestUrl).pathname.startsWith('/verdelia/'));
const events = {}, removed = [];
const currentPrefix = 'verdelia-shell-/verdelia/-';
vm.runInNewContext(fs.readFileSync(path.join(root, 'sw.js'), 'utf8'), {
  URL,
  self: {
    registration: {scope: origin + '/verdelia/'},
    location: {origin, href: origin + '/verdelia/sw.js'},
    addEventListener(type, fn) { events[type] = fn; },
    clients: {claim() {}},
  },
  caches: {
    async keys() {return [currentPrefix + 'v1', currentPrefix + 'v5', 'invicto-assets-v1', 'verdelia-shell-/otra-app/-v1'];},
    async delete(key) {removed.push(key);},
  },
});
(async () => {
  let completion;
  events.activate({waitUntil(promise) {completion = promise;}});
  await completion;
  assert.deepEqual(removed, [currentPrefix + 'v1'], 'Must never remove another application cache');
  let intercepted = false;
  events.fetch({request: {method: 'GET', url: 'https://example.supabase.co/rest/v1/products'}, respondWith() {intercepted = true;}});
  assert.equal(intercepted, false, 'Database responses must not be cached');
  events.fetch({request: {method: 'POST', url: origin + '/verdelia/'}, respondWith() {intercepted = true;}});
  assert.equal(intercepted, false, 'Writes must not be cached');
  console.log('PASS: GitHub Pages paths, icons, shortcuts, application cache isolation and no API caching');
})().catch(error => {console.error(error); process.exitCode = 1;});
