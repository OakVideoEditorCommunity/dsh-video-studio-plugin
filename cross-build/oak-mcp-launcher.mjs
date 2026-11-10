#!/usr/bin/env node
// oak-mcp launcher: resolves the platform binary package installed as an
// optionalDependency and execs it with the bundled libraries on the loader path.
// Works as an MCP stdio server: `npx -y @oakvideoeditor/oak-mcp`.
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import path from 'node:path'

const PACKAGES = {
	'darwin-arm64': '@oakvideoeditor/oak-mcp-darwin-arm64',
	'linux-x64': '@oakvideoeditor/oak-mcp-linux-x64',
	'win32-x64': '@oakvideoeditor/oak-mcp-win32-x64',
}

const key = `${process.platform}-${process.arch}`
const packageName = PACKAGES[key]
if (packageName === undefined) {
	console.error(`oak-mcp: unsupported platform ${key}. Supported: ${Object.keys(PACKAGES).join(', ')}`)
	process.exit(1)
}

const require = createRequire(import.meta.url)
let packageDir
try {
	packageDir = path.dirname(require.resolve(`${packageName}/package.json`))
} catch (error) {
	console.error(`oak-mcp: platform package ${packageName} is not installed (${error?.message ?? error})`)
	console.error('oak-mcp: try reinstalling @oakvideoeditor/oak-mcp, or set OAK_MCP_BIN to an existing binary')
	process.exit(1)
}

const executable =
	process.env.OAK_MCP_BIN ??
	path.join(packageDir, 'bin', process.platform === 'win32' ? 'oak-mcp.exe' : 'oak-mcp')

const env = { ...process.env }
if (process.platform !== 'win32') {
	const libDir = path.join(packageDir, 'lib')
	const loaderKey = process.platform === 'darwin' ? 'DYLD_LIBRARY_PATH' : 'LD_LIBRARY_PATH'
	env[loaderKey] = env[loaderKey] ? `${libDir}:${env[loaderKey]}` : libDir
}

const child = spawn(executable, process.argv.slice(2), { stdio: 'inherit', env })
for (const signal of ['SIGINT', 'SIGTERM']) {
	process.on(signal, () => {
		try {
			child.kill(signal)
		} catch {}
	})
}
child.on('error', (error) => {
	console.error(`oak-mcp: failed to start ${executable}: ${error.message}`)
	process.exit(1)
})
child.on('exit', (code, signal) => {
	if (signal) {
		process.kill(process.pid, signal)
		return
	}
	process.exit(code ?? 0)
})
