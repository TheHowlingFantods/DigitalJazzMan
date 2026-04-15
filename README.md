# Digital Jazz Man — local AI file-organiser harness

Windows PowerShell scripts that pair plain-English prompts with a **local Ollama** model (for example **gemma4:e2b**) to plan folder tidy-up operations. The harness resolves paths, shows a snapshot, asks questions first, validates every action, supports **dry-run**, and only runs moves after you type **y**.

## Prerequisites

- Windows with PowerShell
- [Ollama](https://ollama.com/) installed and running on `127.0.0.1:11434`
- A suitable model pulled locally (for example `gemma4:e2b`)

## Install

1. Clone this repository (or copy the `ai` folder).

2. Copy the `ai` folder to a fixed location, for example:

   `C:\ai\`

   so you have:

   - `C:\ai\ai.ps1`
   - `C:\ai\ai-status.ps1`

3. Optional: define commands in your PowerShell profile (`$PROFILE`). Aliases cannot point at `.ps1` paths directly, so use functions (see `install/profile-snippet.ps1`):

   ```powershell
   $AiRoot = "C:\ai"
   function ai { & (Join-Path $AiRoot "ai.ps1") @args }
   function aistatus { & (Join-Path $AiRoot "ai-status.ps1") @args }
   ```

   Adjust `$AiRoot` if you keep the scripts elsewhere.

## Usage

Check Ollama and models:

```powershell
aistatus
```

Organise a folder (examples):

```powershell
ai "tidy my desktop" -DryRun
ai "organise my downloads" -DryRun
cd "D:\Your\Project"
ai "tidy this folder" -DryRun
ai "can you tidy this folder?" -TargetPath "D:\Your\Exact\Folder" -DryRun
```

Remove `-DryRun` only when you intend to apply changes; the script will ask for final confirmation.

## Behaviour (summary)

- **Type** mode: deterministic moves by file extension (no model-generated filenames).
- **Purpose / date** mode: the model returns **JSON classifications only**; the script builds `New-Item` / `Move-Item` lines and checks every filename against the live snapshot.
- Safety checks include allowlisted cmdlets, quoted paths, staying inside the target folder, and no deletes.

## Repository layout

| Path | Purpose |
|------|--------|
| `ai/ai.ps1` | Main harness |
| `ai/ai-status.ps1` | Ollama reachability, `ollama list`, optional model warm-up |
| `install/profile-snippet.ps1` | Example profile functions for `ai` and `aistatus` |

## Licence

Use and modify for personal or internal use; add a licence file if you redistribute.
