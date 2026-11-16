# ChatGMG Cloudflare Pages private GitHub secrets -> PREVIEW ONLY
# This script never deploys production, changes webhook/D1 or prints a Cloudflare token.
# Review: https://github.com/cryptostee1/MatthaiosGrigoriadis/tree/main/chatgmg-connect
$ErrorActionPreference = 'Stop'
$repo = 'cryptostee1/chatgmg-production-source'
$branch = 'feat/chatgmg-unified-home-20261116'
$workflow = 'chatgmg-controlled-release.yml'
$gh = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\GitHub.cli_Microsoft.Winget.Source_8wekyb3d8bbwe\bin\gh.exe'
function Find-Gh {
  if (Test-Path $gh) { return $gh }
  $a=Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($a) { return $a.Source }
  foreach ($x in @('C:\Program Files\GitHub CLI\gh.exe','C:\Program Files (x86)\GitHub CLI\gh.exe')) {
    if (Test-Path $x) {return $x}
  }
  throw 'GitHub CLI not found; it was installed earlier. Reopen PowerShell and retry.'
}
function Set-RepoSecret {
  param([string]$Name,[string]$Value)
  if (-not $Value -or $Value.Length -lt 20) {throw ('Missing/invalid '+$Name)}
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:gh
  $psi.Arguments = "secret set $Name --repo $repo"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  $null = $proc.Start()
  $proc.StandardInput.Write($Value)
  $proc.StandardInput.Close()
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  if ($proc.ExitCode -ne 0) {
    throw ('Could not save '+$Name+' to GitHub Secrets. '+($stderr -replace '[^\x20-\x7E]',' ').Substring(0,[Math]::Min($stderr.Length,240)))
  }
  Write-Host ("GitHub secret saved: "+$Name) -ForegroundColor Green
}
try {
  $gh = Find-Gh
  Write-Host 'CHATGMG: FREE GITHUB -> CLOUDFLARE PAGES PREVIEW' -ForegroundColor Cyan
  & $gh auth status --hostname github.com *> $null
  if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI not logged in. Use gh auth login first.' }
  $viewer = (& $gh api user --jq '.login').Trim()
  if ($LASTEXITCODE -ne 0 -or $viewer -ne 'cryptostee1') {
    throw ('Wrong GitHub account: '+$viewer)
  }
  $names = @(& $gh secret list --repo $repo --json name --jq '.[].name')
  if ($LASTEXITCODE -ne 0) {throw 'Cannot read GitHub repository secrets listing'}
  if ($names -notcontains 'CLOUDFLARE_ACCOUNT_ID') {
    Write-Host ''
    Write-Host 'STEP 1/3: Copy Cloudflare Account ID (32 hexadecimal characters).' -ForegroundColor Cyan
    Write-Host 'Open the Cloudflare account dashboard. Find Account ID in Overview.'
    Start-Process 'https://dash.cloudflare.com/'
    Read-Host 'After copying Account ID, return here and press Enter' | Out-Null
    $id = (Get-Clipboard -Raw).Trim()
    if ($id -notmatch '^[a-fA-F0-9]{32}$') {
      throw 'Clipboard is not a 32-character Cloudflare Account ID. Nothing uploaded.'
    }
    Set-RepoSecret -Name 'CLOUDFLARE_ACCOUNT_ID' -Value $id
    $id=$null
    Set-Clipboard -Value ' '
  } else {
    Write-Host 'STEP 1/3: Account ID secret already present.' -ForegroundColor Green
  }
  if ($names -notcontains 'CLOUDFLARE_API_TOKEN') {
    Write-Host ''
    Write-Host 'STEP 2/3: Create a narrowly-scoped Cloudflare API token.' -ForegroundColor Cyan
    Write-Host 'Token name: ChatGMG GitHub Preview'
    Write-Host 'Permission: Account > Cloudflare Pages > Edit.'
    Write-Host 'Account resources: include only your ChatGMG Cloudflare account.'
    Write-Host 'Do NOT use the Global API Key. Do NOT post the token in a chat.'
    Start-Process 'https://dash.cloudflare.com/profile/api-tokens'
    Read-Host 'After creating the token and copying it, return here and press Enter' | Out-Null
    $token = (Get-Clipboard -Raw).Trim()
    if ($token -notmatch '^[^\s]{20,512}$') {
      throw 'Clipboard does not contain a valid-looking token. Nothing uploaded.'
    }
    Set-RepoSecret -Name 'CLOUDFLARE_API_TOKEN' -Value $token
    $token=$null
    Set-Clipboard -Value ' '
  } else {
    Write-Host 'STEP 2/3: Cloudflare token secret already present.' -ForegroundColor Green
  }
  Write-Host ''
  Write-Host 'STEP 3/3: Start a GitHub Actions PREVIEW (never production).' -ForegroundColor Cyan
  & $gh workflow run $workflow --repo $repo --ref $branch --raw-field target=preview
  if ($LASTEXITCODE -ne 0) {throw 'Unable to dispatch GitHub preview workflow'}
  Write-Host ''
  Write-Host 'CHATGMG_PREVIEW_REQUESTED' -ForegroundColor Green
  Write-Host 'Track deployment: https://github.com/cryptostee1/chatgmg-production-source/actions'
  Write-Host 'Preview URL after successful run: https://gh-preview.chatgmg.pages.dev/'
  Write-Host 'Production chatgmg.com / Telegram / other domains untouched.'
}
catch {
  Write-Host ''
  Write-Host 'CHATGMG_PREVIEW_SETUP_INCOMPLETE' -ForegroundColor Red
  Write-Host ('Stage stopped: ' + $_.Exception.Message) -ForegroundColor Red
  Write-Host 'Production has not been deployed.'
  exit 1
}
finally {
  $token = $null
  $id = $null
}
