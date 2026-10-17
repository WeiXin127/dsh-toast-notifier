/**
 * dsh-toast-notifier host half.
 *
 * Listens to the application's events directly (host-side, no browser half
 * needed) and pops a system-level always-on-top floating window for each
 * notification. The window is a separate PowerShell(WPF) process — a native
 * topmost frameless window that escapes the DSH window, spans monitors, and
 * sits above other applications (like a QQ message popup).
 */
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-toast-notifier'

const here = dirname(fileURLToPath(import.meta.url)) // .../lib
const SCRIPT = join(here, '..', 'toast.ps1')
const DATA_DIR = join(homedir(), '.dsh', 'dsh-toast-notifier')

function ensureDataDir() {
  if (!existsSync(DATA_DIR)) {
    try { mkdirSync(DATA_DIR, { recursive: true }) } catch (_) {}
  }
}

let seq = 0
function showToast(kind, title, body) {
  try {
    ensureDataDir()
    const contentFile = join(DATA_DIR, `content-${Date.now()}-${seq++}.json`)
    const positionFile = join(DATA_DIR, 'position.json')
    writeFileSync(contentFile, JSON.stringify({ kind, title, body }), 'utf8')
    const child = spawn(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT, contentFile, positionFile],
      { stdio: 'inherit', windowsHide: true },
    )
    child.unref()
  } catch (error) {
    console.error('[dsh-toast-notifier] showToast failed:', error)
  }
}

function approvalBody(request) {
  try {
    if (request && typeof request.toolName === 'string' && request.toolName) {
      return `工具 ${request.toolName} 请求权限执行`
    }
  } catch (_) {}
  return '有一个权限请求等待处理'
}

function questionBody(request) {
  try {
    const qs = request && request.questions
    if (Array.isArray(qs) && qs.length > 0) {
      const first = qs[0]
      if (first && typeof first.question === 'string' && first.question) return first.question
      if (first && typeof first.header === 'string' && first.header) return first.header
    }
  } catch (_) {}
  return '有一个问题等待你的回答'
}

export function apply(ctx) {
  // Task completion + errors (emit events).
  ctx.on('api-session/status', (sessionId, running) => {
    if (!running) {
      showToast('done', '任务完成', sessionId ? `会话 ${String(sessionId)} 的任务已结束` : '任务已结束')
    }
  })
  ctx.on('api-session/error', (sessionId, message) => {
    showToast('error', '任务出错', message ? String(message) : `会话 ${String(sessionId)} 发生错误`)
  })

  // Permission requests (waterfall — observe then delegate via next()).
  ctx.on('approval/request', (request, next) => {
    showToast('warn', '权限请求', approvalBody(request))
    return next()
  })
  ctx.on('user-questions/request', (request, next) => {
    showToast('question', '需要你回答', questionBody(request))
    return next()
  })
}
