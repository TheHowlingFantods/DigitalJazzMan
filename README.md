# VincentAtHome

Local Windows **PowerShell + Ollama** file-organiser harness (plain English in, validated moves out).

<p align="center">
  <img src="assets/vincent-at-home.png" alt="VincentAtHome — DIY robot mascot" width="420" />
</p>

Windows PowerShell scripts that pair plain-English prompts with a **local Ollama** model (for example **gemma4:e2b**) to plan folder tidy-up operations. The harness resolves paths, shows a snapshot, asks questions first, validates every action, supports **dry-run**, and only runs moves after you type **y**.

## Prerequisites

- Windows with PowerShell
- [Ollama](https://ollama.com/) installed and running on `127.0.0.1:11434`
- At least one **Google Gemma** model pulled locally (this project defaults to **`gemma4:e2b`**)

## Install Ollama and Google Gemma models

### Install Ollama (Windows)

1. Open **[Ollama — Download](https://ollama.com/download)** and download the **Windows** installer.
2. Run the installer and complete the steps (you may need to allow the app through the firewall the first time it serves models).
3. After installation, Ollama usually listens on **`http://127.0.0.1:11434`**. You do **not** need to run `ollama serve` manually if the Ollama app or background service is already running (starting it twice can show a “bind: Only one usage…” message, which means the port is already in use).
4. Check that the CLI works:

   ```powershell
   ollama --version
   ```

5. Optional sanity check that the HTTP API responds:

   ```powershell
   Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get
   ```

### Install Google Gemma models

Gemma models in Ollama are listed in the **[Ollama library](https://ollama.com/library)** (search for **“gemma”**). Tags and sizes change over time; always pick a tag that exists on your machine with `ollama list`.

**Pull models** (downloads weights; needs disk space and a stable connection):

```powershell
# Default for this harness (see $MODEL in ai/ai.ps1)
ollama pull gemma4:e2b

# Smaller / faster option for testing (optional)
ollama pull gemma3:1b
```

**Confirm they are installed:**

```powershell
ollama list
```

**Using a different model:** edit the `$MODEL` line near the top of `ai/ai.ps1` to match a name shown in `ollama list` (for example `gemma3:1b`). If you use **`ai-status.ps1`** warm-up, update the `ollama run …` line there so it matches the same tag.

**Licence and terms:** Gemma is provided by Google under its own terms. Review **[Google’s Gemma documentation and terms](https://ai.google.dev/gemma)** before use, especially for redistribution or commercial use.

## Install this harness

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
| `assets/vincent-at-home.png` | README mascot image |
| `ai/ai.ps1` | Main harness |
| `ai/ai-status.ps1` | Ollama reachability, `ollama list`, optional model warm-up |
| `install/profile-snippet.ps1` | Example profile functions for `ai` and `aistatus` |
| `social/` | Archived X.com and other social thread snapshots (Markdown) |

## Licence

Use and modify for personal or internal use; add a licence file if you redistribute.
