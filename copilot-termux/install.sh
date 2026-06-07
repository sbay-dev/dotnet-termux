#!/data/data/com.termux/files/usr/bin/bash
# install.sh — تثبيت GitHub Copilot CLI على Termux (Android ARM64)
#
# يُثبّت Copilot CLI ويُهيّئه للعمل مباشرة من Termux
# عبر proot + glibc Node.js + Ubuntu rootfs libraries
#
# الاستخدام: ./install.sh
# أو:       bash <(curl -sL https://raw.githubusercontent.com/sbay-dev/dotnet-termux/main/copilot-termux/install.sh)

set -e

# ─── ألوان ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}✅ $1${NC}"; }
info()  { echo -e "${BLUE}ℹ️  $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
step()  { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }

# ─── ثوابت ───
UBUNTU_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"
COPILOT_DIR="$UBUNTU_ROOT/usr/local/lib/node_modules/@github/copilot"
COPILOT_APP="$COPILOT_DIR/app.js"
NODE_DIR="$HOME/.copilot-node"
NODE_VERSION="v22.16.0"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-arm64.tar.xz"
WRAPPER_PATH="$PREFIX/bin/copilot"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   GitHub Copilot CLI — Termux Installer           ║"
echo "║   تثبيت كوبايلوت على تيرموكس                      ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── الخطوة 0: فحص المتطلبات ───
step "الخطوة 0/5: فحص المتطلبات"

# التحقق من Termux
if [ -z "$PREFIX" ] || [[ "$PREFIX" != *"com.termux"* ]]; then
    error "هذا السكربت مُصمّم لـ Termux فقط"
fi
log "بيئة Termux"

# التحقق من proot
if ! command -v proot &>/dev/null; then
    info "تثبيت proot..."
    pkg install -y proot >/dev/null 2>&1
fi
log "proot متوفر"

# التحقق من proot-distro
if ! command -v proot-distro &>/dev/null; then
    info "تثبيت proot-distro..."
    pkg install -y proot-distro >/dev/null 2>&1
fi
log "proot-distro متوفر"

# التحقق من Ubuntu rootfs
if [ ! -d "$UBUNTU_ROOT" ]; then
    info "تثبيت Ubuntu عبر proot-distro (قد يستغرق وقتاً)..."
    proot-distro install ubuntu
fi
log "Ubuntu rootfs موجود"

# التحقق من Node.js على Termux
if ! command -v node &>/dev/null; then
    info "تثبيت Node.js..."
    pkg install -y nodejs >/dev/null 2>&1
fi
log "Node.js (Termux): $(node --version 2>/dev/null)"

# التحقق من gh CLI
if ! command -v gh &>/dev/null; then
    warn "gh CLI غير مُثبّت — ثبّته لاحقاً: pkg install gh"
fi

# ─── الخطوة 1: تثبيت Copilot CLI في Ubuntu rootfs ───
step "الخطوة 1/5: تثبيت Copilot CLI"

# تثبيت Node.js داخل Ubuntu إن لم يكن موجوداً
if [ ! -f "$UBUNTU_ROOT/usr/bin/node" ]; then
    info "تثبيت Node.js داخل Ubuntu rootfs..."
    proot-distro login ubuntu -- bash -c "apt update -qq && apt install -y -qq nodejs npm" 2>/dev/null
fi

# تثبيت/تحديث Copilot CLI
info "تثبيت @github/copilot داخل Ubuntu rootfs..."
proot-distro login ubuntu -- bash -c "npm install -g @github/copilot --force 2>&1" | tail -3
log "Copilot CLI مُثبّت"

# ─── الخطوة 2: ترقيع app.js ───
step "الخطوة 2/5: ترقيع app.js لدعم Android"

COPILOT_APP="$UBUNTU_ROOT/usr/local/lib/node_modules/@github/copilot/app.js"

if [ ! -f "$COPILOT_APP" ]; then
    error "لم يتم العثور على app.js في: $COPILOT_APP"
fi

if [ -f "$SCRIPT_DIR/patch-app.sh" ]; then
    bash "$SCRIPT_DIR/patch-app.sh" "$COPILOT_APP"
else
    # ترقيع مُضمّن في حال التشغيل بدون المستودع
    info "تطبيق الترقيعات مباشرة..."

    [ ! -f "$COPILOT_APP.bak-android" ] && cp "$COPILOT_APP" "$COPILOT_APP.bak-android"

    # Patch 1: oVo() — case switch للمنصة
    grep -q 'case"android":case"linux"' "$COPILOT_APP" 2>/dev/null || \
        sed -i 's/case"linux":return`linux-${e}-${OVe()}`/case"android":case"linux":return`linux-${e}-${OVe()}`/' "$COPILOT_APP"

    # Patch 2: BVe() — بادئة المنصة
    grep -q 't==="android"?"linux":t}' "$COPILOT_APP" 2>/dev/null || \
        sed -i 's/t==="linux"\&\&r==="musl"?"linuxmusl":t}/t==="linux"\&\&r==="musl"?"linuxmusl":t==="android"?"linux":t}/' "$COPILOT_APP"

    # Patch 3: OVe() — كشف libc
    grep -q '!=="android"?"gnu"' "$COPILOT_APP" 2>/dev/null || \
        sed -i 's/(t.platform??process.platform)!=="linux"?"gnu"/(t.platform??process.platform)!=="linux"\&\&(t.platform??process.platform)!=="android"?"gnu"/' "$COPILOT_APP"

    # Patch 4: pme() — كشف musl
    grep -q 'process.platform==="android"' "$COPILOT_APP" 2>/dev/null || \
        sed -i 's/process.platform==="linux"\&\&OVe()==="musl"/(process.platform==="linux"||process.platform==="android")\&\&OVe()==="musl"/' "$COPILOT_APP"

    log "تم تطبيق الترقيعات"
fi

# ─── الخطوة 3: تنزيل Node.js 22 (linux-arm64) ───
step "الخطوة 3/5: تنزيل Node.js 22 (linux-arm64)"

if [ -f "$NODE_DIR/bin/node" ]; then
    CURRENT_NODE_VER=$("$UBUNTU_ROOT/lib/ld-linux-aarch64.so.1" "$NODE_DIR/bin/node" -e "console.log(process.version)" 2>/dev/null || echo "unknown")
    if [[ "$CURRENT_NODE_VER" == v22.* ]] || [[ "$CURRENT_NODE_VER" == v24.* ]]; then
        log "Node.js $CURRENT_NODE_VER موجود مسبقاً"
    else
        info "تحديث Node.js إلى $NODE_VERSION..."
        rm -rf "$NODE_DIR"
    fi
fi

if [ ! -f "$NODE_DIR/bin/node" ]; then
    info "تنزيل Node.js $NODE_VERSION..."
    mkdir -p "$NODE_DIR"
    curl -sL "$NODE_URL" -o /tmp/node-arm64.tar.xz
    tar xf /tmp/node-arm64.tar.xz -C "$NODE_DIR" --strip-components=1
    rm -f /tmp/node-arm64.tar.xz
    log "Node.js $NODE_VERSION مُثبّت في $NODE_DIR"
fi

# ─── الخطوة 4: إنشاء wrapper script ───
step "الخطوة 4/5: إنشاء wrapper script"

cat > "$WRAPPER_PATH" << 'COPILOT_WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
# GitHub Copilot CLI — Termux Wrapper
# Generated by copilot-termux installer
# https://github.com/sbay-dev/dotnet-termux/tree/main/copilot-termux

UBUNTU_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"
NODE22="/data/data/com.termux/files/home/.copilot-node/bin/node"
COPILOT_APP="/usr/local/lib/node_modules/@github/copilot/app.js"
TERMUX_HOME="/data/data/com.termux/files/home"

export LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu
exec proot \
  -r "$UBUNTU_ROOT" \
  -b "$TERMUX_HOME":/root \
  -b "$TERMUX_HOME":"$TERMUX_HOME" \
  -b /dev:/dev \
  -b /proc:/proc \
  -b /sys:/sys \
  -w /root \
  "$NODE22" "$COPILOT_APP" "$@"
COPILOT_WRAPPER

chmod +x "$WRAPPER_PATH"
log "wrapper مُثبّت في $WRAPPER_PATH"

# ─── الخطوة 5: اختبار ───
step "الخطوة 5/5: اختبار التثبيت"

VERSION_OUTPUT=$(copilot --version 2>&1)
if echo "$VERSION_OUTPUT" | grep -q "GitHub Copilot CLI"; then
    log "$(echo "$VERSION_OUTPUT" | head -1)"
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   🎉 تم التثبيت بنجاح!                           ║${NC}"
    echo -e "${GREEN}║                                                   ║${NC}"
    echo -e "${GREEN}║   شغّل: copilot                                   ║${NC}"
    echo -e "${GREEN}║   أو:   copilot -p \"سؤالك هنا\"                    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
else
    warn "التثبيت قد لا يكون مكتملاً. المخرجات:"
    echo "$VERSION_OUTPUT"
    echo ""
    info "جرّب تشغيل: copilot --version"
fi
