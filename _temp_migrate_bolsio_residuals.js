const fs = require('fs');
const path = require('path');

const root = 'c:/Users/ramse/OneDrive/Documents/vacas/bolsio';
const excludedSegments = [
  '/.git/',
  '/android/keys/',
  '/android/app/google-services.json',
  '/google-services (2).json',
  '/google-services (4).json',
  '/bolsio-c6a69-firebase-adminsdk-fbsvc-2257b2a855.json',
  '/bolsio-c6a69-firebase-adminsdk-fbsvc-2aea097547.json',
  '/lib/firebase_options.dart',
];
const textExtensions = new Set(['.md', '.html', '.htm', '.jsx', '.js', '.yaml', '.yml', '.txt', '.rc', '.json', '.dart']);
const url = '__BOLSIO_GITHUB_URL__';
const urlPlaceholder = '__BOLSIO_GITHUB_URL__';

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!full.includes(`${path.sep}.git${path.sep}`)) walk(full, out);
    } else {
      out.push(full);
    }
  }
  return out;
}

function shouldSkip(filePath) {
  const normalized = filePath.replace(/\\/g, '/');
  return excludedSegments.some((segment) => normalized.includes(segment));
}

function replaceText(text) {
  let next = text;
  next = next.replaceAll(url, urlPlaceholder);
  next = next.replace(/\bbolsio(?=[A-Z])/g, 'bolsio');
  next = next.replace(/\bBolsio(?=[A-Z])/g, 'Bolsio');
  next = next.replace(/\bBOLSIO(?=[A-Z])/g, 'BOLSIO');
  next = next.replace(/Bolsio/g, 'Bolsio');
  next = next.replace(/BOLSIO/g, 'BOLSIO');
  next = next.replace(/bolsio/g, 'bolsio');
  next = next.replaceAll('bolsio_', 'bolsio_');
  next = next.replaceAll('Bolsio_', 'Bolsio_');
  next = next.replaceAll('BOLSIO_', 'BOLSIO_');
  next = next.replaceAll(urlPlaceholder, url);
  return next;
}

function renameBolsioFiles(filePath) {
  const base = path.basename(filePath);
  if (!base.includes('bolsio')) return null;
  const renamedBase = base.replaceAll('bolsio', 'bolsio');
  if (renamedBase === base) return null;
  return path.join(path.dirname(filePath), renamedBase);
}

const files = walk(root).filter((filePath) => textExtensions.has(path.extname(filePath)));
for (const filePath of files) {
  if (shouldSkip(filePath)) continue;
  const original = fs.readFileSync(filePath, 'utf8');
  const updated = replaceText(original);
  if (updated !== original) fs.writeFileSync(filePath, updated);
}

for (const filePath of files) {
  if (shouldSkip(filePath)) continue;
  const newPath = renameBolsioFiles(filePath);
  if (newPath && !fs.existsSync(newPath)) {
    fs.renameSync(filePath, newPath);
  }
}

console.log('residuals done');