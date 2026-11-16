# ChatGMG Clarity v1 — preview-only deployment via ALREADY authenticated Wrangler.
# No API tokens required. No production deploy. No changes to other domains or Telegram secrets.
$ErrorActionPreference = 'Stop'
$branch = 'feat/chatgmg-unified-home-20261116'
$project = 'chatgmg'
$repository = Join-Path $env:USERPROFILE 'Documents\chatgmg_private_repo_20261116'
$git = 'C:\Program Files\Git\cmd\git.exe'
try {
  Write-Host 'CHATGMG SAFE PREVIEW — current production stays unchanged' -ForegroundColor Cyan
  if (-not (Test-Path $git)) {
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { throw 'Git missing. Git was installed earlier: check C:\Program Files\Git\cmd\git.exe' }
    $git = $cmd.Source
  }
  if (-not (Test-Path (Join-Path $repository '.git'))) {
    throw ('Prepared local private repository missing: '+$repository)
  }
  if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) {
    throw 'Node/npm missing from current PowerShell PATH'
  }
  Set-Location $repository
  $remote = (& $git remote get-url origin).Trim()
  if ($LASTEXITCODE -ne 0 -or $remote -notlike '*cryptostee1/chatgmg-production-source*') {
    throw ('Wrong git remote: '+$remote)
  }
  Write-Host '1/4 Fetching reviewed Clarity v1 from your private GitHub...'
  & $git fetch --no-tags origin "refs/heads/feat/chatgmg-unified-home-20261116:refs/remotes/origin/feat/chatgmg-unified-home-20261116"
  if ($LASTEXITCODE -ne 0) { throw 'Git fetch failed — GitHub access is not ready' }
  $commit = (& $git rev-parse "refs/remotes/origin/feat/chatgmg-unified-home-20261116").Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$') {
    throw 'GitHub commit could not be resolved'
  }
  $previewFolder = Join-Path $env:USERPROFILE ("Documents\chatgmg_preview_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
  Write-Host '2/4 Creating separate preview checkout (not replacing your current website files)...'
  & $git worktree add --detach "$previewFolder" "$commit"
  if ($LASTEXITCODE -ne 0) { throw 'Could not create separate preview worktree' }
  Set-Location $previewFolder
  Write-Host '3/4 Validating downloaded source locally...'
  foreach ($file in @('deploy\index.html','deploy\_worker.js','deploy\gitonas\connect-runtime.mjs','deploy\clarity-v1.css','tools\clarity-verify.mjs','wrangler.toml')) {
    if (-not (Test-Path $file)) { throw ('Source missing: '+$file) }
  }
  & node --check '.\deploy\_worker.js'
  if ($LASTEXITCODE -ne 0) { throw 'Worker syntax validation failed' }
  & node --check '.\tools\clarity-verify.mjs'
  if ($LASTEXITCODE -ne 0) { throw 'UI test syntax validation failed' }
  & node '.\tools\ci-verify.mjs'
  if ($LASTEXITCODE -ne 0) { throw 'Source preflight failed; no deploy' }
  & node '.\tools\clarity-verify.mjs'
  if ($LASTEXITCODE -ne 0) { throw 'Clarity UI regression failed; no deploy' }
  Write-Host '4/4 Deploying ONLY non-production Pages branch gh-preview...' -ForegroundColor Cyan
  & npx.cmd --yes wrangler@4 pages deploy '.\deploy' --project-name $project --branch gh-preview
  if ($LASTEXITCODE -ne 0) { throw 'Wrangler did not confirm preview deployment' }
  Write-Host ''
  Write-Host 'CHATGMG_PREVIEW_DEPLOY_SUCCESS' -ForegroundColor Green
  Write-Host ('Source commit: '+$commit)
  Write-Host ('Preview checkout: '+$previewFolder)
  Write-Host 'Open: https://gh-preview.chatgmg.pages.dev/'
  Write-Host 'Production chatgmg.com / D1 / Telegram / other domains untouched.'
  Start-Process 'https://gh-preview.chatgmg.pages.dev/'
}
catch {
  Write-Host ''
  Write-Host 'CHATGMG_PREVIEW_NOT_CONFIRMED' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host 'No production deployment was attempted.'
  exit 1
}
