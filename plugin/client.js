// SPDX-License-Identifier: GPL-3.0-or-later
/**
 * Client half of the `@local/video-studio` bundle.
 *
 * Adds a sidebar panel ("视频预览") whose main view plays the newest cut
 * exported by the oak MCP server. The Host half serves the inventory and the
 * media bytes, so this module only fetches JSON and renders a <video>.
 */
window.__ModuleLoader__.load({
	id: '@local/video-studio',
	factory(require) {
		const React = require('react')
		const h = React.createElement

		const PANEL_ID = 'video-studio'
		const STATE_PATH = '/video-studio/state'
		const POLL_MS = 2000

		const ZH = {
			title: '视频预览',
			subtitle: 'oak MCP 导出的最新成片会自动出现在这里',
			refresh: '刷新',
			emptyTitle: '还没有可预览的成片',
			emptyHint: '让助手用 oak MCP 剪辑并导出到 video-studio/previews/，面板会自动显示最新一条。',
			loading: '正在读取预览…',
			error: '无法读取预览目录',
			video: '视频',
			image: '图片',
			dirLabel: '预览目录',
			retry: '重试',
			playbackFailed: '浏览器无法播放这个文件，请换一条预览或让助手重新导出为 MP4。',
		}
		const EN = {
			title: 'Video preview',
			subtitle: 'The newest cut exported by the oak MCP server appears here automatically.',
			refresh: 'Refresh',
			emptyTitle: 'No preview yet',
			emptyHint: 'Ask the agent to cut and export with the oak MCP into video-studio/previews/. The newest file shows up here.',
			loading: 'Loading previews…',
			error: 'Cannot read the preview directory',
			video: 'Video',
			image: 'Image',
			dirLabel: 'Preview folder',
			retry: 'Retry',
			playbackFailed: 'This file cannot play in the browser. Pick another preview or ask the agent to export MP4.',
		}

		const CSS = `
.vs-page {
  display: flex; flex-direction: column; gap: 12px;
  box-sizing: border-box; height: 100%; min-height: 0;
  padding: 20px 24px 16px; overflow: hidden;
  background: var(--dsw-alias-bg-base);
  color: var(--dsw-alias-label-primary);
  font-size: 13px;
}
.vs-header { display: flex; align-items: flex-start; gap: 12px; flex: none; }
.vs-heading { display: flex; flex-direction: column; gap: 3px; min-width: 0; flex: 1; }
.vs-title { font-size: 17px; font-weight: 600; line-height: 1.3; }
.vs-subtitle { font-size: 12px; color: var(--dsw-alias-label-secondary); }
.vs-refresh {
  flex: none; height: 28px; padding: 0 12px; border-radius: 7px; cursor: pointer;
  border: 1px solid var(--dsw-alias-border-l2);
  background: var(--dsw-alias-bg-layer-1);
  color: var(--dsw-alias-label-primary); font-size: 12px;
}
.vs-refresh:hover { background: var(--dsw-alias-bg-layer-2); }
.vs-stage {
  flex: 1; min-height: 0; display: flex; align-items: center; justify-content: center;
  border: 1px solid var(--dsw-alias-border-l1); border-radius: 10px;
  background: var(--dsw-alias-bg-layer-1); overflow: hidden; position: relative;
}
.vs-video {
  display: block; max-width: 100%; max-height: 100%; width: auto; height: auto;
  background: #000; outline: none;
}
.vs-frame { max-width: 100%; max-height: 100%; object-fit: contain; }
.vs-empty {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 10px; padding: 32px; text-align: center; color: var(--dsw-alias-label-secondary);
}
.vs-empty-title { font-size: 14px; font-weight: 600; color: var(--dsw-alias-label-primary); }
.vs-empty-hint { font-size: 12px; line-height: 1.6; max-width: 460px; }
.vs-badge {
  font-size: 11px; padding: 1px 7px; border-radius: 999px;
  border: 1px solid var(--dsw-alias-border-l2);
  color: var(--dsw-alias-label-secondary);
}
.vs-info { display: flex; align-items: center; gap: 10px; flex: none; min-width: 0; }
.vs-name {
  font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  direction: rtl; text-align: left; max-width: 60%;
}
.vs-meta { font-size: 12px; color: var(--dsw-alias-label-secondary); white-space: nowrap; }
.vs-list {
  flex: none; display: flex; gap: 8px; overflow-x: auto; padding-bottom: 4px;
}
.vs-item {
  flex: none; min-width: 150px; max-width: 220px; text-align: left; cursor: pointer;
  display: flex; flex-direction: column; gap: 2px;
  padding: 8px 10px; border-radius: 8px;
  border: 1px solid var(--dsw-alias-border-l1);
  background: var(--dsw-alias-bg-layer-1);
  color: var(--dsw-alias-label-primary); font-size: 12px;
}
.vs-item:hover { background: var(--dsw-alias-bg-layer-2); }
.vs-item[data-active='true'] {
  border-color: var(--dsw-alias-brand-primary);
  box-shadow: inset 0 0 0 1px var(--dsw-alias-brand-primary);
}
.vs-item-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.vs-item-meta { color: var(--dsw-alias-label-secondary); font-size: 11px; }
.vs-footer {
  flex: none; display: flex; gap: 8px; align-items: center;
  font-size: 11px; color: var(--dsw-alias-label-secondary);
}
.vs-footer-path { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.vs-error { color: var(--dsw-alias-state-error-primary); }
`

		function formatSize(bytes) {
			if (!Number.isFinite(bytes) || bytes <= 0) return ''
			if (bytes < 1024) return `${bytes} B`
			if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
			return `${(bytes / 1024 / 1024).toFixed(1)} MB`
		}

		function formatRelative(mtimeMs) {
			if (!Number.isFinite(mtimeMs)) return ''
			const seconds = Math.max(0, Math.round((Date.now() - mtimeMs) / 1000))
			if (seconds < 60) return '刚刚'
			const minutes = Math.round(seconds / 60)
			if (minutes < 60) return `${minutes} 分钟前`
			const hours = Math.round(minutes / 60)
			if (hours < 24) return `${hours} 小时前`
			const date = new Date(mtimeMs)
			return `${date.getMonth() + 1}/${date.getDate()} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
		}

		return {
			inject: ['slots'],
			apply(ctx) {
				const slots = ctx.slots
				if (slots === undefined) return undefined

				const locale = typeof ctx.get === 'function' ? ctx.get('locale') : undefined
				const t = (key, fallback) => {
					try {
						if (locale && typeof locale.bind === 'function') {
							const translate = locale.bind('video-studio')
							const value = typeof translate === 'function' ? translate(key) : undefined
							if (typeof value === 'string' && value.length > 0) return value
						}
					} catch {}
					return fallback
				}

				function VideoStudioIcon({ size = 16 }) {
					return h(
						'svg',
						{ width: size, height: size, viewBox: '0 0 24 24', fill: 'none', 'aria-hidden': true },
						h('rect', {
							x: 3,
							y: 7,
							width: 18,
							height: 13,
							rx: 2,
							stroke: 'currentColor',
							strokeWidth: 1.7,
						}),
						h('path', { d: 'M3 11h18', stroke: 'currentColor', strokeWidth: 1.7 }),
						h('path', {
							d: 'M7.5 7L9.5 3M12.5 7L14.5 3M17.5 7L19.5 3',
							stroke: 'currentColor',
							strokeWidth: 1.7,
							strokeLinecap: 'round',
						}),
					)
				}

				function VideoStudioPanel() {
					const [state, setState] = React.useState({ phase: 'loading', items: [], dir: '' })
					const [selectedName, setSelectedName] = React.useState(null)
					const [manualSelection, setManualSelection] = React.useState(false)
					const [failure, setFailure] = React.useState(false)
					const followLatest = React.useRef(true)

					const load = React.useCallback(async () => {
						try {
							const response = await fetch(STATE_PATH, { cache: 'no-store' })
							if (!response.ok) throw new Error(`HTTP ${response.status}`)
							const data = await response.json()
							const items = Array.isArray(data.items) ? data.items : []
							setState({ phase: 'ready', items, dir: typeof data.dir === 'string' ? data.dir : '' })
							setFailure(false)
							const latest = typeof data.latest === 'string' ? data.latest : null
							if (followLatest.current) {
								const item = items.find((candidate) => candidate.name === latest) ?? items[0]
								if (item !== undefined) setSelectedName(item.name)
							} else {
								setSelectedName((previous) => {
									if (previous !== null && items.some((candidate) => candidate.name === previous)) {
										return previous
									}
									followLatest.current = true
									return items[0]?.name ?? null
								})
							}
						} catch (error) {
							setFailure(true)
							setState((previous) => ({ ...previous, phase: 'ready' }))
						}
					}, [])

					React.useEffect(() => {
						let cancelled = false
						const tick = () => {
							if (cancelled) return
							if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return
							void load()
						}
						void load()
						const interval = setInterval(tick, POLL_MS)
						const onVisibility = () => {
							if (typeof document !== 'undefined' && document.visibilityState === 'visible') void load()
						}
						document?.addEventListener?.('visibilitychange', onVisibility)
						return () => {
							cancelled = true
							clearInterval(interval)
							document?.removeEventListener?.('visibilitychange', onVisibility)
						}
					}, [load])

					const selected =
						state.items.find((candidate) => candidate.name === selectedName) ??
						state.items[0] ??
						null

					const onPick = (name) => {
						followLatest.current = false
						setManualSelection(true)
						setSelectedName(name)
					}

					const header = h(
						'div',
						{ className: 'vs-header' },
						h(
							'div',
							{ className: 'vs-heading' },
							h('div', { className: 'vs-title' }, t('title', ZH.title)),
							h('div', { className: 'vs-subtitle' }, t('subtitle', ZH.subtitle)),
						),
						h(
							'button',
							{ type: 'button', className: 'vs-refresh', onClick: () => void load() },
							t('refresh', ZH.refresh),
						),
					)

					let stage
					if (selected === null) {
						stage = h(
							'div',
							{ className: 'vs-stage' },
							h(
								'div',
								{ className: 'vs-empty' },
								h('div', { className: 'vs-empty-title' }, failure ? t('error', ZH.error) : t('emptyTitle', ZH.emptyTitle)),
								h('div', { className: 'vs-empty-hint' }, t('emptyHint', ZH.emptyHint)),
								failure
									? h(
											'button',
											{
												type: 'button',
												className: 'vs-refresh',
												onClick: () => {
													setFailure(false)
													void load()
												},
											},
											t('retry', ZH.retry),
										)
									: null,
							),
						)
					} else if (selected.kind === 'image') {
						stage = h(
							'div',
							{ className: 'vs-stage' },
							h('img', {
								key: selected.name,
								className: 'vs-frame',
								src: selected.url,
								alt: selected.name,
							}),
						)
					} else {
						stage = h(
							'div',
							{ className: 'vs-stage' },
							h('video', {
								key: selected.name,
								className: 'vs-video',
								src: selected.url,
								controls: true,
								autoPlay: true,
								playsInline: true,
								preload: 'metadata',
								onError: (event) => {
									const target = event?.currentTarget
									if (target && target.parentElement) {
										target.dataset.failed = 'true'
									}
								},
							}),
						)
					}

					const info =
						selected === null
							? null
							: h(
									'div',
									{ className: 'vs-info' },
									h('span', { className: 'vs-badge' }, selected.kind === 'image' ? t('image', ZH.image) : t('video', ZH.video)),
									h('span', { className: 'vs-name', title: selected.name }, selected.name),
									h('span', { className: 'vs-meta' }, `${formatRelative(selected.mtimeMs)} · ${formatSize(selected.size)}`),
								)

					const list = state.items.length > 1
						? h(
								'div',
								{ className: 'vs-list' },
								...state.items.map((item) =>
									h(
										'button',
										{
											type: 'button',
											key: item.name,
											className: 'vs-item',
											'data-active': String(item.name === selected?.name),
											onClick: () => onPick(item.name),
											title: item.name,
										},
										h('span', { className: 'vs-item-name' }, item.name),
										h('span', { className: 'vs-item-meta' }, `${formatRelative(item.mtimeMs)} · ${formatSize(item.size)}`),
									),
								),
							)
						: null

					const footer = h(
						'div',
						{ className: 'vs-footer' },
						h('span', null, `${t('dirLabel', ZH.dirLabel)}:`),
						h('span', { className: 'vs-footer-path', title: state.dir }, state.dir || 'video-studio/previews'),
					)

					return h(
						'div',
						{ className: 'vs-page' },
						h('style', null, CSS),
						header,
						info,
						stage,
						list,
						footer,
					)
				}

				const disposers = []
				if (locale && typeof locale.register === 'function') {
					try {
						disposers.push(locale.register('video-studio', 'zh', ZH))
						disposers.push(locale.register('video-studio', 'en', EN))
					} catch {}
				}

				disposers.push(
					slots.inject('main', () =>
						slots.register({ name: 'main', key: PANEL_ID }, VideoStudioPanel),
					),
				)
				disposers.push(
					slots.inject('sidebar.panellist', () =>
						slots.register(
							{
								name: 'sidebar.panellist',
								id: PANEL_ID,
								order: 20,
								label: () => t('title', ZH.title),
							},
							VideoStudioIcon,
						),
					),
				)

				ctx.effect(
					() => () => {
						for (const dispose of disposers.reverse()) {
							try {
								dispose()
							} catch {}
						}
					},
					'video-studio.client',
				)
				return undefined
			},
		}
	},
})
