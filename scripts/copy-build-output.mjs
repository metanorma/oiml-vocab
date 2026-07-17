#!/usr/bin/env node
// Workaround for glossarist/concept-browser#118:
// 0.7.77's Astro build writes output to the package's own dist/ inside
// node_modules/. Copy it to the consumer's ./dist/ where the deploy
// workflow's upload-artifact step expects it.
// Remove once upstream #118 is merged and released.

import { cpSync, existsSync, mkdirSync, rmSync } from 'fs';
import { resolve } from 'path';

const cwd = process.cwd();
const pkgDist = resolve(cwd, 'node_modules/@glossarist/concept-browser/dist');
const outDist = resolve(cwd, 'dist');

if (!existsSync(pkgDist)) {
  console.error(`[copy-build-output] package dist not found: ${pkgDist}`);
  console.error('Did concept-browser build run?');
  process.exit(1);
}

if (existsSync(outDist)) {
  rmSync(outDist, { recursive: true, force: true });
}
mkdirSync(outDist, { recursive: true });

cpSync(pkgDist, outDist, { recursive: true });
console.log(`[copy-build-output] copied ${pkgDist} → ${outDist}`);
