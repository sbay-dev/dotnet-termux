#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# dotnet-termux — Smart .NET SDK manager for Termux (ARM64)
# https://github.com/sbay-dev/dotnet-termux
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

VERSION="1.0.0"
DOTNET_DIR="${DOTNET_DIR:-$HOME/.dotnet}"
LIBS_DIR="${LIBS_DIR:-$HOME/dotnet-libs}"
INSTALL_SCRIPT_URL="https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.sh"
PATCHELF_BIN="$(command -v patchelf 2>/dev/null || echo "")"

# ─── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────
info()  { printf "${CYAN}  ℹ ${NC}%s\n" "$*"; }
ok()    { printf "${GREEN}  ✅ ${NC}%s\n" "$*"; }
warn()  { printf "${YELLOW}  ⚠️  ${NC}%s\n" "$*"; }
fail()  { printf "${RED}  ❌ ${NC}%s\n" "$*"; }
banner(){ printf "\n${BOLD}${CYAN}  ╔══════════════════════════════════════════╗${NC}\n"
          printf "${BOLD}${CYAN}  ║  🔧  dotnet-termux v${VERSION}               ║${NC}\n"
          printf "${BOLD}${CYAN}  ╚══════════════════════════════════════════╝${NC}\n\n"; }

# ─── Environment Detection ───────────────────────────────────
detect_env() {
    if [ -f /system/bin/linker64 ] && [ -d /data/data/com.termux ]; then
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
            echo "proot"
        else
            echo "termux"
        fi
    elif [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
        echo "proot"
    else
        echo "linux"
    fi
}

# ─── Progress Bar Download ────────────────────────────────────
download_with_progress() {
    local url="$1" dest="$2" label="${3:-Downloading}"
    printf "${DIM}  ⏳ %s...${NC}\n" "$label"

    if command -v curl &>/dev/null; then
        curl -fSL --progress-bar -o "$dest" "$url" 2>&1
    elif command -v wget &>/dev/null; then
        wget --show-progress -q -O "$dest" "$url" 2>&1
    else
        fail "Neither curl nor wget found"
        return 1
    fi
}

# ─── Patch ELF Interpreter ───────────────────────────────────
patch_dotnet_binary() {
    local dotnet_bin="$1"
    local glibc_ld="${LIBS_DIR}/ld-linux-aarch64.so.1"

    if [ ! -f "$glibc_ld" ]; then
        warn "glibc loader not found at $glibc_ld"
        suggest_fix "glibc-loader" "Missing glibc loader"
        return 1
    fi

    if [ -z "$PATCHELF_BIN" ]; then
        warn "patchelf not installed"
        suggest_fix "patchelf" "patchelf required for Termux"
        return 1
    fi

    local current_interp
    current_interp=$("$PATCHELF_BIN" --print-interpreter "$dotnet_bin" 2>/dev/null || echo "unknown")

    if [ "$current_interp" = "$glibc_ld" ]; then
        info "Interpreter already patched"
        return 0
    fi

    info "Patching interpreter: ${DIM}$current_interp → glibc${NC}"
    cp "$dotnet_bin" "${dotnet_bin}.pre-patch" 2>/dev/null || true
    "$PATCHELF_BIN" --set-interpreter "$glibc_ld" "$dotnet_bin"
    ok "Binary patched successfully"
}

# ─── Error Suggestions ───────────────────────────────────────
suggest_fix() {
    local scenario="$1" detail="${2:-}"
    printf "\n${YELLOW}  ┌─ 💡 Suggested Fix ──────────────────────${NC}\n"
    case "$scenario" in
        tls-alignment)
            printf "${YELLOW}  │${NC} TLS alignment error on Android Bionic\n"
            printf "${YELLOW}  │${NC} Fix: Run this script to auto-patch:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}bash dotnet-termux-update.sh patch${NC}\n"
            printf "${YELLOW}  │${NC} Or manually:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}patchelf --set-interpreter ~/dotnet-libs/ld-linux-aarch64.so.1 ~/.dotnet/dotnet${NC}\n"
            ;;
        patchelf)
            printf "${YELLOW}  │${NC} Install patchelf:\n"
            printf "${YELLOW}  │${NC}   Termux: ${CYAN}pkg install patchelf${NC}\n"
            printf "${YELLOW}  │${NC}   proot:  ${CYAN}apt install patchelf${NC}\n"
            ;;
        glibc-loader)
            printf "${YELLOW}  │${NC} glibc loader missing at ~/dotnet-libs/\n"
            printf "${YELLOW}  │${NC} Install glibc-runner:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}pkg install glibc-runner${NC}\n"
            printf "${YELLOW}  │${NC} Or copy from proot:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}cp /usr/lib/ld-linux-aarch64.so.1 ~/dotnet-libs/${NC}\n"
            ;;
        sdk-not-found)
            printf "${YELLOW}  │${NC} SDK version mismatch: $detail\n"
            printf "${YELLOW}  │${NC} Update global.json or install the required SDK:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}bash dotnet-termux-update.sh install --channel 10.0${NC}\n"
            ;;
        wasm-packs)
            printf "${YELLOW}  │${NC} WebAssembly packs outdated\n"
            printf "${YELLOW}  │${NC} Fix: Install wasm-tools workload:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}bash dotnet-termux-update.sh workload wasm-tools${NC}\n"
            printf "${YELLOW}  │${NC} In proot if direct install fails:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}proot-distro login ubuntu -- dotnet workload install wasm-tools${NC}\n"
            ;;
        restore-fail)
            printf "${YELLOW}  │${NC} NuGet restore failed: $detail\n"
            printf "${YELLOW}  │${NC} Try:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}dotnet nuget locals all --clear${NC}\n"
            printf "${YELLOW}  │${NC}   ${CYAN}dotnet restore --force${NC}\n"
            ;;
        copilot-session)
            printf "${YELLOW}  │${NC} Use Session Guard to export/import sessions:\n"
            printf "${YELLOW}  │${NC}   ${CYAN}dotnet tool install -g sbay-session-guard${NC}\n"
            printf "${YELLOW}  │${NC}   ${CYAN}session-guard export --session-id <id>${NC}\n"
            ;;
        *)
            printf "${YELLOW}  │${NC} $detail\n"
            ;;
    esac
    printf "${YELLOW}  └────────────────────────────────────────${NC}\n\n"
}

# ─── Install / Update SDK ────────────────────────────────────
do_install() {
    local channel="${1:-10.0}" quality="${2:-ga}"
    local env_type
    env_type=$(detect_env)

    banner
    info "Environment: ${BOLD}$env_type${NC}"
    info "Target: ${BOLD}$DOTNET_DIR${NC}"
    info "Channel: ${BOLD}$channel${NC}"

    # Download install script
    local tmp_script="/tmp/dotnet-install-$$.sh"
    download_with_progress "$INSTALL_SCRIPT_URL" "$tmp_script" "Fetching install script"
    chmod +x "$tmp_script"

    # Run install with progress
    printf "\n"
    info "Installing .NET SDK (channel $channel)..."
    printf "${DIM}"

    local install_env=""
    if [ "$env_type" = "termux" ]; then
        install_env="env -u LD_PRELOAD LD_LIBRARY_PATH=$LIBS_DIR DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1"
    fi

    if eval $install_env bash "$tmp_script" \
        --channel "$channel" --quality "$quality" \
        --install-dir "$DOTNET_DIR" 2>&1 | while IFS= read -r line; do
            case "$line" in
                *"Installed version"*)
                    printf "${NC}"
                    ok "$line"
                    ;;
                *"Extracting"*)
                    info "$line"
                    ;;
                *"Error"*|*"error"*)
                    printf "${NC}"
                    fail "$line"
                    ;;
                *)
                    printf "${DIM}  │ %s${NC}\n" "$line"
                    ;;
            esac
        done; then
        printf "${NC}\n"
    else
        printf "${NC}\n"
        fail "Installation failed"
        suggest_fix "generic" "Check network connectivity and try again"
        rm -f "$tmp_script"
        return 1
    fi

    rm -f "$tmp_script"

    # Auto-patch on Termux
    if [ "$env_type" = "termux" ]; then
        info "Auto-patching for Termux..."
        patch_dotnet_binary "$DOTNET_DIR/dotnet"
    fi

    # Verify
    local installed_ver
    if [ "$env_type" = "termux" ]; then
        installed_ver=$(env -u LD_PRELOAD \
            LD_LIBRARY_PATH="$LIBS_DIR" \
            DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
            "$DOTNET_DIR/dotnet" --version 2>&1) || true
    else
        installed_ver=$("$DOTNET_DIR/dotnet" --version 2>&1) || true
    fi

    if [ -n "$installed_ver" ] && [[ ! "$installed_ver" =~ error|Error ]]; then
        ok "dotnet $installed_ver ready"
    else
        fail "Verification failed: $installed_ver"
        if [[ "$installed_ver" =~ TLS|underaligned ]]; then
            suggest_fix "tls-alignment"
        fi
        return 1
    fi
}

# ─── Patch Only ───────────────────────────────────────────────
do_patch() {
    banner
    info "Patching dotnet binary..."
    patch_dotnet_binary "$DOTNET_DIR/dotnet"
}

# ─── Workload Install ────────────────────────────────────────
do_workload() {
    local workload="${1:-wasm-tools}"
    local env_type
    env_type=$(detect_env)

    banner
    info "Installing workload: $workload"

    if [ "$env_type" = "termux" ]; then
        warn "Workload install may require proot environment"
        info "Attempting via proot..."

        if command -v proot-distro &>/dev/null; then
            proot-distro login ubuntu -- bash -c \
                "DOTNET_ROOT=/opt/dotnet PATH=/opt/dotnet:\$PATH dotnet workload install $workload" 2>&1
        else
            info "proot-distro not found, trying direct install..."
            env -u LD_PRELOAD \
                LD_LIBRARY_PATH="$LIBS_DIR" \
                DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
                "$DOTNET_DIR/dotnet" workload install "$workload" 2>&1
        fi
    else
        dotnet workload install "$workload" 2>&1
    fi

    ok "Workload '$workload' installed"
}

# ─── Diagnostics ──────────────────────────────────────────────
do_status() {
    banner
    local env_type
    env_type=$(detect_env)
    info "Environment: ${BOLD}$env_type${NC}"

    local dotnet_bin="$DOTNET_DIR/dotnet"
    if [ ! -f "$dotnet_bin" ]; then
        fail "dotnet not found at $dotnet_bin"
        suggest_fix "generic" "Run: bash dotnet-termux-update.sh install"
        return 1
    fi

    # Check interpreter
    if [ -n "$PATCHELF_BIN" ]; then
        local interp
        interp=$("$PATCHELF_BIN" --print-interpreter "$dotnet_bin" 2>/dev/null || echo "?")
        info "Interpreter: $interp"
        if [ "$env_type" = "termux" ] && [[ "$interp" =~ linker64|/lib/ld ]]; then
            warn "Interpreter NOT patched for Termux!"
            suggest_fix "tls-alignment"
        fi
    fi

    # Check version
    local ver
    if [ "$env_type" = "termux" ]; then
        ver=$(env -u LD_PRELOAD \
            LD_LIBRARY_PATH="$LIBS_DIR" \
            DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
            "$dotnet_bin" --version 2>&1) || ver="ERROR"
    else
        ver=$("$dotnet_bin" --version 2>&1) || ver="ERROR"
    fi

    if [[ "$ver" =~ ^[0-9] ]]; then
        ok "SDK version: $ver"
    else
        fail "SDK check failed: $ver"
        if [[ "$ver" =~ TLS|underaligned ]]; then
            suggest_fix "tls-alignment"
        elif [[ "$ver" =~ "not found" ]]; then
            suggest_fix "sdk-not-found" "$ver"
        fi
        return 1
    fi

    # Check SDKs
    info "Installed SDKs:"
    if [ "$env_type" = "termux" ]; then
        env -u LD_PRELOAD \
            LD_LIBRARY_PATH="$LIBS_DIR" \
            DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
            "$dotnet_bin" --list-sdks 2>&1 | sed 's/^/    /'
    else
        "$dotnet_bin" --list-sdks 2>&1 | sed 's/^/    /'
    fi

    # Check glibc loader
    if [ -f "$LIBS_DIR/ld-linux-aarch64.so.1" ]; then
        ok "glibc loader: present"
    else
        warn "glibc loader: missing"
    fi

    # Check patchelf
    if [ -n "$PATCHELF_BIN" ]; then
        ok "patchelf: $PATCHELF_BIN"
    else
        warn "patchelf: not installed"
    fi
}

# ─── dotnet Wrapper ───────────────────────────────────────────
do_run() {
    local env_type
    env_type=$(detect_env)

    if [ "$env_type" = "termux" ]; then
        # Ensure binary is patched
        local interp
        interp=$("$PATCHELF_BIN" --print-interpreter "$DOTNET_DIR/dotnet" 2>/dev/null || echo "?")
        if [[ "$interp" =~ linker64|/lib/ld-linux ]]; then
            patch_dotnet_binary "$DOTNET_DIR/dotnet" 2>/dev/null
        fi

        exec env -u LD_PRELOAD \
            LD_LIBRARY_PATH="$LIBS_DIR" \
            DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
            "$DOTNET_DIR/dotnet" "$@"
    else
        exec "$DOTNET_DIR/dotnet" "$@"
    fi
}

# ─── Main ─────────────────────────────────────────────────────
main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        install|update)
            do_install "${1:-10.0}" "${2:-ga}"
            ;;
        patch)
            do_patch
            ;;
        workload)
            do_workload "${1:-wasm-tools}"
            ;;
        status|info)
            do_status
            ;;
        run)
            do_run "$@"
            ;;
        help|--help|-h)
            banner
            printf "  ${BOLD}Usage:${NC} dotnet-termux <command> [options]\n\n"
            printf "  ${BOLD}Commands:${NC}\n"
            printf "    install [channel] [quality]   Install/update .NET SDK\n"
            printf "    patch                         Patch binary for Termux\n"
            printf "    workload <name>               Install workload (via proot if needed)\n"
            printf "    status                        Show environment diagnostics\n"
            printf "    run <args...>                 Run dotnet with auto-patch\n"
            printf "\n"
            printf "  ${BOLD}Examples:${NC}\n"
            printf "    dotnet-termux install             # Latest .NET 10 GA\n"
            printf "    dotnet-termux install 10.0 ga     # Specific channel\n"
            printf "    dotnet-termux workload wasm-tools # Install WASM tools\n"
            printf "    dotnet-termux run build            # Build with auto-patch\n"
            printf "    dotnet-termux status               # Diagnostics\n"
            printf "\n"
            printf "  ${BOLD}One-liner install:${NC}\n"
            printf "    bash <(curl -sL https://github.com/sbay-dev/dotnet-termux/releases/latest/download/dotnet-termux.sh) install\n\n"
            ;;
        *)
            # Default: treat as dotnet subcommand (wrapper mode)
            do_run "$cmd" "$@"
            ;;
    esac
}

main "$@"
