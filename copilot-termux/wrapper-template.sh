#!/data/data/com.termux/files/usr/bin/bash
# wrapper-template.sh — قالب wrapper لتشغيل Copilot CLI على Termux
#
# يستخدم proot لاعتراض syscalls المحجوبة من Android
# مع ربط مجلد Termux الرئيسي للوصول للملفات والجلسات
#
# يُنسخ إلى $PREFIX/bin/copilot أثناء التثبيت

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
