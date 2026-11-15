# GITONAS CONNECT -- free Telegram setup for the authorized MATTHAIOS Windows computer.
# PUBLIC SCRIPT: no credentials are embedded in this file.
# Bot token is requested locally as hidden input and is never sent to ChatGPT or GitHub.
# Scope: only the existing Cloudflare Pages project "chatgmg"; no paid APIs.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = Join-Path $env:USERPROFILE 'Documents\chatgmg_safe_20261114'
$deploy = Join-Path $project 'deploy'
$runtime = Join-Path $deploy 'gitonas\connect-runtime.mjs'
$site = 'https://chatgmg.pages.dev'
$webhook = "$site/api/gitonas-connect/webhook"
$script:token = ''
$script:webhookSecret = ''

function Read-Hidden([string]$label) {
  $secure = Read-Host -Prompt $label -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function Read-Token-Safely {
  Write-Host 'Copy the API Token from @BotFather > /mybots > your bot > API Token.'
  Write-Host 'C = Windows clipboard; H = hidden prompt. Never send token to ChatGPT.'
  $choice=(Read-Host 'Choose C or H').Trim().ToUpperInvariant()
  if($choice -eq 'C'){$raw=[string](Get-Clipboard -Raw -ErrorAction Stop)}
  elseif($choice -eq 'H'){$raw=Read-Hidden 'Bot token (hidden; right-click to paste if Ctrl+V fails)'}
  else{throw 'Choose C or H, not your bot name.'}
  $found=[regex]::Match($raw,'(?<![A-Za-z0-9_-])([0-9]{7,15}:[A-Za-z0-9_-]{25,})(?![A-Za-z0-9_-])')
  if($choice -eq 'C' -and $found.Success){try{Set-Clipboard -Value '' -ErrorAction SilentlyContinue}catch{}}
  $raw=''
  if(-not $found.Success){throw 'API Token not recognized. Do not copy @username or t.me link.'}
  return $found.Groups[1].Value
}

function RandomHex([int]$count) {
  $b = New-Object byte[] $count
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($b) } finally { $rng.Dispose() }
  return ([BitConverter]::ToString($b)).Replace('-','').ToLowerInvariant()
}
function Tg([string]$method,$body=$null) {
  $url = 'https://api.telegram.org/bot'+$script:token+'/'+$method
  if ($null -eq $body) {
    return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20
  }
  $json = ConvertTo-Json -InputObject $body -Compress -Depth 8
  return Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 25
}
function Wrangler([string]$args, [string]$stdin='') {
  $npx = (Get-Command npx.cmd -ErrorAction Stop).Source
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $npx
  $psi.Arguments = '--yes wrangler '+$args
  $psi.WorkingDirectory = $project
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = New-Object Diagnostics.Process
  $p.StartInfo = $psi
  try {
    [void]$p.Start()
    if ($stdin) { $p.StandardInput.WriteLine($stdin) }
    $p.StandardInput.Close()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    if (-not $p.WaitForExit(180000)) {
      try { $p.Kill() } catch {}
      throw 'Cloudflare command timed out.'
    }
    if ($p.ExitCode -ne 0) {
      $details = ($stdout+' '+$stderr)
      if ($script:token) { $details=$details.Replace($script:token,'[REDACTED]') }
      if ($script:webhookSecret) { $details=$details.Replace($script:webhookSecret,'[REDACTED]') }
      throw ('Wrangler failed, exit code '+$p.ExitCode+': '+$details.Substring(0,[Math]::Min($details.Length,500)))
    }
    return $stdout
  } finally { $p.Dispose() }
}
function Save-Secret([string]$name,[string]$value) {
  Write-Host ('Saving encrypted Cloudflare secret: '+$name)
  $null = Wrangler ('pages secret put '+$name+' --project-name chatgmg') $value
}
try {
  Write-Host '=== GITONAS CONNECT FREE SETUP ===' -ForegroundColor Cyan
  if (-not (Test-Path $runtime)) { throw ('Missing ChatGMG source on this PC: '+$runtime) }
  if (-not (Test-Path (Join-Path $deploy '_worker.js'))) { throw 'Missing ChatGMG Pages Worker.' }
  if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Node.js not installed.' }
  if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) { throw 'Node.js npm/npx not installed.' }

  Write-Host 'Use the bot you already created; do not send its token to ChatGPT.'
  $me=$null
  for($attempt=1;$attempt -le 3;$attempt++){
    try{
      $script:token=Read-Token-Safely
      $me=Tg 'getMe'
      if($me.ok -and $me.result.is_bot){break}
    } catch {
      Write-Host ('Attempt '+$attempt+': token not verified. Copy API Token again.') -ForegroundColor Yellow
      $script:token=''
    }
  }
  if(-not $me -or -not $me.ok -or -not $me.result.is_bot) {
    throw 'Telegram bot token verification failed. Check @BotFather /mybots > API Token.'
  }
  $username = [string]$me.result.username
  if ($username -notmatch '^[A-Za-z][A-Za-z0-9_]{4,31}$') { throw 'Invalid bot username.' }
  Write-Host ('Verified bot: @'+$username) -ForegroundColor Green

  $info=Tg 'getWebhookInfo'
  if ($info.result.url -and $info.result.url -ne $webhook) {
    throw ('This bot already has a different webhook: '+$info.result.url)
  }

  $pair='connect-'+(RandomHex 6)
  Write-Host 'Now open your bot in Telegram:' -ForegroundColor Yellow
  Write-Host ('https://t.me/'+$username)
  Write-Host ('SEND EXACTLY THIS MESSAGE: /start '+$pair) -ForegroundColor Cyan
  Write-Host 'This identifies your private operator chat, not a public group.'
  $chatId=''
  for($i=0;$i -lt 45;$i++){
    $updates=Tg 'getUpdates'
    foreach($item in @($updates.result)){
      if(-not $item -or -not $item.message){continue}
      $m=$item.message
      if ($m.chat.type -eq 'private' -and [string]$m.text -ceq ('/start '+$pair) -and [string]$m.from.id -eq [string]$m.chat.id) {
        $chatId=[string]$m.chat.id;break
      }
    }
    if($chatId){break}
    Start-Sleep -Seconds 3
  }
  if ($chatId -notmatch '^\d{5,20}$') {
    throw 'No matching pairing message received. No Cloudflare settings were changed.'
  }
  $script:webhookSecret=RandomHex 32
  Write-Host 'Pairing confirmed.' -ForegroundColor Green

  Save-Secret 'GITONAS_TG_BOT_TOKEN' $script:token
  Save-Secret 'GITONAS_TG_WEBHOOK_SECRET' $script:webhookSecret
  Save-Secret 'GITONAS_TG_ADMIN_CHAT_ID' $chatId
  Save-Secret 'GITONAS_TG_USERNAME' $username
  Write-Host 'Deploying tested files ONLY to the existing chatgmg Pages project...'
  $null=Wrangler ('pages deploy "'+$deploy+'" --project-name chatgmg --branch main')

  $ready=$false
  for($i=0;$i -lt 12;$i++){
    try {
      $status=Invoke-RestMethod -Uri "$site/api/gitonas-connect/status" -Method Get -TimeoutSec 15
      if ($status.lead_delivery_ready -eq $true -and $status.bot_username -eq $username) { $ready=$true;break }
    } catch {}
    Start-Sleep -Seconds 3
  }
  if (-not $ready) {
    throw 'Site did not confirm live bot connection. Secrets may be saved, but webhook was not set.'
  }
  $reg=Tg 'setWebhook' @{url=$webhook;secret_token=$script:webhookSecret;allowed_updates=@('message');max_connections=3;drop_pending_updates=$false}
  if(-not $reg.ok){throw 'Telegram webhook registration failed.'}
  $check=Tg 'getWebhookInfo'
  if($check.result.url -ne $webhook){throw 'Telegram webhook URL verification failed.'}
  $sent=Tg 'sendMessage' @{chat_id=$chatId;text='GITONAS CONNECT is configured. Please send /help to test the webhook.'}
  if(-not $sent.ok){throw 'Telegram direct test message failed.'}
  Write-Host ''
  Write-Host 'SUCCESS — GITONAS CONNECT TELEGRAM LINKED!' -ForegroundColor Green
  Write-Host ('BOT: https://t.me/'+$username)
  Write-Host 'SITE: https://chatgmg.com/gitonas/connect/'
  Write-Host 'Final test: send /help to the bot and submit one consented website enquiry.'
} catch {
  $msg=[string]$_.Exception.Message
  if($script:token){$msg=$msg.Replace($script:token,'[REDACTED]')}
  if($script:webhookSecret){$msg=$msg.Replace($script:webhookSecret,'[REDACTED]')}
  Write-Host ('SETUP NOT COMPLETE: '+$msg) -ForegroundColor Red
  Write-Host 'No payment was made. The bot is not confirmed live.'
  exit 1
} finally {
  $script:token=''
  $script:webhookSecret=''
}