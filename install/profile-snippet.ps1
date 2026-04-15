# Paste into your PowerShell profile ($PROFILE), or dot-source from there.
# Update $AiRoot if you did not install under C:\ai

$AiRoot = "C:\ai"

function ai {
    & (Join-Path $AiRoot "ai.ps1") @args
}

function aistatus {
    & (Join-Path $AiRoot "ai-status.ps1") @args
}

Write-Host "Loaded ai / aistatus from $AiRoot" -ForegroundColor DarkGray
