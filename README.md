# dotnet-termux

> Smart .NET SDK manager for Termux (Android ARM64) + Copilot CLI session encryption tool

## Quick Install

```bash
bash <(curl -sL https://github.com/sbay-dev/dotnet-termux/releases/latest/download/dotnet-termux.sh) install
```

## Components

### 1. `dotnet-termux.sh` — .NET SDK Manager for Termux

Handles .NET SDK installation on Termux with automatic TLS alignment patching (required for Android Bionic linker on ARM64).

**Commands:**
| Command | Description |
|---------|-------------|
| `install [version]` | Install/upgrade .NET SDK (default: latest) |
| `patch` | Apply patchelf fix for Bionic TLS alignment |
| `status` | Show current .NET SDK status |
| `workload [name]` | Install .NET workloads |
| `run [args...]` | Run dotnet with correct environment |

**Features:**
- 🔍 Auto-detects environment (native Termux vs proot)
- 🔧 Auto-patches binary after install (patchelf + glibc loader)
- 📊 Progress bar during download
- ❌ Smart error messages with fix suggestions
- 🔄 Works as wrapper for all `dotnet` commands

### 2. SessionGuard — Copilot CLI Session Manager

A .NET console app + MCP server for encrypting, exporting, and importing GitHub Copilot CLI sessions.

**CLI Usage:**
```bash
# List sessions
dotnet run -- list

# Scan a session
dotnet run -- scan <session-id>

# Export session (encrypted)
dotnet run -- export <session-id> [output.zip]

# Import session
dotnet run -- import <path.zip> [target-copilot-root]

# Publish to GitHub
dotnet run -- publish <archive.zip> <owner> <repo>

# Run as MCP server
dotnet run -- --mcp
```

**MCP Tools (for Copilot CLI integration):**
- `session_list` — List all local sessions
- `session_scan` — Get session details
- `session_export` — Export encrypted session archive
- `session_import` — Import and decrypt session
- `session_publish` — Publish archive to GitHub release

**Encryption:**
- Uses AES-256 via [EntityCrypt.Core](https://www.nuget.org/packages/EntityCrypt.Core)
- Session ID serves as encryption key
- Sensitive data (code, events, files) encrypted at rest in SQLite
- Non-sensitive metadata (timestamps, types) stored in plaintext

### 3. `copilot-termux/` — Copilot CLI Fix for Termux

Fixes GitHub Copilot CLI (v1.0.60+) to run natively on Termux (Android ARM64). Solves the `Native addon "runtime" not found for android-arm64` error and all related glibc/seccomp issues.

```bash
cd copilot-termux && ./install.sh
```

**See [copilot-termux/README.md](copilot-termux/README.md) for full documentation.**

## Requirements

- Termux (Android ARM64) or proot-distro Ubuntu
- .NET SDK 10.0+ 
- `patchelf` (for native Termux)
- `gh` CLI (for GitHub publishing)

## Architecture

```
.copilot/
├── config.json          → ConfigRecord (tokens skipped)
├── session-state/
│   └── {uuid}/
│       ├── workspace.yaml → SessionRecord
│       ├── events.jsonl   → EventRecord[]
│       ├── files/         → FileRecord[]
│       ├── checkpoints/   → FileRecord[]
│       └── research/      → FileRecord[]
```

**Export format:** ZIP containing:
- `manifest.json` — Unencrypted metadata
- `session.db` — SQLite with AES-256 encrypted fields

## License

MIT

## Author

[@sultanaalyami](https://github.com/sultanaalyami) / [sbay-dev](https://github.com/sbay-dev)
