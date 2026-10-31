#!/bin/bash
# Monta o Sinapse.app a partir do código e instala em Aplicativos.
set -e
cd "$(dirname "$0")"

echo ""
echo "  ◆ Sinapse — instalação"
echo ""

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "  As Ferramentas de Linha de Comando da Apple ainda não estão instaladas."
  echo "  Uma janela vai abrir pedindo para instalar: clique em Instalar,"
  echo "  espere terminar (alguns minutos) e rode este mesmo comando de novo."
  echo ""
  xcode-select --install 2>/dev/null || true
  exit 1
fi

BUILD="$(mktemp -d)"
APP="$BUILD/Sinapse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "  ▸ Compilando (leva alguns segundos)…"
xcrun swiftc -O main.swift -o "$APP/Contents/MacOS/Sinapse" \
  -framework Cocoa -framework WebKit -framework UserNotifications

cp Info.plist "$APP/Contents/Info.plist"
cp sinapse.html AppIcon.icns Assets.car "$APP/Contents/Resources/"   # Assets.car: ícone no formato novo do macOS (fonte em AppIcon.icon)

echo "  ▸ Assinando para uso neste Mac…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

DEST="/Applications"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi

echo "  ▸ Instalando em $DEST…"
osascript -e 'tell application "Sinapse" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST/Sinapse.app"
cp -R "$APP" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Sinapse.app" 2>/dev/null || true
rm -rf "$BUILD"

echo ""
echo "  ✓ Pronto! Abrindo o Sinapse…"
echo ""
open "$DEST/Sinapse.app"
