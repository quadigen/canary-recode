import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'out');

const routes = [
  'docs.html',
  'docs/kne.html',
  'docs/kne/getting-started.html',
  'docs/kne/lifecycle.html',
  'docs/kne/host-api.html',
  'docs/kne/luau-interop.html',
  'docs/kne/classes-and-datatypes.html',
  'docs/kne/signals-and-callbacks.html',
  'docs/kne/distribution.html',
  'docs/native-sdk.html',
  'docs/native-sdk/getting-started.html',
  'docs/native-sdk/runtime-loading.html',
  'docs/native-sdk/plugin-authoring.html',
  'docs/native-sdk/classes-and-services.html',
  'docs/native-sdk/datatypes.html',
  'docs/native-sdk/signals-and-callbacks.html',
  'docs/native-sdk/reference.html',
  'docs/native-sdk/migrating-from-kne.html',
  'docs/native-sdk/instance-metadata.html',
  'docs/native-sdk/networking-and-services.html',
  'docs/native-sdk/players-and-physics.html',
  'docs/native-sdk/gpu-compute.html',
  'docs/VRService.html',
];

for (const route of routes) {
  const location = path.join(output, route);
  const info = await stat(location);
  if (!info.isFile() || info.size === 0) throw new Error('Missing output: ' + route);
}

const checks = [
  ['index.html', '/docs/native-sdk'],
  ['docs.html', '/docs/VRService'],
  ['docs.html', '/docs/native-sdk'],
  ['docs/native-sdk.html', '/docs/native-sdk/getting-started'],
  ['docs/native-sdk.html', '/docs/native-sdk/runtime-loading'],
  ['docs/native-sdk.html', '/docs/native-sdk/plugin-authoring'],
  ['docs/native-sdk.html', '/docs/native-sdk/classes-and-services'],
  ['docs/native-sdk.html', '/docs/native-sdk/datatypes'],
  ['docs/native-sdk.html', '/docs/native-sdk/signals-and-callbacks'],
  ['docs/native-sdk.html', '/docs/native-sdk/reference'],
  ['docs/native-sdk.html', '/docs/native-sdk/migrating-from-kne'],
  ['docs/native-sdk.html', '/docs/native-sdk/instance-metadata'],
  ['docs/native-sdk.html', '/docs/native-sdk/networking-and-services'],
  ['docs/native-sdk.html', '/docs/native-sdk/players-and-physics'],
  ['docs/native-sdk.html', '/docs/native-sdk/gpu-compute'],
  ['docs/kne.html', '/docs/native-sdk/plugin-authoring'],
];

for (const [route, href] of checks) {
  const html = await readFile(path.join(output, route), 'utf8');
  if (!html.includes('href="' + href + '"')) {
    throw new Error('Missing navigation link ' + href + ' in ' + route);
  }
}

const staticHtml = async function* (directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const filename = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      yield* staticHtml(filename);
    } else if (entry.isFile() && entry.name.endsWith('.html')) {
      yield filename;
    }
  }
};

let checkedLinks = 0;
let checkedPages = 0;
const brokenLinks = [];

for await (const filename of staticHtml(output)) {
  const relative = path.relative(output, filename).replaceAll(path.sep, '/');
  const pageRoute = relative === 'index.html'
    ? '/'
    : '/' + relative.replace(/\.html$/, '');
  const pageUrl = new URL(pageRoute, 'https://kinemium.docs.quadigen.com');
  const html = await readFile(filename, 'utf8');
  const links = html.matchAll(/<a\b[^>]*\bhref="([^"]+)"/g);

  for (const match of links) {
    const href = match[1].replaceAll('&amp;', '&');
    if (!href || href.startsWith('#') || href.startsWith('mailto:') ||
        href.startsWith('tel:') || href.startsWith('//')) continue;
    const target = new URL(href, pageUrl);
    if (target.origin !== pageUrl.origin) continue;
    const targetPath = decodeURIComponent(target.pathname);
    const relativeTarget = targetPath.replace(/^\//, '');
    const candidates = targetPath === '/'
      ? [path.join(output, 'index.html')]
      : [
          path.join(output, relativeTarget + '.html'),
          path.join(output, relativeTarget, 'index.html'),
          path.join(output, relativeTarget),
        ];
    checkedLinks++;
    let found = false;
    for (const candidate of candidates) {
      try {
        if ((await stat(candidate)).isFile()) {
          found = true;
          break;
        }
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
      }
    }
    if (!found) brokenLinks.push(relative + ': ' + href);
  }
  checkedPages++;
}
if (brokenLinks.length !== 0) {
  throw new Error('Broken internal links:\n' + brokenLinks.slice(0, 30).join('\n') +
      (brokenLinks.length > 30 ? '\n... and ' + (brokenLinks.length - 30) + ' more' : ''));
}

const index = await readFile(path.join(output, 'api/search'), 'utf8');
for (const url of ['/docs/kne', '/docs/native-sdk', '/docs/native-sdk/reference', '/docs/native-sdk/runtime-loading', '/docs/native-sdk/plugin-authoring', '/docs/native-sdk/classes-and-services', '/docs/native-sdk/networking-and-services', '/docs/native-sdk/players-and-physics', '/docs/native-sdk/gpu-compute', '/docs/native-sdk/datatypes', '/docs/native-sdk/signals-and-callbacks', '/docs/VRService']) {
  if (!index.includes(url)) throw new Error('Missing search entry: ' + url);
}

console.log('Verified ' + checkedPages + ' exported HTML pages, ' + checkedLinks + ' internal links, native SDK navigation and static search.');
