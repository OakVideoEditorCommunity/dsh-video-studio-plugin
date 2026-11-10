// SPDX-License-Identifier: GPL-3.0-or-later
/**
 * Host half of the `@oakvideoeditor/oak-deepseek-plugin` bundle.
 *
 * Responsibilities:
 *  - Create the preview directory when missing.
 *  - Serve `GET /video-studio/state`: JSON inventory of exported cuts.
 *  - Serve `GET /video-studio/media/<name>`: the media bytes with HTTP Range
 *    support so the browser <video> element can seek and play.
 *  - Add a short system-prompt section explaining the oak MCP workflow and the
 *    preview convention, so future sessions know where exports should land.
 *
 * The MCP server itself is connected by the `@deepseek-ai/dsh-mcp-client` row
 * inserted from cordis.patch.yml; this half only owns the preview surface.
 */

import fs from 'node:fs'
import fsp from 'node:fs/promises'
import { createRequire } from 'node:module'
import os from 'node:os'
import path from 'node:path'

/** Preview inventory route. */
const STATE_PATH = '/video-studio/state'
/** Media byte route prefix. */
const MEDIA_PREFIX = '/video-studio/media'

const VIDEO_EXTENSIONS = new Set(['.mp4', '.webm', '.mov', '.m4v', '.mkv'])
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.webp'])

const MIME_TYPES = {
	'.mp4': 'video/mp4',
	'.webm': 'video/webm',
	'.mov': 'video/quicktime',
	'.m4v': 'video/x-m4v',
	'.mkv': 'video/x-matroska',
	'.png': 'image/png',
	'.jpg': 'image/jpeg',
	'.jpeg': 'image/jpeg',
	'.webp': 'image/webp',
}

/** npm platform binary packages published by CI (optionalDependencies). */
const PLATFORM_PACKAGES = {
	'darwin-arm64': '@oakvideoeditor/oak-mcp-darwin-arm64',
	'linux-x64': '@oakvideoeditor/oak-mcp-linux-x64',
	'win32-x64': '@oakvideoeditor/oak-mcp-win32-x64',
}
/** Version of the binary this plugin build expects (kept in sync by CI). */
const PACKAGE_VERSION = '0.1.1'
const requireFromHere = createRequire(import.meta.url)

/** Directory the MCP command expression resolves to (shared with install scripts). */
function mcpInstallDir() {
	if (process.platform === 'win32') {
		return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'video-studio')
	}
	return path.join(os.homedir(), '.local', 'share', 'video-studio')
}

/**
 * Provision the oak-mcp binary from the matching npm platform package
 * (`optionalDependencies`) into {@link mcpInstallDir}, where the
 * `@deepseek-ai/dsh-mcp-client` row starts it. A pre-installed binary from the
 * GitHub release installer is left untouched. Runs synchronously once per
 * version, before the MCP client row activates.
 */
function ensureMcpBinary(logger) {
	const dir = mcpInstallDir()
	const isWindows = process.platform === 'win32'
	const exeName = isWindows ? 'oak-mcp.exe' : 'oak-mcp'
	const installedReal = path.join(dir, isWindows ? 'oak-mcp.exe' : 'oak-mcp.bin')
	const stampPath = path.join(dir, '.version')
	const stamp = fs.existsSync(stampPath) ? fs.readFileSync(stampPath, 'utf8').trim() : ''
	if (fs.existsSync(installedReal) && stamp === PACKAGE_VERSION) return true

	const packageName = PLATFORM_PACKAGES[`${process.platform}-${process.arch}`]
	if (packageName === undefined) {
		logger?.warn?.(`video-studio: no bundled oak-mcp for ${process.platform}-${process.arch}`)
		return fs.existsSync(installedReal)
	}
	let packageDir
	try {
		packageDir = path.dirname(requireFromHere.resolve(`${packageName}/package.json`))
	} catch {
		if (fs.existsSync(installedReal)) return true
		logger?.warn?.(`video-studio: platform package ${packageName} is not installed; set VIDEO_STUDIO_MCP_BIN`)
		return false
	}

	fs.mkdirSync(dir, { recursive: true })
	const sourceBin = path.join(packageDir, 'bin')
	const sourceLib = path.join(packageDir, 'lib')
	if (isWindows) {
		for (const name of fs.readdirSync(sourceBin)) {
			fs.copyFileSync(path.join(sourceBin, name), path.join(dir, name))
		}
	} else {
		const target = path.join(dir, 'oak-mcp.bin')
		fs.copyFileSync(path.join(sourceBin, 'oak-mcp'), target)
		fs.chmodSync(target, 0o755)
		fs.rmSync(path.join(dir, 'lib'), { recursive: true, force: true })
		if (fs.existsSync(sourceLib)) fs.cpSync(sourceLib, path.join(dir, 'lib'), { recursive: true })
		const wrapper = [
			'#!/bin/sh',
			'DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
			'if [ -d "$DIR/lib" ]; then',
			'  DYLD_LIBRARY_PATH="$DIR/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"; export DYLD_LIBRARY_PATH',
			'  LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; export LD_LIBRARY_PATH',
			'fi',
			'exec "$DIR/oak-mcp.bin" "$@"',
			'',
		].join('\n')
		fs.writeFileSync(path.join(dir, 'oak-mcp'), wrapper, { mode: 0o755 })
	}
	fs.writeFileSync(stampPath, `${PACKAGE_VERSION}\n`)
	logger?.info?.(`video-studio: installed oak-mcp ${PACKAGE_VERSION} from ${packageName}`)
	return true
}

/** Model-facing instructions; embeds the concrete preview directory. */
function systemPromptText(previewDir) {
	return `## 视频剪辑台（video-studio MCP）

本机已通过 \`oak\` MCP 服务器（基于 Quercus 引擎）提供完整的非线性剪辑能力，
工具名为 \`mcp__oak__<tool>\`，共 50 个（project_new、media_import、clip_place、
clip_trim、clip_split、transition_add、effect_add、preview_frame、export_start、
task_status/task_wait 等）。

工作约定：

- 时间是秒（f64）；节点 id 是工具返回的十进制字符串，不要自己编造 id。
- 一次典型流程：project_new → media_import → clip_place（按顺序铺素材）→
  clip_trim/clip_move/transition_add/effect_add → preview_frame 检查 →
  export_start → task_wait 等待导出完成。
- export_start 的 filename 用绝对路径。所有交付/预览成片请导出到
  \`${previewDir}\`（由 video-studio 插件监视）：用户打开 GUI 左侧
  侧栏的「视频预览」面板即可播放最新成片，面板每 2 秒自动刷新。
- 导出可能耗时，用 task_wait 轮询（timeout_ms 可到 180000）。导出完成后
  最好用 ffprobe 校验时长、分辨率、编码与音频流。
- \`preview_frame\` 返回 PNG，可用于逐帧检查构图；把关键帧另存到预览目录
  也能在面板里当作图片预览查看。
`
}

function sendJson(res, status, body) {
	const payload = JSON.stringify(body)
	res.writeHead(status, {
		'content-type': 'application/json; charset=utf-8',
		'cache-control': 'no-store',
	})
	res.end(payload)
}

/** Same-origin (or header-less desktop bridge) only. */
function trusted(req) {
	const origin = req.headers.origin
	if (origin === undefined) return true
	try {
		return new URL(origin).host === req.headers.host
	} catch {
		return false
	}
}

/** List previewable files newest-first. */
async function listPreviews(dir) {
	const names = await fsp.readdir(dir)
	const items = []
	for (const name of names) {
		const extension = path.extname(name).toLowerCase()
		const isVideo = VIDEO_EXTENSIONS.has(extension)
		const isImage = IMAGE_EXTENSIONS.has(extension)
		if (!isVideo && !isImage) continue
		let stat
		try {
			stat = await fsp.stat(path.join(dir, name))
		} catch {
			continue
		}
		if (!stat.isFile()) continue
		items.push({
			name,
			kind: isVideo ? 'video' : 'image',
			url: `${MEDIA_PREFIX}/${encodeURIComponent(name)}`,
			size: stat.size,
			mtimeMs: Math.round(stat.mtimeMs),
		})
	}
	items.sort((a, b) => b.mtimeMs - a.mtimeMs)
	return items
}

function serveMedia(dir, req, res) {
	if (req.method !== 'GET' && req.method !== 'HEAD') {
		res.writeHead(405, { allow: 'GET, HEAD' })
		res.end()
		return
	}
	if (!trusted(req)) {
		res.writeHead(403)
		res.end()
		return
	}

	const pathname = new URL(req.url ?? '/', 'http://dsh.local').pathname
	const raw = pathname.slice(MEDIA_PREFIX.length).replace(/^\/+/, '')
	let name = raw
	try {
		name = decodeURIComponent(raw)
	} catch {
		res.writeHead(400)
		res.end()
		return
	}
	// Basename only: no traversal, no nested paths, no hidden files.
	if (!name || name !== path.basename(name) || name.startsWith('.')) {
		res.writeHead(400)
		res.end()
		return
	}

	const file = path.join(dir, name)
	const extension = path.extname(name).toLowerCase()
	if (!VIDEO_EXTENSIONS.has(extension) && !IMAGE_EXTENSIONS.has(extension)) {
		res.writeHead(404)
		res.end()
		return
	}

	fs.stat(file, (error, stat) => {
		if (error || !stat.isFile()) {
			res.writeHead(404)
			res.end()
			return
		}

		const headers = {
			'content-type': MIME_TYPES[extension] ?? 'application/octet-stream',
			'accept-ranges': 'bytes',
			'cache-control': 'no-store',
		}

		const range = req.headers.range
		if (typeof range === 'string') {
			const match = /^bytes=(\d*)-(\d*)$/.exec(range.trim())
			if (!match) {
				res.writeHead(416, { 'content-range': `bytes */${stat.size}` })
				res.end()
				return
			}
			const start = match[1] === '' ? undefined : Number(match[1])
			const end = match[2] === '' ? undefined : Number(match[2])
			let from
			let to
			if (start === undefined && end === undefined) {
				res.writeHead(416, { 'content-range': `bytes */${stat.size}` })
				res.end()
				return
			}
			if (start === undefined) {
				// suffix range: last N bytes
				from = Math.max(0, stat.size - end)
				to = stat.size - 1
			} else {
				from = start
				to = end === undefined ? stat.size - 1 : Math.min(end, stat.size - 1)
			}
			if (from > to || from >= stat.size) {
				res.writeHead(416, { 'content-range': `bytes */${stat.size}` })
				res.end()
				return
			}
			res.writeHead(206, {
				...headers,
				'content-range': `bytes ${from}-${to}/${stat.size}`,
				'content-length': String(to - from + 1),
			})
			if (req.method === 'HEAD') {
				res.end()
				return
			}
			fs.createReadStream(file, { start: from, end: to }).pipe(res)
			return
		}

		res.writeHead(200, { ...headers, 'content-length': String(stat.size) })
		if (req.method === 'HEAD') {
			res.end()
			return
		}
		fs.createReadStream(file).pipe(res)
	})
}

/** @param {import('cordis').Context} ctx @param {{ previewDir?: string }} config */
export function apply(ctx, config = {}) {
	try {
		ensureMcpBinary(ctx.logger)
	} catch (error) {
		ctx.logger?.warn?.(`video-studio: oak-mcp provisioning failed: ${error?.message ?? error}`)
	}

	const previewDir = path.resolve(
		config.previewDir ??
			path.join(os.homedir(), '.dsh', 'video-studio', 'previews'),
	)
	void fsp.mkdir(previewDir, { recursive: true }).catch(() => {})

	ctx.inject(['webServer'], (scoped) => {
		const webServer = scoped.webServer
		if (webServer === undefined || typeof webServer.register !== 'function') return

		const disposeState = webServer.register({
			kind: 'exact',
			path: STATE_PATH,
			handler: async (req, res) => {
				if (!trusted(req)) {
					res.writeHead(403)
					res.end()
					return
				}
				try {
					const items = await listPreviews(previewDir)
					sendJson(res, 200, {
						ok: true,
						dir: previewDir,
						updatedAt: Date.now(),
						latest: items[0]?.name ?? null,
						items,
					})
				} catch (error) {
					if (error && error.code === 'ENOENT') {
						sendJson(res, 200, { ok: true, dir: previewDir, updatedAt: Date.now(), latest: null, items: [] })
						return
					}
					sendJson(res, 500, { ok: false, error: String(error?.message ?? error) })
				}
			},
		})

		const disposeMedia = webServer.register({
			kind: 'prefix',
			path: MEDIA_PREFIX,
			handler: (req, res) => serveMedia(previewDir, req, res),
		})

		scoped.effect(
			() => () => {
				disposeMedia()
				disposeState()
			},
			'video-studio.routes',
		)
		ctx.logger?.info?.(`video-studio: preview routes ready (${previewDir})`)
	})

	ctx.inject(['systemPrompt'], (scoped) => {
		const systemPrompt = scoped.systemPrompt
		if (systemPrompt === undefined || typeof systemPrompt.section !== 'function') return
		scoped.effect(
			() =>
				systemPrompt.section({
					name: 'video-studio',
					order: 85,
					text: systemPromptText(previewDir),
					interpolate: false,
				}),
			'video-studio.system-prompt',
		)
	})
}
