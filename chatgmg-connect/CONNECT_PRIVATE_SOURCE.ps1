# ChatGMG Windows -> PRIVATE GitHub source sync, one-time setup.
# Does NOT modify Cloudflare, Telegram, D1, or any existing production deployment.
# GitHub account auth occurs via official web flow; never paste API tokens in chat.
$ErrorActionPreference = 'Stop'
$repo = 'cryptostee1/chatgmg-production-source'
$folder = Join-Path $env:USERPROFILE 'Documents\chatgmg_private_repo_20261116'
$gh = 'C:\Users\grigo\AppData\Local\Microsoft\WinGet\Packages\GitHub.cli_Microsoft.Winget.Source_8wekyb3d8bbwe\bin\gh.exe'
$git = 'C:\Program Files\Git\cmd\git.exe'
try {
  if (-not (Test-Path $folder)) { throw "Prepared source directory not found: $folder" }
  if (-not (Test-Path (Join-Path $folder '.git'))) { throw 'Prepared Git repository missing' }
  if (-not (Test-Path $gh)) {
    $x = Get-Command 'gh.exe' -ErrorAction SilentlyContinue
    if (-not $x) { throw 'GitHub CLI missing; install with winget install --id GitHub.cli --exact' }
    $gh = $x.Source
  }
  if (-not (Test-Path $git)) {
    $x = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if (-not $x) { throw 'Git missing' }
    $git = $x.Source
  }
  # WinGet Git may be installed but not on PATH of an older PowerShell session.
  # Ensure gh auth setup-git can resolve git.exe without requiring reboot.
  $gitCmd = Split-Path -Parent $git
  if (($env:Path -split ';') -notcontains $gitCmd) { $env:Path = $gitCmd + ';' + $env:Path }
  Set-Location $folder
  Write-Host '1/6 Verifying ChatGMG files (no upload yet)...'
  node --check '.\deploy\_worker.js'
  if ($LASTEXITCODE -ne 0) { throw 'Worker syntax check failed' }
  node '.\tools\ci-verify.mjs'
  if ($LASTEXITCODE -ne 0) { throw 'Security / source preflight failed: no upload' }
  $files = @(& $git ls-files)
  if ($LASTEXITCODE -ne 0 -or $files.Count -lt 100) { throw 'Git source manifest missing or incomplete' }
  foreach ($file in $files) {
    if ($file -match '(^|/)(\.env|\.dev\.vars|credentials\.json|secrets\.json)' -or
        $file -match '\.(pem|key|p12|pfx)$') { throw "Forbidden credential-like file: $file" }
  }
  Write-Host ('Checked '+$files.Count+' tracked files') -ForegroundColor Green

  Write-Host '2/6 Confirming GitHub sign-in...'
  $ErrorActionPreference = 'Continue'
  & $gh auth status --hostname github.com *> $null
  $needsLogin = ($LASTEXITCODE -ne 0)
  $ErrorActionPreference = 'Stop'
  if ($needsLogin) {
    Write-Host 'A GitHub page will open. Authorize GitHub CLI in your browser.'
    & $gh auth login --hostname github.com --git-protocol https --web --clipboard --scopes repo,workflow
    if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in was not completed' }
  }
  & $gh auth setup-git
  if ($LASTEXITCODE -ne 0) { throw 'Could not configure Git authentication' }
  $login = (& $gh api user --jq '.login').Trim()
  if ($LASTEXITCODE -ne 0 -or $login -ne 'cryptostee1') {
    throw "Signed in as '$login' instead of 'cryptostee1': stopped"
  }

  Write-Host '3/6 Checking private repository...'
  $ErrorActionPreference = 'Continue'
  $visibility = & $gh repo view $repo --json isPrivate --jq '.isPrivate' 2>$null
  $repoMissing = ($LASTEXITCODE -ne 0)
  $ErrorActionPreference = 'Stop'
  if ($repoMissing) {
    Write-Host 'Creating private repository without uploading files...'
    & $gh repo create $repo --private --source . --remote origin --description 'ChatGMG Cloudflare Pages source and guarded release workflow'
    if ($LASTEXITCODE -ne 0) { throw 'Could not create private repository' }
  }

  Write-Host '4/6 Verifying privacy before upload...'
  $isPrivate = (& $gh repo view $repo --json isPrivate --jq '.isPrivate').Trim()
  if ($LASTEXITCODE -ne 0 -or $isPrivate -ne 'true') {
    throw 'Repository is not confirmed private: upload blocked'
  }
  $ErrorActionPreference = 'Continue'
  $remote = & $git remote get-url origin 2>$null
  $remoteMissing = ($LASTEXITCODE -ne 0)
  $ErrorActionPreference = 'Stop'
  if ($remoteMissing -or -not $remote) {
    & $git remote add origin "https://github.com/$repo.git"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to add Git remote' }
  } elseif ($remote -notlike "*github.com/$repo*") {
    throw "Wrong Git remote: $remote. Upload blocked"
  }

  Write-Host '5/6 Uploading verified source to private GitHub...'
  & $git push -u origin main
  if ($LASTEXITCODE -ne 0) { throw 'Git upload failed' }

  Write-Host '6/6 Checking source is available on GitHub...'
  $head = (& $gh api "repos/$repo/commits/main" --jq '.sha').Trim()
  if ($LASTEXITCODE -ne 0 -or -not $head) { throw 'Upload not yet visible in GitHub' }
  Write-Host ''
  Write-Host 'CHATGMG_PRIVATE_SOURCE_SYNC_SUCCESS' -ForegroundColor Green
  Write-Host "Repository: https://github.com/$repo"
  Write-Host "Commit: $head"
  Write-Host 'Cloudflare / production / Telegram were NOT changed.'
} catch {
  Write-Host ''
  Write-Host 'CHATGMG_SETUP_INCOMPLETE' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host 'No Cloudflare production deployment was attempted.'
  exit 1
}
