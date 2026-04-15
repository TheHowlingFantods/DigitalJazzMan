param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$TargetPath,

    [switch]$DryRun
)

$MODEL = "gemma4:e2b"

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Normalise-YesNo {
    param(
        [string]$Value,
        [string]$Default = "yes"
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    switch ($Value.Trim().ToLower()) {
        "y" { return "yes" }
        "yes" { return "yes" }
        "n" { return "no" }
        "no" { return "no" }
        default { return $Default }
    }
}

function Add-Command {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Command
    )

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $List.Add($Command)
    }
}

function Sanitise-FolderName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $clean = $Name.Trim()
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

    foreach ($char in $invalidChars) {
        $clean = $clean.Replace([string]$char, "-")
    }

    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim(' ', '.')

    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    return $clean
}

function Extract-JsonBlock {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $t = $Text.Trim()

    if ($t -match '(?s)```(?:json)?\s*(\{.*\})\s*```') {
        return $Matches[1].Trim()
    }

    $start = $t.IndexOf("{")
    $end = $t.LastIndexOf("}")
    if ($start -ge 0 -and $end -gt $start) {
        return $t.Substring($start, $end - $start + 1).Trim()
    }

    return $t
}

function Get-TrimmedUnquotedPathCandidate {
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return ""
    }

    $s = $Raw.Trim()
    while ($s.Length -gt 3 -and $s[-1] -match '[\?\!\.\,\;\:\)]') {
        $s = $s.Substring(0, $s.Length - 1)
    }
    return $s.Trim()
}

function Resolve-TargetPathFromPrompt {
    param([string]$PromptText)

    $lower = $PromptText.ToLower()

    if ($lower -match '\bthis folder\b') {
        Write-Info "Path hint: using current directory (""this folder"")."
        return (Get-Location).Path
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($m in [regex]::Matches($PromptText, '"([A-Za-z]:\\[^"]+)"')) {
        [void]$candidates.Add($m.Groups[1].Value.Trim())
    }

    foreach ($m in [regex]::Matches($PromptText, "'([A-Za-z]:\\[^']+)'")) {
        [void]$candidates.Add($m.Groups[1].Value.Trim())
    }

    foreach ($m in [regex]::Matches($PromptText, '(?<![:"''])([A-Za-z]:\\[^\s''"]+)')) {
        $trimmed = Get-TrimmedUnquotedPathCandidate -Raw $m.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            [void]$candidates.Add($trimmed)
        }
    }

    $resolvedOk = New-Object System.Collections.Generic.List[string]
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        try {
            $rp = (Resolve-Path -LiteralPath $c -ErrorAction Stop).Path
            if (Test-Path -LiteralPath $rp -PathType Container) {
                [void]$resolvedOk.Add($rp)
            }
        }
        catch {
            # ignore; try later with longest candidate
        }
    }

    $resolvedUnique = @($resolvedOk | Select-Object -Unique)

    if ($resolvedUnique.Count -eq 1) {
        Write-Info "Path hint: using the folder path found in your message."
        return $resolvedUnique[0]
    }

    if ($resolvedUnique.Count -gt 1) {
        $longest = @($resolvedUnique | Sort-Object { $_.Length } -Descending | Select-Object -First 1)[0]
        Write-Warn "Multiple folder paths in your message matched. Using the longest existing path:"
        Write-Host "  $longest" -ForegroundColor Gray
        return $longest
    }

    if ($candidates.Count -gt 0) {
        $sorted = $candidates | Sort-Object Length -Descending
        $pick = $sorted[0]
        Write-Warn "Found a path-like string in your message. Trying the longest candidate (verify this is correct):"
        Write-Host "  $pick" -ForegroundColor Gray
        return $pick
    }

    if ($lower -match '\bdesktop\b') {
        Write-Info "Path hint: using Desktop."
        $oneDriveDesktop = Join-Path $env:USERPROFILE "OneDrive\Desktop"
        $plainDesktop = Join-Path $env:USERPROFILE "Desktop"
        if (Test-Path -LiteralPath $oneDriveDesktop) {
            return $oneDriveDesktop
        }
        return $plainDesktop
    }

    if ($lower -match '\bdownloads\b') {
        Write-Info "Path hint: using Downloads."
        return (Join-Path $env:USERPROFILE "Downloads")
    }

    if ($lower -match '\bdocuments\b') {
        Write-Info "Path hint: using Documents."
        return (Join-Path $env:USERPROFILE "Documents")
    }

    Write-Warn "I could not confidently determine which folder you mean from the message alone."
    $entered = Read-Host "Please enter the full folder path"
    return $entered
}

function Get-OllamaTextResponse {
    param(
        [string]$Model,
        [string]$PromptText
    )

    $bodyObject = @{
        model  = $Model
        prompt = $PromptText
        stream = $false
    }

    $body = $bodyObject | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/generate" -Method Post -ContentType "application/json; charset=utf-8" -Body $body
    }
    catch {
        Write-Err "Could not reach Ollama at http://127.0.0.1:11434"
        Write-Err ("Details: {0}" -f $_.Exception.Message)
        Write-Err "Run aistatus first, or start Ollama."
        exit 1
    }

    if ($null -ne $response -and $response.PSObject.Properties.Name -contains 'response' -and -not [string]::IsNullOrWhiteSpace($response.response)) {
        return $response.response.Trim()
    }

    if ($null -ne $response -and $response.PSObject.Properties.Name -contains 'message' -and $null -ne $response.message) {
        if ($response.message.PSObject.Properties.Name -contains 'content' -and -not [string]::IsNullOrWhiteSpace($response.message.content)) {
            return $response.message.content.Trim()
        }
    }

    Write-Err "The model returned no usable text."
    Write-Host ""
    Write-Warn "Raw Ollama response:"
    $response | ConvertTo-Json -Depth 10
    exit 1
}

function Build-TypeCommands {
    param(
        [string]$BasePath,
        [bool]$CreateFolders
    )

    $result = New-Object 'System.Collections.Generic.List[string]'

    $groups = @(
        @{ Name = "Archives";   Extensions = @(".zip", ".rar", ".7z") },
        @{ Name = "Installers"; Extensions = @(".exe", ".msi") },
        @{ Name = "Images";     Extensions = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".psd") },
        @{ Name = "Documents";  Extensions = @(".pdf", ".doc", ".docx", ".txt", ".csv", ".xlsx", ".pptx", ".url") },
        @{ Name = "Videos";     Extensions = @(".mp4", ".mov", ".mkv") },
        @{ Name = "Audio";      Extensions = @(".mp3", ".wav", ".flac") },
        @{ Name = "Design";     Extensions = @(".ai", ".indd") }
    )

    foreach ($group in $groups) {
        $matchingFiles = Get-ChildItem -Path $BasePath -File -Force | Where-Object {
            $group.Extensions -contains $_.Extension.ToLower()
        }

        if ($matchingFiles.Count -eq 0) {
            continue
        }

        $destination = Join-Path $BasePath $group.Name

        if ($CreateFolders) {
            Add-Command -List $result -Command ("New-Item -Path ""{0}"" -ItemType Directory -Force" -f $destination)
        }

        foreach ($ext in $group.Extensions) {
            $hasExt = $matchingFiles | Where-Object { $_.Extension.ToLower() -eq $ext }
            if ($hasExt.Count -gt 0) {
                Add-Command -List $result -Command ("Get-ChildItem -Path ""{0}"" -Filter ""*{1}"" -File | Move-Item -Destination ""{2}"" -Force" -f $BasePath, $ext, $destination)
            }
        }
    }

    return $result
}

function Build-ClassificationPrompt {
    param(
        [string]$ResolvedTargetPath,
        [string]$OrganisationMode,
        [string]$TouchSubfolders,
        [string]$CreateFolders,
        [string]$RenameFiles,
        [string]$ExtraInstruction,
        [string[]]$TopLevelFileNames
    )

    $lines = @(
        "You are classifying files into sensible folders.",
        "",
        "Return JSON only.",
        "Do not return PowerShell.",
        "Do not return explanations.",
        "Do not wrap the JSON in markdown.",
        "",
        "Target folder:",
        $ResolvedTargetPath,
        "",
        "Organisation mode:",
        $OrganisationMode,
        "",
        "User choices:",
        "- Leave existing subfolders alone: $TouchSubfolders",
        "- May create new subfolders: $CreateFolders",
        "- May rename files: $RenameFiles",
        "- Extra instruction: $ExtraInstruction",
        "",
        "Important:",
        "- Only classify the loose top-level files shown below.",
        "- Do not include any file that is not listed below.",
        "- Copy each filename exactly, character for character.",
        "- Do not rewrite dates.",
        "- Do not remove leading zeroes.",
        "- Do not invent files.",
        "- Use a small number of sensible folders.",
        "- Put unclear items into ""Miscellaneous"".",
        "- Do not produce more than 8 folders.",
        "- Prefer folders with at least 2 files where possible.",
        "",
        "Return one of these JSON shapes only:",
        "",
        'If there is nothing useful to do:',
        '{"status":"no_changes"}',
        "",
        'If the request is unsafe or impossible:',
        '{"status":"blocked"}',
        "",
        'Otherwise:',
        '{',
        '  "status":"ok",',
        '  "folders":[',
        '    {',
        '      "name":"Folder Name",',
        '      "files":[',
        '        "Exact File Name 1.ext",',
        '        "Exact File Name 2.ext"',
        '      ]',
        '    }',
        '  ]',
        '}',
        "",
        "Loose top-level files:"
    )

    if ($TopLevelFileNames.Count -eq 0) {
        $lines += "[NONE]"
    }
    else {
        $lines += $TopLevelFileNames
    }

    return ($lines -join "`n")
}

function Build-CommandsFromClassification {
    param(
        [pscustomobject]$Classification,
        [string]$ResolvedTargetPath,
        [System.IO.FileInfo[]]$TopLevelFiles,
        [string]$CreateFolders
    )

    $result = New-Object 'System.Collections.Generic.List[string]'

    $exactFileMap = @{}
    foreach ($file in $TopLevelFiles) {
        $exactFileMap[$file.Name] = $file.FullName
    }

    $assignedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $createdFolderSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if ($null -eq $Classification.folders -or $Classification.folders.Count -gt 8) {
        Write-Err "Blocked: model proposed an invalid folder list (missing or too many folders)."
        exit 1
    }

    foreach ($folder in $Classification.folders) {
        $safeFolderName = Sanitise-FolderName -Name $folder.name

        if ([string]::IsNullOrWhiteSpace($safeFolderName)) {
            Write-Err "Blocked: invalid folder name returned by model."
            exit 1
        }

        if ($safeFolderName -eq "." -or $safeFolderName -eq "..") {
            Write-Err "Blocked: invalid folder name returned by model."
            exit 1
        }

        $destinationPath = Join-Path $ResolvedTargetPath $safeFolderName

        if (($CreateFolders -ne "yes") -and -not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
            Write-Err "Blocked: model wants a new folder but you said no to creating folders."
            exit 1
        }

        if (-not $createdFolderSet.Contains($destinationPath) -and -not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
            Add-Command -List $result -Command ("New-Item -Path ""{0}"" -ItemType Directory -Force" -f $destinationPath)
            [void]$createdFolderSet.Add($destinationPath)
        }

        if ($null -eq $folder.files) {
            continue
        }

        foreach ($fileName in $folder.files) {
            if (-not $exactFileMap.ContainsKey($fileName)) {
                Write-Err "Blocked: model referenced a file not in the exact snapshot: $fileName"
                exit 1
            }

            if ($assignedFiles.Contains($fileName)) {
                Write-Err "Blocked: model assigned the same file to more than one folder: $fileName"
                exit 1
            }

            $sourcePath = $exactFileMap[$fileName]
            Add-Command -List $result -Command ("Move-Item -Path ""{0}"" -Destination ""{1}"" -Force" -f $sourcePath, $destinationPath)
            [void]$assignedFiles.Add($fileName)
        }
    }

    return $result
}

function Get-DestinationPathsFromCommandLine {
    param([string]$Line)

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Line, '-Destination\s+"([^"]+)"')) {
        [void]$list.Add($m.Groups[1].Value)
    }
    return $list
}

function Get-SourcePathFromDirectMove {
    param([string]$Line)

    $m = [regex]::Match($Line, '^Move-Item\s+.*-Path\s+"([^"]+)"')
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    try {
        $TargetPath = Resolve-TargetPathFromPrompt -PromptText $Prompt
    }
    catch {
        Write-Err ("Could not resolve a target folder from your prompt. {0}" -f $_.Exception.Message)
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    Write-Err "No target folder was provided."
    exit 1
}

try {
    $resolvedTargetPath = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
}
catch {
    Write-Err "Target path does not exist or is not reachable: $TargetPath"
    Write-Err ("Details: {0}" -f $_.Exception.Message)
    exit 1
}

if (-not (Test-Path -LiteralPath $resolvedTargetPath -PathType Container)) {
    Write-Err "Target path is not a folder: $resolvedTargetPath"
    exit 1
}

$folderItems = Get-ChildItem -LiteralPath $resolvedTargetPath -Force | Sort-Object PSIsContainer, Name
$topLevelFiles = Get-ChildItem -LiteralPath $resolvedTargetPath -File -Force | Sort-Object Name

$folderSnapshotLines = @()
foreach ($item in $folderItems) {
    if ($item.PSIsContainer) {
        $folderSnapshotLines += "[DIR]  $($item.Name)"
    }
    else {
        $folderSnapshotLines += "[FILE] $($item.Name) | EXT=$($item.Extension) | SIZE=$($item.Length)"
    }
}

if ($folderSnapshotLines.Count -eq 0) {
    $folderSnapshot = "[EMPTY]"
}
else {
    $folderSnapshot = ($folderSnapshotLines -join "`n")
}

Write-Host ""
Write-Info "Resolved target folder: $resolvedTargetPath"
Write-Host ""
Write-Info "Folder snapshot:"
Write-Host "---------------------------------" -ForegroundColor DarkGray
Write-Host $folderSnapshot -ForegroundColor Gray
Write-Host "---------------------------------" -ForegroundColor DarkGray
Write-Host ""

Write-Info "Before I plan anything, answer these questions."

$organisationMode = Read-Host "Organise by file type, by project purpose, or by date? (type/purpose/date)"
if ([string]::IsNullOrWhiteSpace($organisationMode)) {
    $organisationMode = "type"
}
$organisationMode = $organisationMode.Trim().ToLower()
switch ($organisationMode) {
    "file type" { $organisationMode = "type" }
    "filetype" { $organisationMode = "type" }
    "project purpose" { $organisationMode = "purpose" }
    "by purpose" { $organisationMode = "purpose" }
    "by date" { $organisationMode = "date" }
    "by type" { $organisationMode = "type" }
}

$touchSubfolders = Normalise-YesNo (Read-Host "Should I leave existing subfolders alone? (yes/no)") "yes"
$createFolders = Normalise-YesNo (Read-Host "May I create new subfolders if needed? (yes/no)") "yes"
$renameFiles = Normalise-YesNo (Read-Host "May I rename files if that helps tidy things up? (yes/no)") "no"
$extraInstruction = Read-Host "Anything else I should avoid or prefer? (press Enter to skip)"

$commands = New-Object 'System.Collections.Generic.List[string]'

if ($organisationMode -eq "type") {
    $commands = Build-TypeCommands -BasePath $resolvedTargetPath -CreateFolders ($createFolders -eq "yes")

    if ($commands.Count -eq 0) {
        Write-Info "Suggested command(s):"
        Write-Host "---------------------------------" -ForegroundColor DarkGray
        Write-Host 'Write-Output "No changes needed"' -ForegroundColor Yellow
        Write-Host "---------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Ok "No changes needed. The folder already looks organised for file-type mode."
        exit 0
    }
}
else {
    $classificationPrompt = Build-ClassificationPrompt -ResolvedTargetPath $resolvedTargetPath -OrganisationMode $organisationMode -TouchSubfolders $touchSubfolders -CreateFolders $createFolders -RenameFiles $renameFiles -ExtraInstruction $extraInstruction -TopLevelFileNames ($topLevelFiles | ForEach-Object { $_.Name })

    $classificationRaw = Get-OllamaTextResponse -Model $MODEL -PromptText $classificationPrompt
    $classificationText = Extract-JsonBlock -Text $classificationRaw

    try {
        $classification = $classificationText | ConvertFrom-Json
    }
    catch {
        Write-Err "The model returned invalid JSON for purpose/date mode."
        Write-Err ("Details: {0}" -f $_.Exception.Message)
        Write-Host ""
        Write-Warn "Raw model output:"
        Write-Host $classificationRaw
        exit 1
    }

    if ($null -eq $classification.status) {
        Write-Err "The model did not return a valid status."
        exit 1
    }

    switch ($classification.status) {
        "no_changes" {
            Write-Info "Suggested command(s):"
            Write-Host "---------------------------------" -ForegroundColor DarkGray
            Write-Host 'Write-Output "No changes needed"' -ForegroundColor Yellow
            Write-Host "---------------------------------" -ForegroundColor DarkGray
            Write-Host ""
            Write-Ok "No changes needed. The folder already looks organised."
            exit 0
        }
        "blocked" {
            Write-Info "Suggested command(s):"
            Write-Host "---------------------------------" -ForegroundColor DarkGray
            Write-Host 'Write-Output "Blocked: unsafe or unsupported request"' -ForegroundColor Yellow
            Write-Host "---------------------------------" -ForegroundColor DarkGray
            Write-Host ""
            Write-Err "The model declined the request as unsafe or unsupported."
            exit 1
        }
        "ok" { }
        default {
            Write-Err "Unexpected model status: $($classification.status)"
            exit 1
        }
    }

    if ($null -eq $classification.folders -or $classification.folders.Count -eq 0) {
        Write-Err "The model returned no folders to apply."
        exit 1
    }

    $commands = Build-CommandsFromClassification -Classification $classification -ResolvedTargetPath $resolvedTargetPath -TopLevelFiles $topLevelFiles -CreateFolders $createFolders

    if ($commands.Count -eq 0) {
        Write-Info "Suggested command(s):"
        Write-Host "---------------------------------" -ForegroundColor DarkGray
        Write-Host 'Write-Output "No changes needed"' -ForegroundColor Yellow
        Write-Host "---------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Ok "No changes needed. The folder already looks organised."
        exit 0
    }
}

$fullCommandText = ($commands -join "`n")

Write-Host ""
Write-Info "Suggested command(s):"
Write-Host "---------------------------------" -ForegroundColor DarkGray
Write-Host $fullCommandText -ForegroundColor Yellow
Write-Host "---------------------------------" -ForegroundColor DarkGray
Write-Host ""

$blockedPatterns = @(
    'Remove-Item',
    '(^|[\s;])del([\s;]|$)',
    '(^|[\s;])rmdir([\s;]|$)',
    'Format-',
    'Clear-Content',
    'Set-Content',
    'Add-Content',
    'Invoke-WebRequest',
    '(^|[\s;])curl([\s;]|$)',
    'Start-Process',
    '(^|[\s;])powershell([\s;]|$)',
    '(^|[\s;])cmd([\s;]|$)',
    '(^|[\s;])reg([\s;]|$)',
    '(^|[\s;])sc([\s;]|$)',
    'taskkill',
    'Stop-Process',
    'Copy-Item',
    'Set-Location',
    'C:\\Windows',
    'C:\\Program Files',
    'C:\\Program Files \(x86\)',
    '\.\.',
    '\s-Include\s',
    'New-Item\s+.*-Name\s+'
)

foreach ($pattern in $blockedPatterns) {
    if ($fullCommandText -match $pattern) {
        Write-Err "Blocked potentially dangerous, malformed, or out-of-scope command."
        exit 1
    }
}

$allowedCmdlets = @(
    'New-Item',
    'Move-Item',
    'Get-ChildItem',
    'Rename-Item',
    'Write-Output'
)

foreach ($line in $commands) {
    $trimmed = $line.Trim()
    if ($trimmed -eq '') { continue }

    $firstToken = ($trimmed -split '\s+')[0]
    if ($allowedCmdlets -notcontains $firstToken) {
        Write-Err "Blocked unapproved cmdlet: $firstToken"
        exit 1
    }
}

$quotedPathMatches = [regex]::Matches($fullCommandText, '"([A-Za-z]:\\[^"]*)"')
foreach ($match in $quotedPathMatches) {
    $pathText = $match.Groups[1].Value.Trim()
    if (-not $pathText.StartsWith($resolvedTargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Err "Blocked command outside the allowed target folder."
        exit 1
    }
}

if ($fullCommandText -match '(?<!")([A-Za-z]:\\[^\s"]+)') {
    Write-Err "Blocked unquoted path. Paths must be wrapped in double quotes."
    exit 1
}

$existingDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($dir in Get-ChildItem -LiteralPath $resolvedTargetPath -Directory -Force) {
    [void]$existingDirs.Add($dir.FullName)
}

$createdDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($line in $commands) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^New-Item\s+.*-Path\s+"([^"]+)"\s+.*-ItemType\s+Directory\b') {
        [void]$createdDirs.Add($matches[1])
        continue
    }
}

foreach ($line in $commands) {
    $trimmed = $line.Trim()
    foreach ($destinationPath in (Get-DestinationPathsFromCommandLine -Line $trimmed)) {
        if (-not ($existingDirs.Contains($destinationPath) -or $createdDirs.Contains($destinationPath))) {
            Write-Err "Blocked move to destination folder that was not created first: $destinationPath"
            exit 1
        }
    }
}

foreach ($line in $commands) {
    $trimmed = $line.Trim()
    $directSource = Get-SourcePathFromDirectMove -Line $trimmed
    if ($null -ne $directSource) {
        if (-not (Test-Path -LiteralPath $directSource)) {
            Write-Err "Blocked move from source path that does not exist: $directSource"
            exit 1
        }
    }
}

Write-Info "Dry run summary:"
Write-Host "---------------------------------" -ForegroundColor DarkGray

foreach ($line in $commands) {
    $trimmed = $line.Trim()

    if ($trimmed -match '^New-Item\s+.*-Path\s+"([^"]+)"\s+.*-ItemType\s+Directory\b') {
        Write-Host "Would create folder: $($matches[1])" -ForegroundColor Gray
        continue
    }

    if ($trimmed -match '^Get-ChildItem\s+.*-Path\s+"([^"]+)"\s+.*-Filter\s+"([^"]+)"\s+.*\|\s+Move-Item\s+.*-Destination\s+"([^"]+)"') {
        $sourcePath = $matches[1]
        $filter = $matches[2]
        $destinationPath = $matches[3]

        $matchedFiles = Get-ChildItem -LiteralPath $sourcePath -Filter $filter -File -Force -ErrorAction SilentlyContinue
        if ($matchedFiles.Count -eq 0) {
            Write-Host "Would move 0 files matching $filter to $destinationPath" -ForegroundColor Gray
        }
        else {
            Write-Host "Would move $($matchedFiles.Count) file(s) matching $filter to $destinationPath" -ForegroundColor Gray
            foreach ($file in $matchedFiles) {
                Write-Host "  - $($file.Name)" -ForegroundColor DarkGray
            }
        }
        continue
    }

    if ($trimmed -match '^Move-Item\s+.*-Path\s+"([^"]+)"\s+.*-Destination\s+"([^"]+)"') {
        $sourcePath = $matches[1]
        $destinationPath = $matches[2]
        $fileName = Split-Path $sourcePath -Leaf
        Write-Host "Would move file: $fileName -> $destinationPath" -ForegroundColor Gray
        continue
    }

    if ($trimmed -match '^Rename-Item\s+.*-Path\s+"([^"]+)"\s+.*-NewName\s+"([^"]+)"') {
        $sourcePath = $matches[1]
        $newName = $matches[2]
        $fileName = Split-Path $sourcePath -Leaf
        Write-Host "Would rename file: $fileName -> $newName" -ForegroundColor Gray
        continue
    }

    Write-Host "Would run: $trimmed" -ForegroundColor Gray
}

Write-Host "---------------------------------" -ForegroundColor DarkGray
Write-Host ""

if ($DryRun) {
    Write-Ok "Dry run only. No changes made."
    exit 0
}

$planConfirm = Read-Host "Do you want me to execute this plan? (y/n)"
if ($planConfirm -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit 0
}

foreach ($line in $commands) {
    $trimmed = $line.Trim()
    if ($trimmed -ne "") {
        try {
            Invoke-Expression $trimmed
        }
        catch {
            Write-Err ("Command failed: {0}" -f $trimmed)
            Write-Err ("Details: {0}" -f $_.Exception.Message)
            exit 1
        }
    }
}

Write-Ok "Done."
