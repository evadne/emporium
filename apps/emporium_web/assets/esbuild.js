// https://cloudless.studio/wrapping-your-head-around-assets-in-phoenix-1-6

const esbuild = require('esbuild')

let mode = 'build'
let options = {
  entryPoints: ['js/screen-generic.js'],
  bundle: true,
  logLevel: 'info',
  target: 'es2016',
  outdir: '../priv/static/assets'
}

process.argv.slice(2).forEach((arg) => {
  if (arg === '--watch') {
    mode = 'watch'
  } else if (arg === '--deploy') {
    mode = 'deploy'
  }
})

if (mode === 'watch') {
  options = {watch: true, sourcemap: 'inline', ...options}
} else if (mode === 'deploy') {
  options = {minify: true, ...options}
}

esbuild.build(options).then((result) => {
  if (mode === 'watch') {
    process.stdin.pipe(process.stdout)
    process.stdin.on('end', () => { result.stop() })
  }
}).catch((error) => {
  process.exit(1)
})
