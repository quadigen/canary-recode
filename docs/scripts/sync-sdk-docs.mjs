import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const docsRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(docsRoot, 'sdk/README.md');
const target = path.join(docsRoot, 'content/docs/native-sdk/reference.mdx');
const markdown = (await readFile(source, 'utf8'))
  .replace(/^# Kinemium Native SDK\s*\n/, '')
  .trim();

const content = [
  '---',
  'title: Unified Native SDK API reference',
  'description: Unified SDK API and integration documentation, synchronized from the source README.',
  '---',
  '',
  markdown,
  '',
].join('\n');

let previous = '';
try {
  previous = await readFile(target, 'utf8');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
if (content !== previous) {
  await writeFile(target, content);
  console.log('Updated native C SDK reference for Fumadocs');
}
