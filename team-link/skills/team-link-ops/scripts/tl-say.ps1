#requires -Version 5.1
<#
.SYNOPSIS
  给对端发一条 A2A 消息（自动化任务/值班里"处理完并回复"用）。
.DESCRIPTION
  走 config.json 里的 peer.a2aUrl + peer-a2a.token（出站 token）；可用 -Peer/-TokenFile 覆盖（自测时指向本机）。
  只发一段纯文本，打印对端回执的 task id 与回复文本。
  正文用 -Text 直接给，或 -TextFile 指向一个 UTF-8 文件（长报告推荐，避开命令行长度限制）。
  编码：**请求体按 UTF-8 字节发**。Windows PowerShell 5.1 的 Invoke-RestMethod 在 -Body 是字符串时
  会用 ASCII 编码，中文会**每个字变成一个 ?**（2026-11-24 实测踩到，PC2 的中文 TEAM-REPORT 全成 ????），
  所以这里显式 [Text.Encoding]::UTF8.GetBytes()。
  退出码：0=已送达并收到回复；2=通道不可用；5=认证失败(401)；6=参数错。
.EXAMPLE
  powershell -NoProfile -File scripts\tl-say.ps1 -Text "TEAM-REPORT ..."
.EXAMPLE
  # 自测：发给自己
  powershell -NoProfile -File scripts\tl-say.ps1 -Peer http://127.0.0.1:7310/ -TokenFile state\a2a.token -Text "[ping] self"
#>
[CmdletBinding()]
param(
  [string]$Text = '',
  [string]$TextFile = '',
  [string]$Bundle = '',
  [string]$Peer = '',
  [string]$TokenFile = '',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [int]$TimeoutSec = 15
)
$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($TextFile)) {
  if (-not (Test-Path -LiteralPath $TextFile)) { Write-Host ('FAIL -TextFile 不存在: ' + $TextFile); exit 6 }
  # 会写 BOM 的编辑器（记事本 / Set-Content -Encoding UTF8）要去掉，否则 BOM 会进正文。
  $Text = ((Get-Content -Raw -Encoding UTF8 -LiteralPath $TextFile) -replace '^\uFEFF', '').TrimEnd()
}
if ([string]::IsNullOrWhiteSpace($Text)) { Write-Host 'FAIL -Text / -TextFile 必须给一个（正文不能为空）'; exit 6 }
if ([string]::IsNullOrWhiteSpace($Bundle)) { $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link' }
$cfgPath = Join-Path $Bundle 'state\config.json'
if (-not (Test-Path -LiteralPath $cfgPath)) { Write-Host ("FAIL 找不到 " + $cfgPath); exit 2 }
$cfg = (Get-Content -Raw -Encoding UTF8 -LiteralPath $cfgPath) -replace '^\uFEFF','' | ConvertFrom-Json

$endpoint = if ($Peer) { $Peer } else { [string]$cfg.peer.a2aUrl }
if ([string]::IsNullOrWhiteSpace($endpoint)) { Write-Host "FAIL 未配置对端地址（peer.a2aUrl 为空）：先跑 tl-sync.ps1 -PeerHost <ip>"; exit 2 }

# token：显式 > 对端出站 token > 报错
$tf = $TokenFile
if ([string]::IsNullOrWhiteSpace($tf)) { $tf = [string]$cfg.peer.a2a.tokenFile }
if ([string]::IsNullOrWhiteSpace($tf)) { Write-Host 'FAIL 没有可用的 token 文件'; exit 5 }
if (-not [System.IO.Path]::IsPathRooted($tf)) {
  $c1 = Join-Path $Bundle $tf
  $c2 = Join-Path (Join-Path $Bundle 'state') $tf
  $tf = if (Test-Path -LiteralPath $c1) { $c1 } else { $c2 }
}
if (-not (Test-Path -LiteralPath $tf)) { Write-Host ("FAIL token 文件不存在: " + $tf); exit 5 }
$token = (Get-Content -Raw -LiteralPath $tf -Encoding UTF8).Trim()
if ([string]::IsNullOrWhiteSpace($token)) { Write-Host 'FAIL token 文件为空'; exit 5 }

$payload = [ordered]@{
  jsonrpc = "2.0"
  id = 1
  method = "message/send"
  params = [ordered]@{
    message = [ordered]@{
      kind = "message"
      role = "user"
      messageId = [guid]::NewGuid().ToString()
      parts = @(@{ kind = "text"; text = $Text })
    }
  }
} | ConvertTo-Json -Depth 10 -Compress

# 必须发字节：PS 5.1 的 Invoke-RestMethod 对字符串 body 按 ASCII 编码，中文会每个字变一个 "?"。
$utf8 = New-Object System.Text.UTF8Encoding($false)
$bodyBytes = $utf8.GetBytes($payload)

try {
  $resp = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType "application/json; charset=utf-8" -Headers @{ Authorization = ("Bearer " + $token) } -Body $bodyBytes -TimeoutSec $TimeoutSec
} catch {
  $msg = $_.Exception.Message.Split([char]10)[0]
  if ($_.Exception.Response -and ([int]$_.Exception.Response.StatusCode -eq 401)) { Write-Host ("FAIL 401 认证失败：" + $msg); exit 5 }
  Write-Host ("FAIL 通道不可用：" + $msg)
  exit 2
}

$id = ""
try { $id = [string]$resp.result.id } catch { }
$state = ""
try { $state = [string]$resp.result.status.state } catch { }
$reply = ""
try { $reply = [string]$resp.result.artifacts[0].parts[0].text } catch { }
if (-not $id) { Write-Host "FAIL 对端未返回 task（可能是认证明明通过但协议不符）"; exit 2 }

Write-Host ("PASS 对端服务已落盘 task=" + $id.Substring(0, [Math]::Min(8, $id.Length)) + " state=" + $state + "（不代表对端 agent 已读）")
if ($reply) { Write-Host ("     对端回执: " + $reply.Substring(0, [Math]::Min(160, $reply.Length))) }
exit 0
