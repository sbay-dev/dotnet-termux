#!/data/data/com.termux/files/usr/bin/bash
# patch-app.sh — ترقيع Copilot CLI app.js لدعم Android/Termux
#
# يُعالج 4 دوال في app.js تفحص process.platform:
#   1. oVo()  — تحويل المنصة لاسم ملف (case switch)
#   2. BVe()  — بادئة المنصة (linux/linuxmusl)
#   3. OVe()  — كشف عائلة libc (gnu/musl)
#   4. pme()  — كشف musl
#
# الاستخدام: ./patch-app.sh [مسار app.js]

set -e

APP_JS="${1:-}"

if [ -z "$APP_JS" ]; then
    # محاولة العثور على app.js تلقائياً
    UBUNTU_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"
    for path in \
        "$UBUNTU_ROOT/usr/local/lib/node_modules/@github/copilot/app.js" \
        "$PREFIX/lib/node_modules/@github/copilot/app.js" \
        "$HOME/node_modules/@github/copilot/app.js"; do
        if [ -f "$path" ]; then
            APP_JS="$path"
            break
        fi
    done
fi

if [ -z "$APP_JS" ] || [ ! -f "$APP_JS" ]; then
    echo "❌ لم يتم العثور على app.js"
    echo "   الاستخدام: $0 [مسار app.js]"
    exit 1
fi

echo "📄 ملف: $APP_JS"

# نسخة احتياطية
if [ ! -f "$APP_JS.bak-android" ]; then
    cp "$APP_JS" "$APP_JS.bak-android"
    echo "📋 نسخة احتياطية: app.js.bak-android"
fi

PATCHED=0

# ─── Patch 1: oVo() — إضافة case "android" قبل case "linux" ───
if grep -q 'case"android":case"linux"' "$APP_JS" 2>/dev/null; then
    echo "✅ [1/4] oVo() مُرقّع مسبقاً"
else
    sed -i 's/case"linux":return`linux-${e}-${OVe()}`/case"android":case"linux":return`linux-${e}-${OVe()}`/' "$APP_JS"
    if grep -q 'case"android":case"linux"' "$APP_JS"; then
        echo "✅ [1/4] oVo() — تم الترقيع"
        PATCHED=$((PATCHED + 1))
    else
        echo "⚠️  [1/4] oVo() — فشل الترقيع"
    fi
fi

# ─── Patch 2: BVe() — معاملة android كـ linux ───
if grep -q 't==="android"?"linux":t}' "$APP_JS" 2>/dev/null; then
    echo "✅ [2/4] BVe() مُرقّع مسبقاً"
else
    sed -i 's/t==="linux"\&\&r==="musl"?"linuxmusl":t}/t==="linux"\&\&r==="musl"?"linuxmusl":t==="android"?"linux":t}/' "$APP_JS"
    if grep -q 't==="android"?"linux":t}' "$APP_JS"; then
        echo "✅ [2/4] BVe() — تم الترقيع"
        PATCHED=$((PATCHED + 1))
    else
        echo "⚠️  [2/4] BVe() — فشل الترقيع"
    fi
fi

# ─── Patch 3: OVe() — كشف libc لمنصة Android ───
if grep -q '!=="android"?"gnu"' "$APP_JS" 2>/dev/null; then
    echo "✅ [3/4] OVe() مُرقّع مسبقاً"
else
    sed -i 's/(t.platform??process.platform)!=="linux"?"gnu"/(t.platform??process.platform)!=="linux"\&\&(t.platform??process.platform)!=="android"?"gnu"/' "$APP_JS"
    if grep -q '!=="android"?"gnu"' "$APP_JS"; then
        echo "✅ [3/4] OVe() — تم الترقيع"
        PATCHED=$((PATCHED + 1))
    else
        echo "⚠️  [3/4] OVe() — فشل الترقيع"
    fi
fi

# ─── Patch 4: pme() — كشف musl لمنصة Android ───
if grep -q '(process.platform==="linux"||process.platform==="android")&&OVe()==="musl"' "$APP_JS" 2>/dev/null; then
    echo "✅ [4/4] pme() مُرقّع مسبقاً"
else
    sed -i 's/process.platform==="linux"\&\&OVe()==="musl"/(process.platform==="linux"||process.platform==="android")\&\&OVe()==="musl"/' "$APP_JS"
    if grep -q 'process.platform==="android"' "$APP_JS"; then
        echo "✅ [4/4] pme() — تم الترقيع"
        PATCHED=$((PATCHED + 1))
    else
        echo "⚠️  [4/4] pme() — فشل الترقيع"
    fi
fi

echo ""
if [ "$PATCHED" -gt 0 ]; then
    echo "🎉 تم تطبيق $PATCHED ترقيع(ات) جديدة"
else
    echo "ℹ️  جميع الترقيعات مُطبّقة مسبقاً"
fi
echo ""
echo "💡 لاستعادة النسخة الأصلية:"
echo "   cp $APP_JS.bak-android $APP_JS"
