#!/usr/bin/env bash
# fix-session.sh — إصلاح جلسات Copilot CLI التالفة
# يُعالج خطأ: Session file is corrupted (tokensRemoved: Number must be >= 0)
#
# الاستخدام:
#   ./fix-session.sh <session-id>
#   ./fix-session.sh 1e3b7178-cb31-419a-a73b-1ef5f6a0c09d
#
# يبحث في المسارات التالية بالترتيب:
#   1. ~/.copilot/session-state/<id>/events.jsonl
#   2. $COPILOT_SESSION_DIR (إذا كان مُعيّناً)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ️  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()   { echo -e "${RED}❌ $1${NC}"; }

if [ $# -lt 1 ]; then
    echo "الاستخدام: $0 <session-id>"
    echo "مثال:     $0 1e3b7178-cb31-419a-a73b-1ef5f6a0c09d"
    exit 1
fi

SESSION_ID="$1"

# البحث عن ملف الأحداث
EVENTS=""
SEARCH_PATHS=(
    "$HOME/.copilot/session-state/$SESSION_ID/events.jsonl"
    "${COPILOT_SESSION_DIR:-/nonexistent}/$SESSION_ID/events.jsonl"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        EVENTS="$path"
        break
    fi
done

if [ -z "$EVENTS" ]; then
    err "لم يتم العثور على الجلسة: $SESSION_ID"
    echo "   المسارات التي تم البحث فيها:"
    for path in "${SEARCH_PATHS[@]}"; do
        echo "   - $path"
    done
    exit 1
fi

info "ملف الأحداث: $EVENTS"
info "حجم الملف: $(du -h "$EVENTS" | cut -f1)"
info "عدد الأسطر: $(wc -l < "$EVENTS")"

# فحص القيم السالبة
NEGATIVE_COUNT=$(grep -c '"tokensRemoved":-' "$EVENTS" 2>/dev/null || echo "0")

if [ "$NEGATIVE_COUNT" -eq 0 ]; then
    ok "لا توجد قيم tokensRemoved سالبة. الملف سليم."
    exit 0
fi

warn "وُجدت $NEGATIVE_COUNT قيمة سالبة في tokensRemoved"
echo ""

# عرض القيم التالفة
info "القيم التالفة:"
grep -n '"tokensRemoved":-' "$EVENTS" | while IFS= read -r match; do
    LINE_NUM=$(echo "$match" | cut -d: -f1)
    VALUE=$(echo "$match" | grep -o '"tokensRemoved":-[0-9]*' | head -1)
    echo "   السطر $LINE_NUM: $VALUE"
done
echo ""

# نسخة احتياطية
BACKUP="${EVENTS}.bak-$(date +%Y%m%d%H%M%S)"
cp "$EVENTS" "$BACKUP"
ok "نسخة احتياطية: $BACKUP"

# الإصلاح: تصفير جميع القيم السالبة
sed -i 's/"tokensRemoved":-[0-9]\+/"tokensRemoved":0/g' "$EVENTS"

# التحقق
REMAINING=$(grep -c '"tokensRemoved":-' "$EVENTS" 2>/dev/null || echo "0")

if [ "$REMAINING" -eq 0 ]; then
    ok "تم إصلاح $NEGATIVE_COUNT قيمة بنجاح!"
    echo ""
    info "جرّب الآن:"
    echo "   copilot --resume=$SESSION_ID"
else
    err "لا تزال هناك $REMAINING قيمة سالبة. الرجاء الإصلاح يدوياً."
    exit 1
fi
