import { build } from 'esbuild';

await build({
  entryPoints: ['elytro.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node18',
  packages: 'external', // viem + commander resolved from node_modules at runtime
  outfile: 'dist/elytro.js',
  banner: { js: '#!/usr/bin/env node' },
});
console.log('built dist/elytro.js');
