#!/usr/bin/env node
/**
 * pin（投送会话钉选）离线自测 —— 不碰运行中的插件副本。
 *
 * 两段：
 *   A. lib/pin.js 纯函数：缺文件 / 坏 JSON / BOM / 命中 / 未命中 / 脏 list 不抛错。
 *   B. 真桥：把 lib/ 拷到临时目录，import 真的 apply()，用伪 agents 服务跑 tick，
 *      验 ① 无钉选时投「最近活跃」 ② 有钉选时投钉选会话 ③ 钉选会话不在时回退。
 *
 * 用法：node tools/pin-selftest.mjs
 * 退出码：0 全过；1 有失败。
 */
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO = dirname(HERE)

let failures = 0
function check(name, ok, extra = '') {
  if (ok) {
    console.log(`  PASS ${name}`)
  } else {
    failures += 1
    console.log(`  FAIL ${name}${extra ? ` :: ${extra}` : ''}`)
  }
}

// ---------- A. 纯函数 ----------
const { findPinnedAgent, readPin, pinPath } = await import(pathToFileURL(join(REPO, 'lib', 'pin.js')).href)
console.log('A. lib/pin.js 纯函数')

const emptyDir = mkdtempSync(join(tmpdir(), 'tl-pin-empty-'))
check('缺文件 -> undefined', readPin(emptyDir) === undefined)

const bomDir = mkdtempSync(join(tmpdir(), 'tl-pin-bom-'))
writeFileSync(pinPath(bomDir), '\uFEFF' + JSON.stringify({ sessionId: 'session-AAA', source: 't' }), 'utf8')
check('带 BOM 也能读', readPin(bomDir)?.sessionId === 'session-AAA')

const badDir = mkdtempSync(join(tmpdir(), 'tl-pin-bad-'))
writeFileSync(pinPath(badDir), '{ not json', 'utf8')
check('坏 JSON -> undefined（不抛错）', readPin(badDir) === undefined)

const noIdDir = mkdtempSync(join(tmpdir(), 'tl-pin-noid-'))
writeFileSync(pinPath(noIdDir), JSON.stringify({ sessionId: '   ' }), 'utf8')
check('sessionId 空白 -> undefined', readPin(noIdDir) === undefined)

const pin = { sessionId: 'session-AAA' }
const agentA = { id: 'session-AAA' }
const agentB = { id: 'session-BBB' }
check('命中按 agent.id', findPinnedAgent([agentB, agentA], pin) === agentA)
check('未命中 -> undefined', findPinnedAgent([agentB], pin) === undefined)
check('list 不是数组也不抛错', findPinnedAgent(undefined, pin) === undefined)
check('脏元素不抛错', findPinnedAgent([null, 42, { id: 'session-AAA' }], pin)?.id === 'session-AAA')

for (const d of [emptyDir, bomDir, badDir, noIdDir]) rmSync(d, { recursive: true, force: true })

// ---------- B. 真桥 ----------
console.log('B. lib/index.js 收件箱桥（真实 apply + 伪 agents）')

/** 建一个临时 bundle：拷 lib/，建 state/tasks，投一条任务。 */
function makeBundle(taskId, text) {
  const root = mkdtempSync(join(tmpdir(), 'tl-bridge-'))
  cpSync(join(REPO, 'lib'), join(root, 'lib'), { recursive: true })
  mkdirSync(join(root, 'state', 'tasks'), { recursive: true })
  writeFileSync(
    join(root, 'state', 'tasks', `${taskId}.json`),
    JSON.stringify({ history: [{ parts: [{ text }] }], status: { state: 'submitted' } }),
    'utf8',
  )
  return root
}

/** 伪 agents：id + 根会话 + idle + updatedAt + inbox.prepend 记账。 */
function makeAgents(order) {
  return order.map((spec, i) => {
    const agent = {
      id: spec.id,
      status: 'idle',
      session: { delegationDepth: 0, updatedAt: new Date(2026, 0, 1, 0, i) },
      pushed: [],
      inbox: {
        prepend(kind, msg) {
          agent.pushed.push({ kind, msg })
        },
      },
    }
    return agent
  })
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

/**
 * 跑一次桥：返回被投递的 agent id（或 undefined）。
 * @param pinSessionId 写进 pinned-session.json 的会话；undefined = 不写文件。
 */
async function runBridge({ pinSessionId, agents }) {
  const root = makeBundle(`task-${Math.random().toString(16).slice(2, 10)}`, 'PC2 TEAM-REPORT 正文')
  if (pinSessionId !== undefined) {
    writeFileSync(join(root, 'state', 'pinned-session.json'), JSON.stringify({ version: 1, sessionId: pinSessionId, source: 'selftest' }), 'utf8')
  }
  const logLines = []
  const ctx = {
    logger: { info: (m) => logLines.push(m), warn: (m) => logLines.push(m), error: (m) => logLines.push(m) },
    agents: { list: () => agents },
  }
  const mod = await import(pathToFileURL(join(root, 'lib', 'index.js')).href + `?t=${Date.now()}`)
  mod.apply(ctx, {})
  await sleep(2200)
  const diag = existsSync(join(root, 'state', 'inbox-bridge.log')) ? readFileSync(join(root, 'state', 'inbox-bridge.log'), 'utf8') : ''
  const hit = agents.find((a) => a.pushed.length > 0)
  rmSync(root, { recursive: true, force: true })
  return { agentId: hit?.id, diag }
}

// ① 无钉选：最近活跃（列表里 updatedAt 最大的那个）胜出。
{
  const agents = makeAgents([{ id: 'session-OLD' }, { id: 'session-RECENT' }])
  const r = await runBridge({ agents })
  check('无钉选 -> 投最近活跃 session-RECENT', r.agentId === 'session-RECENT', `实际=${r.agentId}`)
  check('无钉选 -> 日志记 pin: none', /pin: 未设置/.test(r.diag), r.diag.trim().split('\n').pop())
}

// ② 有钉选：钉的是「旧」会话，仍应投它（这正是修复点）。
{
  const agents = makeAgents([{ id: 'session-PINNED' }, { id: 'session-RECENT' }])
  const r = await runBridge({ pinSessionId: 'session-PINNED', agents })
  check('有钉选 -> 投 session-PINNED（压过最近活跃）', r.agentId === 'session-PINNED', `实际=${r.agentId}`)
  check('有钉选 -> 日志记 pin: hit', /pin: hit session-PINNED/.test(r.diag), r.diag.trim().split('\n').pop())
}

// ③ 钉选的会话已经不在了：回退最近活跃，并记 pin: miss。
{
  const agents = makeAgents([{ id: 'session-A' }, { id: 'session-B' }])
  const r = await runBridge({ pinSessionId: 'session-GONE', agents })
  check('钉选失效 -> 回退最近活跃 session-B', r.agentId === 'session-B', `实际=${r.agentId}`)
  check('钉选失效 -> 日志记 pin: miss', /pin: miss session-GONE/.test(r.diag), r.diag.trim().split('\n').pop())
}

console.log('')
if (failures === 0) {
  console.log('RESULT: PASS（A+B 全过）')
  process.exit(0)
} else {
  console.log(`RESULT: FAIL（${failures} 项失败）`)
  process.exit(1)
}
