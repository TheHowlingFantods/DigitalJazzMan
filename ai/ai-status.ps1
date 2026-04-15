Write-Host ""
Write-Host "AI SYSTEM STATUS" -ForegroundColor Cyan
Write-Host "---------------------------------" -ForegroundColor DarkGray

function Test-OllamaHttp {
    try {
        $null = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

$ollamaRunning = Test-OllamaHttp

if ($ollamaRunning) {
    Write-Host "Ollama: RUNNING" -ForegroundColor Green
} else {
    Write-Host "Ollama: NOT RUNNING" -ForegroundColor Red
}

Write-Host ""
Write-Host "Installed models:" -ForegroundColor Cyan
try {
    ollama list
} catch {
    Write-Host "Could not retrieve models via CLI." -ForegroundColor Red
}

if (-not $ollamaRunning) {
    Write-Host ""
    $start = Read-Host "Start Ollama now? (y/n)"
    if ($start -ne "y") {
        Write-Host "Ollama not started." -ForegroundColor Yellow
        exit 0
    }

    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCmd) {
        Write-Host "Could not find ollama.exe on PATH." -ForegroundColor Red
        exit 1
    }

    $ollamaExe = $ollamaCmd.Source
    Write-Host "Starting Ollama from: $ollamaExe" -ForegroundColor DarkGray

    Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden

    $maxAttempts = 15
    $attempt = 0
    do {
        Start-Sleep -Seconds 1
        $attempt++
        $ollamaRunning = Test-OllamaHttp
    } until ($ollamaRunning -or $attempt -ge $maxAttempts)

    if ($ollamaRunning) {
        Write-Host "Ollama started." -ForegroundColor Green
    } else {
        Write-Host "Tried to start Ollama, but it still does not appear to be running." -ForegroundColor Red
        Write-Host "Try running: Invoke-RestMethod -Uri `"http://127.0.0.1:11434/api/tags`" -Method Get" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
$warm = Read-Host "Warm up Gemma 4 model? (y/n)"
if ($warm -eq "y") {
    ollama run gemma4:e2b "Say ready"
    Write-Host "Model warmed." -ForegroundColor Green
}

Write-Host ""
Write-Host "---------------------------------" -ForegroundColor DarkGray