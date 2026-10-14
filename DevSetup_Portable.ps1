#requires -Version 5.1
# DevSetup Portable - Windows Terminal + PowerShell developer environment
# Review the script before running. It installs apps, updates user profiles, and changes Terminal settings.
# Run from PowerShell with:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\DevSetup_Portable.ps1

$ErrorActionPreference = 'Continue'
$script:SetupFailed = $false

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-StepResult {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [bool]$Success = $true
    )
    if ($Success) {
        Write-Host "[OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "[WARN] $Message" -ForegroundColor Yellow
    }
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function ConvertFrom-JsonWithComments {
    param([Parameter(Mandatory = $true)][string]$Text)

    # Remove JSONC comments without accidentally stripping // from URLs inside strings.
    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($inString) {
            [void]$builder.Append($ch)
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$builder.Append($ch)
            $i++
            continue
        }

        if ($ch -eq '/' -and $next -eq '/') {
            while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
            continue
        }

        if ($ch -eq '/' -and $next -eq '*') {
            $i += 2
            while ($i -lt $Text.Length - 1 -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
            if ($i -lt $Text.Length - 1) { $i += 2 }
            [void]$builder.Append(' ')
            continue
        }

        [void]$builder.Append($ch)
        $i++
    }

    # Remove trailing commas outside string literals (Windows PowerShell 5.1 needs this).
    $withoutComments = $builder.ToString()
    $builder2 = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $i = 0
    while ($i -lt $withoutComments.Length) {
        $ch = $withoutComments[$i]
        if ($inString) {
            [void]$builder2.Append($ch)
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            $i++
            continue
        }
        if ($ch -eq '"') {
            $inString = $true
            [void]$builder2.Append($ch)
            $i++
            continue
        }
        if ($ch -eq ',') {
            $lookAhead = $i + 1
            while ($lookAhead -lt $withoutComments.Length -and [char]::IsWhiteSpace($withoutComments[$lookAhead])) { $lookAhead++ }
            if ($lookAhead -lt $withoutComments.Length -and ($withoutComments[$lookAhead] -eq '}' -or $withoutComments[$lookAhead] -eq ']')) {
                $i++
                continue
            }
        }
        [void]$builder2.Append($ch)
        $i++
    }

    return ($builder2.ToString() | ConvertFrom-Json -ErrorAction Stop)
}

Write-Host 'DevSetup Portable v1.2: configure PowerShell and Windows Terminal' -ForegroundColor Magenta
Write-Host 'This script changes settings for the current Windows user.' -ForegroundColor Gray

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'This script is intended for Windows.' -ForegroundColor Red
    exit 1
}

# 1. Install developer command-line applications.
Write-Section '1/6 - Installing command-line tools'
$packages = @(
    'Microsoft.WindowsTerminal',
    'Microsoft.PowerShell',
    'Git.Git',
    'Starship.Starship',
    'DEVCOM.JetBrainsMonoNerdFont',
    'gerardog.gsudo',
    'eza-community.eza',
    'ajeetdsouza.zoxide',
    'junegunn.fzf',
    'sharkdp.bat',
    'sharkdp.fd',
    'BurntSushi.ripgrep.MSVC',
    'JesseDuffield.lazygit',
    'dandavison.delta',
    'rsteube.Carapace',
    'sxyazi.yazi',
    'GitHub.cli'
)

$wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($null -eq $wingetCommand) {
    Write-StepResult 'winget was not found; skipping automatic app installation. Install App Installer/winget, then run this file again.' $false
} else {
    foreach ($packageId in $packages) {
        Write-Host "Installing/checking $packageId ..." -ForegroundColor Gray
        try {
            & $wingetCommand.Source install --id $packageId --exact --accept-package-agreements --accept-source-agreements --silent
            $wingetExitCode = $LASTEXITCODE
            if ($wingetExitCode -eq 0) {
                Write-StepResult "$packageId installed or updated."
            } elseif ($wingetExitCode -eq -1978335189) {
                # 0x8A15002B = APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE.
                # winget can return this when it finds the app already installed but no newer version applies.
                Write-StepResult "$packageId is already installed; winget found no applicable update."
            } else {
                Write-StepResult "$packageId install/update returned exit code $wingetExitCode. Continuing." $false
            }
        } catch {
            Write-StepResult "Could not install $packageId. Continuing. $($_.Exception.Message)" $false
        }
    }

    # Refresh PATH for applications installed during this run.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = $machinePath + ';' + $userPath
}

# Pre-cache shell integration scripts. This avoids launching init commands on every new shell.
Write-Host 'Preparing cached shell initialization (Starship / zoxide)...' -ForegroundColor Gray
$cacheDirectory = Join-Path (Join-Path $HOME '.config') 'powershell_cache'
try {
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

    $starshipCommand = Get-Command starship -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($starshipCommand -and $starshipCommand.Source) {
        $starshipInitCache = Join-Path $cacheDirectory 'starship.ps1'
        $starshipInitText = & $starshipCommand.Source init powershell 2>$null
        if ($LASTEXITCODE -eq 0 -and $starshipInitText) {
            Set-Content -LiteralPath $starshipInitCache -Value $starshipInitText -Encoding UTF8
            Write-StepResult 'Starship initialization cached.'
        } else {
            Write-StepResult 'Starship cache was not created; the profile can fall back to live initialization.' $false
        }
    } else {
        Write-StepResult 'Starship was not found; its initialization cache was skipped.' $false
    }

    $zoxideCommand = Get-Command zoxide -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zoxideCommand -and $zoxideCommand.Source) {
        $zoxideInitCache = Join-Path $cacheDirectory 'zoxide.ps1'
        $zoxideInitText = & $zoxideCommand.Source init powershell 2>$null
        if ($LASTEXITCODE -eq 0 -and $zoxideInitText) {
            Set-Content -LiteralPath $zoxideInitCache -Value $zoxideInitText -Encoding UTF8
            Write-StepResult 'zoxide initialization cached.'
        } else {
            Write-StepResult 'zoxide cache was not created; the profile can fall back to live initialization.' $false
        }
    } else {
        Write-StepResult 'zoxide was not found; its initialization cache was skipped.' $false
    }
} catch {
    Write-StepResult "Could not prepare shell initialization cache: $($_.Exception.Message)" $false
}

# 2. Install PowerShell modules for the current user.
Write-Section '2/6 - Installing PowerShell modules'
$modules = @('PSReadLine', 'Terminal-Icons', 'posh-git', 'PSFzf')
if (Get-Command Install-Module -ErrorAction SilentlyContinue) {
    foreach ($moduleName in $modules) {
        try {
            # Updating a module that is loaded in this PowerShell process often produces
            # an in-use warning. Leave the active version alone; it is already usable.
            $loadedModule = Get-Module -Name $moduleName | Select-Object -First 1
            if ($loadedModule) {
                Write-StepResult "$moduleName $($loadedModule.Version) is loaded in this session; skipped in-place update."
                continue
            }

            Install-Module -Name $moduleName -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            $latestModule = Get-Module -ListAvailable -Name $moduleName |
                Sort-Object Version -Descending |
                Select-Object -First 1
            if ($latestModule) {
                Write-StepResult "PowerShell module available: $moduleName $($latestModule.Version)"
            } else {
                Write-StepResult "Install-Module returned without finding $moduleName afterwards." $false
            }
        } catch {
            Write-StepResult "Could not install/update module $moduleName. The rest of the setup will continue. $($_.Exception.Message)" $false
        }
    }
} else {
    Write-StepResult 'Install-Module is unavailable in this PowerShell session; skipping modules.' $false
}

# 3. Configure Git's diff viewer, if Git is available.
Write-Section '3/6 - Configuring Git and Delta'
$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCommand) {
    try {
        & $gitCommand.Source config --global core.pager delta
        & $gitCommand.Source config --global interactive.diffFilter 'delta --color-only'
        & $gitCommand.Source config --global delta.navigate true
        & $gitCommand.Source config --global delta.side-by-side true
        & $gitCommand.Source config --global delta.line-numbers true
        & $gitCommand.Source config --global delta.syntax-theme 'Catppuccin Mocha'
        Write-StepResult 'Git is configured to use Delta.'
    } catch {
        Write-StepResult "Git configuration was not fully applied: $($_.Exception.Message)" $false
    }
} else {
    Write-StepResult 'Git was not found in PATH; skipping Git configuration.' $false
}

# 4. Write the Starship prompt configuration.
Write-Section '4/6 - Configuring the Starship prompt'
$configDir = Join-Path $HOME '.config'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$starshipConfigPath = Join-Path $configDir 'starship.toml'
if (Test-Path -LiteralPath $starshipConfigPath) {
    $starshipBackupPath = "$starshipConfigPath.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    try {
        Copy-Item -LiteralPath $starshipConfigPath -Destination $starshipBackupPath -Force -ErrorAction Stop
        Write-StepResult "Existing Starship config backed up: $starshipBackupPath"
    } catch {
        Write-StepResult "Could not back up the existing Starship config; keeping it unchanged. $($_.Exception.Message)" $false
        throw
    }
}
$starshipConfig = @'
format = """
$os\
$directory\
$git_branch\
$git_status\
$nodejs\
$python\
$rust\
$dotnet\
$c\
$java\
$docker_context\
$cmd_duration\
$line_break\
$character"""

add_newline = true

[os]
disabled = false
style = "bold #89b4fa"

[os.symbols]
Windows = " "
Linux = " "
Macos = " "

[directory]
style = "bold #89b4fa"
format = "[ $path]($style)[$read_only]($read_only_style) "
truncation_length = 3
truncation_symbol = "…/"
read_only = " 󰌾"

[git_branch]
symbol = " "
style = "bold #cba6f7"

[git_status]
style = "bold #f38ba8"
format = '([$all_status$ahead_behind]($style) )'

[nodejs]
symbol = " "
style = "bold #a6e3a1"

[python]
symbol = " "
style = "bold #f9e2af"

[rust]
symbol = " "
style = "bold #fab387"

[dotnet]
symbol = " "
style = "bold #89dceb"

[c]
symbol = " "
style = "bold #89b4fa"

[java]
symbol = " "
style = "bold #fab387"

[docker_context]
symbol = " "
style = "bold #89b4fa"

[cmd_duration]
min_time = 500
format = "[ $duration](bold #f9e2af) "

[character]
success_symbol = "[❯](bold #a6e3a1)"
error_symbol = "[❯](bold #f38ba8)"
'@
Set-Content -LiteralPath $starshipConfigPath -Value $starshipConfig -Encoding UTF8
Write-StepResult "Starship configuration written to $starshipConfigPath"

# 5. Write a shared PowerShell profile for Windows PowerShell 5.1 and PowerShell 7.
Write-Section '5/6 - Configuring the PowerShell profile'
$profileContent = @'
# DevSetup Portable PowerShell profile

# Prompt and directory navigation. Prefer cached init scripts to reduce shell startup work.
$cacheDir = Join-Path (Join-Path $HOME '.config') 'powershell_cache'
$starshipCachePath = Join-Path $cacheDir 'starship.ps1'
$zoxideCachePath = Join-Path $cacheDir 'zoxide.ps1'

if (Test-Path -LiteralPath $starshipCachePath) {
    try { . $starshipCachePath } catch { }
} elseif (Get-Command starship -ErrorAction SilentlyContinue) {
    try { Invoke-Expression (& starship init powershell) } catch { }
}

if (Test-Path -LiteralPath $zoxideCachePath) {
    try { . $zoxideCachePath } catch { }
} elseif (Get-Command zoxide -ErrorAction SilentlyContinue) {
    try { Invoke-Expression (& { (zoxide init powershell | Out-String) }) } catch { }
}

# Command completion and useful modules
if (Get-Module -ListAvailable -Name Terminal-Icons) { Import-Module Terminal-Icons -ErrorAction SilentlyContinue }
if (Get-Module -ListAvailable -Name posh-git) { Import-Module posh-git -ErrorAction SilentlyContinue }
if (Get-Module -ListAvailable -Name PSFzf) { Import-Module PSFzf -ErrorAction SilentlyContinue }
if (Get-Command carapace -ErrorAction SilentlyContinue) {
    $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
    try { carapace _carapace | Out-String | Invoke-Expression } catch { }
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -EditMode Emacs
        Set-PSReadLineOption -BellStyle None
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
        $psReadLine = Get-Module PSReadLine
        if ($psReadLine -and $psReadLine.Version -ge [version]'2.1.0') {
            Set-PSReadLineOption -PredictionSource History
            Set-PSReadLineOption -PredictionViewStyle ListView
        }
    } catch { }
}

# fzf settings
$env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git --exclude node_modules'
$env:FZF_DEFAULT_OPTS = '--height 60% --layout=reverse --border=rounded --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc,marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8'
$env:FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :300 {}'"
$env:FZF_ALT_C_OPTS = "--preview 'eza --tree --level=2 --color=always --icons=always {}'"
if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
    try { Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' } catch { }
}

# eza shortcuts
if (Get-Command eza -ErrorAction SilentlyContinue) {
    if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue }
    function l  { eza --icons=always --group-directories-first @args }
    function ls { eza --icons=always --group-directories-first @args }
    function ll { eza -lh --git --icons=always --group-directories-first @args }
    function la { eza -lah --git --icons=always --group-directories-first @args }
    function lt { eza --tree --level=2 --icons=always --ignore-glob=node_modules --ignore-glob=.git @args }
}

# Common aliases
if (Get-Command bat -ErrorAction SilentlyContinue)     { Set-Alias -Name cat -Value bat -Option AllScope -Force }
if (Get-Command rg -ErrorAction SilentlyContinue)      { Set-Alias -Name grep -Value rg -Option AllScope -Force }
if (Get-Command lazygit -ErrorAction SilentlyContinue) { Set-Alias -Name lg -Value lazygit -Option AllScope -Force }
if (Get-Command gsudo -ErrorAction SilentlyContinue)   { Set-Alias -Name sudo -Value gsudo -Option AllScope -Force }

# Small helpers
function mkcd {
    param([Parameter(Mandatory = $true)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location -LiteralPath $Path
}

function y {
    if (-not (Get-Command yazi -ErrorAction SilentlyContinue)) { Write-Host 'yazi is not installed.'; return }
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        yazi @args --cwd-file="$tempFile"
        $newLocation = Get-Content -LiteralPath $tempFile -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($newLocation) -and (Test-Path -LiteralPath $newLocation -PathType Container)) {
            Set-Location -LiteralPath $newLocation.Trim()
        }
    } finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function fcode {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { Write-Host 'fzf is not installed.'; return }
    $file = fzf --preview "bat -n --color=always --line-range :300 {}"
    if ($file -and (Get-Command code -ErrorAction SilentlyContinue)) { code -- "$file" }
}

function fkill {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { Write-Host 'fzf is not installed.'; return }
    $selected = Get-Process | Select-Object Id, ProcessName, CPU | Format-Table -HideTableHeaders | Out-String -Stream | fzf --header='Select a process to kill'
    if ($selected -match '^\s*(\d+)') {
        $processIdToKill = [int]$matches[1]
        Stop-Process -Id $processIdToKill -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped process ID $processIdToKill" -ForegroundColor Green
    }
}

function ports {
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess, @{Name='Process';Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} |
        Sort-Object LocalPort | Format-Table -AutoSize
}

function killport {
    param([Parameter(Mandatory = $true)][int]$Port)
    $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($connections) {
        $processIds = $connections.OwningProcess | Select-Object -Unique
        foreach ($processId in $processIds) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped process $processId on port $Port" -ForegroundColor Green
        }
    } else {
        Write-Host "No active process found on port $Port" -ForegroundColor Yellow
    }
}

# The built-in alias 'gi' (Get-Item) takes priority over functions, so remove it first.
if (Test-Path Alias:gi) { Remove-Item Alias:gi -Force -ErrorAction SilentlyContinue }
function gi {
    param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$List)
    $List = ($List -join ',') -replace '\s+', ''
    $gitignorePath = Join-Path (Get-Location) '.gitignore'
    if (Test-Path -LiteralPath $gitignorePath) {
        $confirmation = Read-Host '.gitignore already exists. Type YES to replace it'
        if ($confirmation -cne 'YES') {
            Write-Host 'Cancelled. Existing .gitignore was not changed.' -ForegroundColor Yellow
            return
        }
        $backupPath = "$gitignorePath.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
        try {
            Copy-Item -LiteralPath $gitignorePath -Destination $backupPath -Force -ErrorAction Stop
            Write-Host "Existing .gitignore backed up to: $backupPath" -ForegroundColor Gray
        } catch {
            Write-Host "Could not back up existing .gitignore; cancelled for safety. $($_.Exception.Message)" -ForegroundColor Yellow
            return
        }
    }
    try {
        $content = Invoke-RestMethod -Uri "https://www.toptal.com/developers/gitignore/api/$List" -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$content) -or ([string]$content -match '^Not Found\s*$')) {
            throw 'The gitignore API returned no usable content. Check the language names.'
        }
        $content | Out-File -FilePath $gitignorePath -Encoding utf8
        Write-Host "[OK] .gitignore generated for: $List" -ForegroundColor Green
    } catch {
        Write-Host "Could not generate .gitignore: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function which {
    param([Parameter(Mandatory = $true)][string]$Name)
    $foundCommand = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($foundCommand) {
        if ($foundCommand.Source) { $foundCommand.Source } else { $foundCommand.Definition }
    }
}
'@

$documentsPath = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($documentsPath)) { $documentsPath = Join-Path $HOME 'Documents' }
$profilePaths = @(
    (Join-Path (Join-Path $documentsPath 'PowerShell') 'Microsoft.PowerShell_profile.ps1'),
    (Join-Path (Join-Path $documentsPath 'WindowsPowerShell') 'Microsoft.PowerShell_profile.ps1')
)
$backupStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($profilePath in $profilePaths) {
    try {
        $profileDirectory = Split-Path -Parent $profilePath
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        if (Test-Path -LiteralPath $profilePath) {
            $profileBackup = "$profilePath.$backupStamp.bak"
            Copy-Item -LiteralPath $profilePath -Destination $profileBackup -Force
            Write-StepResult "Existing profile backed up: $profileBackup"
        }
        Set-Content -LiteralPath $profilePath -Value $profileContent -Encoding UTF8
        Write-StepResult "PowerShell profile written: $profilePath"
    } catch {
        Write-StepResult "Could not write profile $profilePath : $($_.Exception.Message)" $false
    }
}

# 6. Apply Windows Terminal colors, font, opacity, and a PowerShell 7 default profile.
Write-Section '6/6 - Configuring Windows Terminal'
$stablePackageDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe'
$previewPackageDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe'
$unpackagedDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal'

if (Test-Path $stablePackageDir) {
    $wtSettingsPath = Join-Path $stablePackageDir 'LocalState\settings.json'
} elseif (Test-Path $previewPackageDir) {
    $wtSettingsPath = Join-Path $previewPackageDir 'LocalState\settings.json'
} else {
    $wtSettingsPath = Join-Path $unpackagedDir 'settings.json'
}

try {
    $wtDirectory = Split-Path -Parent $wtSettingsPath
    New-Item -ItemType Directory -Path $wtDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $wtSettingsPath) {
        $wtBackupPath = "$wtSettingsPath.$backupStamp.bak"
        Copy-Item -LiteralPath $wtSettingsPath -Destination $wtBackupPath -Force
        Write-StepResult "Windows Terminal settings backed up: $wtBackupPath"
        $wtConfig = ConvertFrom-JsonWithComments -Text (Get-Content -LiteralPath $wtSettingsPath -Raw)
    } else {
        $initialSettings = @'
{
  "$schema": "https://aka.ms/terminal-profiles-schema",
  "profiles": { "defaults": {}, "list": [] },
  "schemes": []
}
'@
        $wtConfig = $initialSettings | ConvertFrom-Json
    }

    if ($null -eq $wtConfig.PSObject.Properties['profiles'] -or $null -eq $wtConfig.profiles) {
        Set-ObjectProperty -Object $wtConfig -Name 'profiles' -Value ([PSCustomObject]@{ defaults = [PSCustomObject]@{}; list = @() })
    }
    if ($null -eq $wtConfig.profiles.PSObject.Properties['defaults'] -or $null -eq $wtConfig.profiles.defaults) {
        Set-ObjectProperty -Object $wtConfig.profiles -Name 'defaults' -Value ([PSCustomObject]@{})
    }
    if ($null -eq $wtConfig.profiles.PSObject.Properties['list'] -or $null -eq $wtConfig.profiles.list) {
        Set-ObjectProperty -Object $wtConfig.profiles -Name 'list' -Value @()
    }

    $catppuccin = [PSCustomObject]@{
        name = 'Catppuccin Mocha'
        background = '#1E1E2E'
        foreground = '#CDD6F4'
        cursorColor = '#F5E0DC'
        selectionBackground = '#585B70'
        black = '#45475A'
        red = '#F38BA8'
        green = '#A6E3A1'
        yellow = '#F9E2AF'
        blue = '#89B4FA'
        purple = '#F5C2E7'
        cyan = '#94E2D5'
        white = '#BAC2DE'
        brightBlack = '#585B70'
        brightRed = '#F38BA8'
        brightGreen = '#A6E3A1'
        brightYellow = '#F9E2AF'
        brightBlue = '#89B4FA'
        brightPurple = '#F5C2E7'
        brightCyan = '#94E2D5'
        brightWhite = '#A6ADC8'
    }
    $existingSchemes = @()
    if ($wtConfig.schemes) {
        $existingSchemes = @($wtConfig.schemes | Where-Object { $_.name -ne 'Catppuccin Mocha' })
    }
    $newSchemes = @($existingSchemes) + @($catppuccin)
    Set-ObjectProperty -Object $wtConfig -Name 'schemes' -Value $newSchemes

    $fontObject = $wtConfig.profiles.defaults.font
    if ($null -eq $fontObject) { $fontObject = [PSCustomObject]@{} }
    Set-ObjectProperty -Object $fontObject -Name 'face' -Value 'JetBrainsMono Nerd Font'
    Set-ObjectProperty -Object $fontObject -Name 'size' -Value 11
    Set-ObjectProperty -Object $fontObject -Name 'features' -Value ([PSCustomObject]@{ calt = 1; liga = 1 })
    Set-ObjectProperty -Object $wtConfig.profiles.defaults -Name 'font' -Value $fontObject
    Set-ObjectProperty -Object $wtConfig.profiles.defaults -Name 'colorScheme' -Value 'Catppuccin Mocha'
    Set-ObjectProperty -Object $wtConfig.profiles.defaults -Name 'padding' -Value '12, 12, 12, 12'
    Set-ObjectProperty -Object $wtConfig.profiles.defaults -Name 'cursorShape' -Value 'bar'
    Set-ObjectProperty -Object $wtConfig.profiles.defaults -Name 'opacity' -Value 94
    Set-ObjectProperty -Object $wtConfig.profiles.defaults -Name 'useAcrylic' -Value $true
    Set-ObjectProperty -Object $wtConfig -Name 'copyOnSelect' -Value $false

    # If PowerShell 7 is installed, add one predictable profile and make it the default.
    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $profileList = @($wtConfig.profiles.list)
    $devProfileGuid = '{a7d7f8ab-6f4b-4a7d-aea6-86bc87a15823}'
    if ($pwshCommand -and $pwshCommand.Source) {
        $devProfile = $profileList | Where-Object { $_.guid -eq $devProfileGuid } | Select-Object -First 1
        if ($null -eq $devProfile) {
            $devProfile = [PSCustomObject]@{
                guid = $devProfileGuid
                name = 'PowerShell 7 (DevSetup)'
                commandline = ('"' + $pwshCommand.Source + '" -NoLogo -NoProfileLoadTime')
                startingDirectory = '%USERPROFILE%'
                hidden = $false
            }
            $profileList += $devProfile
        } else {
            Set-ObjectProperty -Object $devProfile -Name 'commandline' -Value ('"' + $pwshCommand.Source + '" -NoLogo -NoProfileLoadTime')
            Set-ObjectProperty -Object $devProfile -Name 'name' -Value 'PowerShell 7 (DevSetup)'
        }
        Set-ObjectProperty -Object $wtConfig.profiles -Name 'list' -Value $profileList
        Set-ObjectProperty -Object $wtConfig -Name 'defaultProfile' -Value $devProfileGuid
    } else {
        $existingPowerShellProfile = $profileList | Where-Object {
            $_.name -match 'PowerShell' -or $_.source -eq 'Windows.Terminal.PowershellCore'
        } | Select-Object -First 1
        if ($existingPowerShellProfile -and $existingPowerShellProfile.guid) {
            Set-ObjectProperty -Object $wtConfig -Name 'defaultProfile' -Value $existingPowerShellProfile.guid
        }
    }

    $jsonOutput = $wtConfig | ConvertTo-Json -Depth 50
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($wtSettingsPath, $jsonOutput, $utf8NoBom)
    Write-StepResult "Windows Terminal configured: $wtSettingsPath"
} catch {
    Write-StepResult "Could not fully configure Windows Terminal: $($_.Exception.Message)" $false
    Write-Host 'Your original settings backup, if created, was not deleted.' -ForegroundColor Yellow
}

Write-Host "`nSetup finished. Close every Windows Terminal window and open it again." -ForegroundColor Green
Write-Host 'Some app installations may have been skipped if the work computer blocks them or winget needs permission.' -ForegroundColor Yellow
Write-Host 'Profile and Windows Terminal backups were saved next to the previous files with a timestamp.' -ForegroundColor Gray
Write-Host 'Starship/zoxide init scripts are cached to reduce startup overhead; actual startup time depends on this PC and installed modules.' -ForegroundColor Gray
