/**
 * 投送会话钉选（pin）——纯函数，无副作用，便于离线自测。
 *
 * 要解决的现场问题：宿主收件箱桥原来只按「最近活跃的根会话」挑投递目标。
 * PC1 同时开着多个会话时，对端消息会投给「刚说过话」的那个会话，而不是真正在
 * 等消息的任务会话（2026-11-24 实测：消息投进 session-3960517d，任务会话收不到）。
 *
 * 方案：技能一加载就调 tl-pin.ps1，把当前会话 id（环境变量 DSH_SESSION_ID）写进
 * state/pinned-session.json；桥优先投给被钉选的会话，钉选的会话关掉了才回退旧逻辑。
 *
 * 为什么不用宿主事件：DSH 0.2.2-rc.5 的插件面只暴露 agents 服务，没有「某会话加载了
 * 技能」这类事件。按本插件第一条纪律「不猜 API」，走文件契约——两侧都只看磁盘。
 *
 * @module dsh-vivado-team-link/pin
 */
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

/** 钉选文件的文件名（与 tl-pin.ps1 写的那份一致）。 */
export const PIN_FILENAME = 'pinned-session.json'

/**
 * 钉选文件的绝对路径。
 * @param stateDir - 插件的 state 目录。
 * @returns 绝对路径。
 */
export function pinPath(stateDir) {
  return join(stateDir, PIN_FILENAME)
}

/**
 * 读钉选文件。缺文件 / 坏 JSON / 没有 sessionId 一律当作「没有钉选」，绝不抛错。
 * @param stateDir - 插件的 state 目录。
 * @returns `{ sessionId, at?, source?, host?, profile?, note? }` 或 undefined。
 */
export function readPin(stateDir) {
  try {
    const path = pinPath(stateDir)
    if (!existsSync(path)) return undefined
    // PowerShell 5.1 的 Set-Content -Encoding UTF8 会写 BOM，不剥掉 JSON.parse 会失败。
    const parsed = JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''))
    if (parsed === null || typeof parsed !== 'object') return undefined
    const sessionId = typeof parsed.sessionId === 'string' ? parsed.sessionId.trim() : ''
    if (!sessionId) return undefined
    return { ...parsed, sessionId }
  } catch {
    return undefined
  }
}

/**
 * 在 agents.list() 的结果里找出被钉选的那个 agent。
 *
 * 匹配键是 `agent.id`：实测 bridged 日志里 agent=session-xxxx，与 DSH_SESSION_ID 同形同值。
 * 不匹配 `session.id`（不同版本形状不稳），也不按标题/时间猜。
 *
 * @param list - agents.list() 的返回值（可能是任何东西）。
 * @param pin - readPin() 的返回值。
 * @returns 命中的 agent，或 undefined。
 */
export function findPinnedAgent(list, pin) {
  if (!pin || typeof pin.sessionId !== 'string' || pin.sessionId === '') return undefined
  const rows = Array.isArray(list) ? list : []
  for (const agent of rows) {
    let id = ''
    try {
      id = String(agent?.id ?? '')
    } catch {
      id = ''
    }
    if (id !== '' && id === pin.sessionId) return agent
  }
  return undefined
}
