# run-Lowlife.ps1 — robust launcher (project root, ASCII-only)

param(
    [switch]$Watch = $true,
    [switch]$RestartOnCrash = $false,
    [switch]$NoPause = $false
)

$ErrorActionPreference = 'Stop'

# Paths
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $projectRoot 'src'
Set-Location $projectRoot

# Validate required files
$required = @(
  (Join-Path $src '__init__.py'),
  (Join-Path $src 'bot\__init__.py'),
  (Join-Path $src 'core\__init__.py'),
  (Join-Path $src 'bot\bot.py')
)
foreach ($p in $required) {
  if (-not (Test-Path $p)) {
    Write-Host "Missing required file: $p" -ForegroundColor Red
    if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
    exit 1
  }
}

# Find python
$py = $null
try { $py = (Get-Command python -ErrorAction Stop).Source } catch { }
if (-not $py) {
  foreach ($c in @(
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "C:\Python312\python.exe","C:\Python311\python.exe","C:\Python310\python.exe"
  )) { if (Test-Path $c) { $py = $c; break } }
}
if (-not $py) {
  Write-Host "Python not found." -ForegroundColor Red
  if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
  exit 1
}

function Clear-PyCache {
  Get-ChildItem -Recurse -Force -Directory -Path $src -Filter '__pycache__' |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
}

function Run-Bot {
  & $py -m src.bot.bot
  return $LASTEXITCODE
}

# Clean any old watchers from this session
Get-EventSubscriber -ErrorAction SilentlyContinue | Where-Object { $_.SourceIdentifier -like 'SrcChanged*' } | Unregister-Event -ErrorAction SilentlyContinue
Get-Event -ErrorAction SilentlyContinue | Where-Object { $_.SourceIdentifier -like 'SrcChanged*' } | Remove-Event
Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'SrcChanged*' } | Remove-Job -Force

# Unique SourceIdentifier every run
$sourceId = 'SrcChanged_' + ([guid]::NewGuid().ToString('N'))

# Optional watcher
$watcher = $null
if ($Watch) {
  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = $src
  $watcher.Filter = '*.py'
  $watcher.IncludeSubdirectories = $true
  $watcher.EnableRaisingEvents = $true
  foreach ($ev in 'Changed','Created','Renamed','Deleted') {
    Register-ObjectEvent -InputObject $watcher -EventName $ev -SourceIdentifier $sourceId | Out-Null
  }
  Write-Host "Watch mode ON (source id: $sourceId)" -ForegroundColor Green
}

try {
  while ($true) {
    Clear-PyCache
    $code = Run-Bot

    if ($RestartOnCrash -and $code -ne 0) {
      Write-Host "Bot crashed with exit code $code. Restarting in 2s..." -ForegroundColor Yellow
      Start-Sleep -Seconds 2
      continue
    }

    if ($Watch) {
      Write-Host "Bot exited ($code). Waiting for file changes..." -ForegroundColor Yellow
      Wait-Event -SourceIdentifier $sourceId | Out-Null
      Get-Event -SourceIdentifier $sourceId | Remove-Event | Out-Null
      Write-Host "Change detected. Restarting..."
      continue
    }

    break
  }
}
finally {
  if ($Watch) {
    try { Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue } catch { }
    try { Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue | Remove-Event } catch { }
    if ($watcher) { $watcher.EnableRaisingEvents = $false; $watcher.Dispose() }
  }
  if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
}
