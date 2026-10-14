# DevSetup Portable

A PowerShell setup script for creating a modern Windows developer terminal with **Windows Terminal**, **PowerShell**, **Starship**, **Catppuccin Mocha**, and a collection of useful command-line tools.

The goal is to recreate a consistent terminal workflow on another Windows PC without configuring every tool by hand.

> **Important:** This script installs software and changes settings for the current Windows user. Review the script before running it, and test it on a personal or test account before using it on a work computer. It has not been verified on every Windows configuration.

## Features

### Terminal appearance

- Windows Terminal, with PowerShell 7 set as the default profile when it is available.
- Catppuccin Mocha color scheme.
- JetBrainsMono Nerd Font, size 11, with `calt` and `liga` font features enabled.
- 94% opacity and acrylic transparency.
- `12, 12, 12, 12` padding and a bar-shaped cursor.
- `copyOnSelect` disabled.
- Starship prompt with symbols and status information for the current directory, Git, Node.js, Python, Rust, .NET, C, Java, and Docker.

### Command-line tools

The script uses `winget` to install or check the following packages:

| Tool | Purpose |
| --- | --- |
| Windows Terminal | Terminal emulator |
| PowerShell 7 | Modern PowerShell shell |
| Git | Version control |
| Starship | Customizable shell prompt |
| JetBrainsMono Nerd Font | Font with programming glyphs and icons |
| `gsudo` | Run commands with elevated privileges |
| `eza` | Enhanced directory listings |
| `zoxide` | Smart directory navigation (`z`) |
| `fzf` | Interactive fuzzy finder |
| `bat` | File viewer with syntax highlighting |
| `fd` | Fast file search |
| `ripgrep` (`rg`) | Fast text search |
| `lazygit` | Terminal UI for Git |
| `delta` | Enhanced Git diff viewer |
| Carapace | Shell completions for many command-line tools |
| Yazi | Terminal file manager |
| GitHub CLI (`gh`) | Work with GitHub from the terminal |

The generated Windows Terminal PowerShell 7 profile uses `-NoLogo -NoProfileLoadTime` to hide the startup banner and profile-load timing message while still loading your profiles.

The script continues if an individual package cannot be installed. If `winget` is unavailable, the automatic application-installation step is skipped, and you will need to install the tools yourself.

### PowerShell modules

The script installs or checks these modules for the current user from PowerShell Gallery:

- `PSReadLine`
- `Terminal-Icons`
- `posh-git`
- `PSFzf`

If a module is already loaded in the running PowerShell session, the script leaves that active version alone to avoid in-use warnings. The profile configures history-based predictions and menu completion when supported, plus fuzzy history and file search shortcuts.

### Aliases and helper functions

| Command | Description |
| --- | --- |
| `ls`, `l` | List files with `eza` icons |
| `ll` | Detailed listing with Git information |
| `la` | Detailed listing including hidden files |
| `lt` | Directory tree view |
| `cat` | Uses `bat` when installed |
| `grep` | Uses `rg` when installed |
| `lg` | Opens `lazygit` |
| `sudo` | Uses `gsudo` when installed |
| `mkcd <path>` | Create a directory and enter it |
| `ports` | Show TCP ports in the listening state and their owning processes |
| `killport <port>` | Stop processes associated with a local port |
| `fcode` | Select a file with `fzf` preview and open it in VS Code, if `code` is available |
| `fkill` | Select a process interactively and stop it |
| `gi <languages>` | Generate a `.gitignore` file using the Toptal gitignore API |
| `y` | Open Yazi and change to its final directory on exit |
| `which <name>` | Show the resolved command path or definition |
| `z <directory>` | Jump to a frequently used directory with `zoxide` |

`Ctrl+R` is configured for fuzzy history search and `Ctrl+T` for fuzzy file selection through PSFzf, when the relevant tools and modules are available.

### Git and startup

- Configures Git to use Delta for diffs, with side-by-side output, line numbers, navigation, and the Catppuccin Mocha syntax theme.
- Creates cached initialization scripts for Starship and zoxide to avoid generating their shell initialization on every launch.
- Uses PowerShell 7’s `-NoLogo -NoProfileLoadTime` switches in the generated Windows Terminal profile to hide the PowerShell version banner and the “Loading personal and system profiles took…” message without disabling profiles.
- The cache may reduce startup work, but actual startup time depends on the computer, installed tools, and PowerShell modules. No fixed startup-time guarantee is made.

## Requirements

- Windows 10 or Windows 11 is recommended.
- Windows PowerShell **5.1 or later**. PowerShell 7 is installed by the script when `winget` is available.
- `winget` (Windows Package Manager) for automatic application installation.
- Internet access to download apps and PowerShell modules, and to use the `gi` command.
- Permission to install applications and modify the current user's settings. A managed work PC may block some installations or configuration changes.

## Installation

1. Download or clone this repository.
2. Open PowerShell in the folder containing `DevSetup_Portable.ps1`.
3. Review the script before running it.
4. Run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\DevSetup_Portable.ps1
   ```

   This sets the execution policy only for the current PowerShell process; it does not permanently change the machine's execution policy.

   Alternatively, run the script directly with Windows PowerShell:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\DevSetup_Portable.ps1
   ```

5. Let the script finish. Some packages or modules may be skipped if installation is blocked or a dependency is unavailable.
6. Close all Windows Terminal windows and reopen Windows Terminal.

## What the script changes

The script configures settings for the **current Windows user**. It does not copy every installed application, credential, project, or personal file from one computer to another.

It may:

- Install applications with `winget`.
- Install PowerShell modules in the current user's module scope.
- Write Starship configuration to `~/.config/starship.toml`.
- Create cached Starship and zoxide initialization scripts under `~/.config/powershell_cache/`.
- Write PowerShell profile files under the user's `Documents\PowerShell` and `Documents\WindowsPowerShell` directories.
- Modify Windows Terminal's `settings.json`.
- Update the current user's global Git configuration with `git config --global`.

### Backups and safety notes

Before writing, the script creates timestamped backups of existing PowerShell profile files, the existing Starship configuration, and Windows Terminal settings when those files are present.

Please note:

- The script **does not create a backup of your global Git configuration** before changing its Delta-related values.
- `killport` and `fkill` force-stop selected processes. Check the target process before using them.
- `gi` contacts `https://www.toptal.com/developers/gitignore/api/` and may replace an existing `.gitignore` only after you type `YES`. It attempts to back up the existing file first.
- Some applications may require permissions or a restart before they are available in the terminal.
- A work computer may have policies that prevent installation or changes. Follow your organization's IT rules.

## Troubleshooting

### `winget` is not found

Install or enable **App Installer** / Windows Package Manager, then run the script again. Otherwise, install the command-line tools manually and rerun the script to configure the available parts.

### `winget` returns `-1978335189` / `0x8A15002B`

This means **no applicable update was found**. If `winget` has identified the package as already installed, the script treats this code as a non-fatal result rather than reporting a false installation failure.

### A command is not recognized

Close and reopen Windows Terminal so the updated `PATH` can load. Check that the relevant application installed successfully. Optional tools are only wired into the profile when they are available.

### PowerShell profile changes do not appear

Confirm that you opened the PowerShell profile written by the script. Windows PowerShell 5.1 and PowerShell 7 use different profile folders. Restart the shell after setup.

### Windows Terminal settings were not updated

The script prints a warning if it cannot read or update the settings file. Check the path reported in the terminal output and inspect the timestamped backup before making manual changes.

### Restore a backup

Close Windows Terminal before restoring its settings. Find the timestamped `.bak` file beside the configuration or profile you want to restore, then copy it back to its original filename. Keep a copy of the current file before restoring, in case you need to undo the restoration.

## Project structure

```text
.
├── DevSetup_Portable.ps1
└── README.md
```

## Contributing

Suggestions, bug reports, and pull requests are welcome. Please include your Windows version, PowerShell version, and any warning or error output when reporting a problem. Do not post personal paths, tokens, or other sensitive information in an issue.

## License

No license is included yet. Add a `LICENSE` file before publishing the project if you want to specify how others may use, modify, and redistribute it.
