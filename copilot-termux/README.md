# Copilot CLI on Termux — Complete Fix

> تشغيل GitHub Copilot CLI (v1.0.60+) مباشرة على Termux (Android ARM64) بدون الحاجة للدخول إلى proot-distro

## المشكلة

عند تثبيت Copilot CLI على Termux بالطريقة العادية (`npm install -g @github/copilot`)، يفشل التشغيل بالخطأ:

```
Error: Native addon "runtime" not found for android-arm64
```

### تسلسل المشكلة وجذرها

Copilot CLI v1.0.60 يعتمد على native addon مُترجم مسبقاً (`runtime.node`) وهو ملف ELF مبني لنظام Linux القياسي. عند تشغيله على Termux تظهر سلسلة من المشاكل المتتابعة:

```
المشكلة 1: كشف المنصة
├─ process.platform يُرجع "android" بدلاً من "linux"
├─ الكود يبحث عن prebuilds/android-arm64/ وهو غير موجود
└─ الحل: ترقيع app.js لمعاملة android كـ linux

المشكلة 2: المكتبات الأصلية (Native Libraries)
├─ runtime.node مبني ضد glibc (GNU C Library)
├─ Termux يستخدم Bionic (Android C Library)
├─ لا يمكن خلط glibc و Bionic في نفس العملية
└─ الحل: استخدام Node.js مبني ضد glibc مع Ubuntu rootfs libraries

المشكلة 3: libc.so Linker Scripts
├─ Ubuntu يستخدم usrmerge (/lib → /usr/lib)
├─ libc.so ملف نصي (linker script) وليس مكتبة ELF
├─ Dynamic linker يفشل عند محاولة تحميله
└─ الحل: تخطّيه - المكتبات الحقيقية هي .so.6

المشكلة 4: LD_PRELOAD التعارض
├─ Termux يحقن libtermux-exec-ld-preload.so عبر LD_PRELOAD
├─ هذه المكتبة مبنية ضد Bionic وتتعارض مع glibc
└─ الحل: إلغاء LD_PRELOAD عند التشغيل

المشكلة 5: Seccomp و Syscalls
├─ Android يحجب بعض system calls عبر seccomp filters
├─ glibc Node.js يستخدم syscalls محجوبة → Signal 31 (SIGSYS)
└─ الحل: استخدام proot لاعتراض syscalls المحجوبة
```

### الحل الجذري

استخدام **proot خفيف** (بدون proot-distro الكامل) لتشغيل Node.js 22 المبني لـ Linux مع مكتبات Ubuntu، مع ربط مجلد Termux الرئيسي لإبقاء الملفات والجلسات متاحة:

```
Termux Shell
  └─ copilot (wrapper script)
       └─ proot (syscall interception فقط)
            └─ Ubuntu rootfs (مكتبات glibc)
                 └─ Node.js 22 linux-arm64
                      └─ Copilot CLI app.js (مُرقّع)
                           └─ runtime.node (يعمل بنجاح)
```

## المتطلبات

| المتطلب | الأمر |
|---------|-------|
| Termux (Android ARM64) | — |
| proot-distro مع Ubuntu | `pkg install proot-distro && proot-distro install ubuntu` |
| Node.js على Termux | `pkg install nodejs` |
| GitHub CLI | `pkg install gh` |

## التثبيت السريع

```bash
# تثبيت بخطوة واحدة
bash <(curl -sL https://raw.githubusercontent.com/sbay-dev/dotnet-termux/main/copilot-termux/install.sh)
```

### أو تثبيت يدوي

```bash
git clone https://github.com/sbay-dev/dotnet-termux.git
cd dotnet-termux/copilot-termux
chmod +x install.sh
./install.sh
```

## ماذا يفعل سكربت التثبيت

1. **يتحقق** من المتطلبات (proot-distro، Ubuntu rootfs)
2. **يُثبّت Copilot CLI** داخل Ubuntu rootfs عبر npm
3. **يُرقّع `app.js`** لدعم منصة Android (4 ترقيعات)
4. **يُنزّل Node.js 22** (linux-arm64) لدعم `node:sqlite`
5. **يُنشئ wrapper script** في `$PREFIX/bin/copilot`
6. **يختبر** التثبيت تلقائياً

## البنية

```
copilot-termux/
├── README.md              # هذا الملف - التوثيق الكامل
├── install.sh             # سكربت التثبيت الرئيسي
├── patch-app.sh           # ترقيع app.js لمنصة Android
└── wrapper-template.sh    # قالب wrapper script
```

## استكشاف الأخطاء

### الخطأ: `Native addon "runtime" not found for android-arm64`
**السبب:** app.js غير مُرقّع
**الحل:**
```bash
cd dotnet-termux/copilot-termux && ./patch-app.sh
```

### الخطأ: `libc.so: invalid ELF header`
**السبب:** LD_LIBRARY_PATH يشير لمجلد يحتوي linker scripts
**الحل:** السكربت يتعامل مع هذا تلقائياً عبر proot

### الخطأ: `Unknown signal 31`
**السبب:** Android seccomp يحجب syscalls
**الحل:** استخدام proot (مُضمّن في wrapper)

### الخطأ: `ERR_UNKNOWN_BUILTIN_MODULE: node:sqlite`
**السبب:** إصدار Node.js قديم (أقل من 22)
**الحل:** السكربت ينزّل Node.js 22 تلقائياً

## التحديث

عند تحديث Copilot CLI، أعد تشغيل سكربت التثبيت:

```bash
cd dotnet-termux/copilot-termux && ./install.sh
```

## المعلومات التقنية

| المكون | التفاصيل |
|--------|----------|
| Copilot CLI | v1.0.60 |
| Node.js | v22.x (linux-arm64, glibc) |
| نظام الملفات | Ubuntu rootfs عبر proot |
| المنصة | Android ARM64 (Termux) |
| Syscall Interception | proot |

## المؤلف

[@sultanaalyami](https://github.com/sultanaalyami) / [sbay-dev](https://github.com/sbay-dev)

## الترخيص

MIT
