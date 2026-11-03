// Standalone bundle config for this override build.
//
// Upstream runs the workspace tsdown config with entry `lib/types/{index,startup}.js`
// plus the Typert code-generation plugin. This package publishes only the host
// face of `index`, so the entry list here is just `lib/types/index.js`; the
// Typert artifacts ship pre-generated under typert/ (see README.md).
//
// A plain object (no `import { defineConfig } from 'tsdown'`) keeps this config
// independent of where the repo's build tooling is installed.
export default {
  entry: ['lib/types/index.js'],
  outDir: 'lib',
  format: ['esm'],
  platform: 'node',
  target: 'es2024',
  fixedExtension: false,
  dts: false,
  clean: false,
  sourcemap: false,
}
