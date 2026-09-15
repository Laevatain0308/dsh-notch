/**
 * Build the Host plugin: transpile `src/*.ts` into `lib/*.js`.
 *
 * The packaged DSH Desktop Host process runs on Node 24, whose built-in
 * TypeScript support is strip-only. It erases type annotations but refuses to
 * rewrite syntax that emits code, and `src/board.ts` constructs its instance
 * state with a parameter property (`constructor(private readonly ctx)`), which
 * strip-only mode rejects with `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX`. The sources
 * therefore cannot be imported directly by a Host that carries no TypeScript
 * loader, and this build emits the plain ESM that such a Host does load.
 *
 * Emitted files are ordinary ESM, so relative specifiers are rewritten from
 * `.ts` to `.js`; the build fails rather than shipping a specifier it did not
 * rewrite.
 */
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { transform } from 'esbuild'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const sourceDir = join(root, 'src')
const outputDir = join(root, 'lib')

/**
 * Collect every TypeScript source under a directory.
 * @param dir - absolute directory to walk.
 * @returns absolute paths of the `.ts` files found, in directory order.
 */
async function collectSources(dir) {
  const entries = await readdir(dir, { withFileTypes: true })
  const found = []
  for (const entry of entries) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) found.push(...await collectSources(path))
    else if (entry.name.endsWith('.ts')) found.push(path)
  }
  return found
}

/**
 * Repoint relative `.ts` specifiers at the emitted `.js` files.
 * @param code - transpiled module source.
 * @param label - repo-relative path, used in the failure message.
 * @returns the module source with every relative specifier ending in `.js`.
 */
function rewriteSpecifiers(code, label) {
  const rewritten = code
    .replace(/(\bfrom\s*['"])(\.{1,2}\/[^'"]*?)\.ts(['"])/gu, '$1$2.js$3')
    .replace(/(\bimport\s*\(\s*['"])(\.{1,2}\/[^'"]*?)\.ts(['"])/gu, '$1$2.js$3')
  const leftover = /(?:\bfrom\s*|\bimport\s*\(\s*)['"]\.{1,2}\/[^'"]*\.ts['"]/u.exec(rewritten)
  if (leftover !== null) {
    throw new Error(`${label}: unrewritten TypeScript specifier ${leftover[0]}`)
  }
  return rewritten
}

const sources = await collectSources(sourceDir)
if (sources.length === 0) throw new Error(`build-host: no TypeScript sources under ${sourceDir}`)

for (const source of sources) {
  const label = relative(root, source)
  const result = await transform(await readFile(source, 'utf8'), {
    loader: 'ts',
    format: 'esm',
    target: 'node22',
    sourcemap: 'external',
    sourcesContent: true,
  })
  const target = join(outputDir, relative(sourceDir, source).replace(/\.ts$/u, '.js'))
  await mkdir(dirname(target), { recursive: true })
  const code = `${rewriteSpecifiers(result.code, label)}\n//# sourceMappingURL=${relative(dirname(target), target)}.map\n`
  await writeFile(target, code)
  await writeFile(`${target}.map`, result.map)
  process.stdout.write(`build-host: ${label} -> ${relative(root, target)}\n`)
}

process.stdout.write(`build-host: ${String(sources.length)} module(s) written to ${relative(root, outputDir)}\n`)
