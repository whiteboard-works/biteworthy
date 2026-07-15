#!/usr/bin/env node
//
// Render the committed icon/splash PNGs from the SVG sources in ../assets.
//
// Rasterizes with rsvg-convert (librsvg) rather than the sharp pipeline the
// README first sketched: librsvg renders the SVG's "BW" text reliably via Pango
// without a native-module install or an outline-the-font step. If it's missing:
//   macOS:  brew install librsvg      linux:  apt-get install librsvg2-bin
//
// The rendered PNGs are committed (they're tiny) so EAS builds and Next don't
// need a render step. Regenerate after editing any *-source.svg:
//   pnpm --filter @biteworthy/mobile run render:assets
//
/* eslint-disable no-console -- this is a CLI build script; console output is the UI */
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));
const assets = join(here, '..', 'assets');
const webApp = join(here, '..', '..', 'web', 'src', 'app');

try {
  execFileSync('rsvg-convert', ['--version'], { stdio: 'ignore' });
} catch {
  console.error('rsvg-convert not found — install librsvg (macOS: brew install librsvg).');
  process.exit(1);
}

function render(src, out, w, h = w) {
  execFileSync('rsvg-convert', ['-w', String(w), '-h', String(h), join(assets, src), '-o', out]);
  console.log(`  ✓ ${out.replace(join(here, '..', '..', '..') + '/', '')}  ${w}×${h}`);
}

// Mobile (Expo)
render('icon-source.svg', join(assets, 'icon.png'), 1024); // iOS app icon
render('adaptive-foreground.svg', join(assets, 'adaptive-icon.png'), 1024); // Android foreground
render('splash-source.svg', join(assets, 'splash.png'), 1284, 2778); // launch screen
render('icon-source.svg', join(assets, 'favicon.png'), 48); // Expo web fallback

// Web (Next.js App Router auto-wires app/icon.* + app/apple-icon.*)
if (existsSync(webApp)) {
  render('icon-source.svg', join(webApp, 'icon.png'), 512);
  render('icon-source.svg', join(webApp, 'apple-icon.png'), 180);
}

console.log('done — commit the rendered PNGs.');
