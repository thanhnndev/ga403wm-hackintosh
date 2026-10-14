#!/bin/bash
# Builds AppleALC 1.9.9 with the GA403WM port resources (S4/M2) using only the
# Xcode command line tools (clang + perl), no Xcode project.
# Reference sources stay pristine: they are copied to a staging dir and patched
# there. Lilu headers are cloned once into build/ (compile-time only; the kext
# links against the Lilu already injected on the ESP at runtime).
#
#   scripts/build-applealc-ga403wm.sh
#
# Output: build/AppleALC-GA403WM.kext (drop-in replacement for AppleALC.kext;
# keep a backup of the ESP original, it is a custom 1.9.9 build with LayoutID 7).
set -euo pipefail
cd "$(dirname "$0")/.."

REF=build/AppleALC-reference
STAGE=build/AppleALC-GA403WM-src
OUT=build/AppleALC-GA403WM.kext
LILU=build/Lilu
OBJ=build/obj
SDK_DIR="${MACKERNELSDK:-build/MacKernelSDK}"
VERSION=1.9.9

[ -d "$SDK_DIR" ] || git clone --depth 1 https://github.com/acidanthera/MacKernelSDK "$SDK_DIR"
[ -d "$LILU" ] || git clone --depth 1 https://github.com/acidanthera/Lilu "$LILU"
mkdir -p "$OBJ"

echo "== stage (pristine reference + GA403WM patches) =="
rm -rf "$STAGE"; mkdir -p "$STAGE"
tar -cf - --exclude=.git -C "$REF" . | tar -xf - -C "$STAGE"
cp patches/applealc/Platforms33.xml "$STAGE/Resources/ALC285/Platforms33.xml"
python3 -I patches/applealc/patch-pinconfigs33.py \
  "$STAGE/Resources/PinConfigs.kext/Contents/Info.plist"

echo "== zlib-pack Resources (*.xml -> *.xml.zlib) =="
find "$STAGE/Resources" -name '*.xml' | while read -r f; do
  perl "$STAGE/Tools/zlib.pl" deflate "$f" > "$f.zlib"
done
echo "packed $(find "$STAGE/Resources" -name '*.xml.zlib' | wc -l | tr -d ' ') files"

echo "== ResourceConverter =="
clang++ -std=c++17 -O2 -framework Foundation -framework Cocoa \
  "$STAGE/ResourceConverter/main.mm" -o "$OBJ/ResourceConverter"
"$OBJ/ResourceConverter" "$STAGE/Resources" "$STAGE/AppleALC/kern_resources.cpp"
ls -lh "$STAGE/AppleALC/kern_resources.cpp"

echo "== compile =="
# Lilu headers live in <$LILU/Lilu/Headers/...>; -I the Lilu/ subdir.
LILU_INC="$LILU/Lilu"
COMMON="-arch x86_64 -mmacosx-version-min=12.0 -O2 -g -mkernel -fno-builtin -fno-stack-protector -nostdlib -nostdlibinc -ffreestanding -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -DHAVE_ANALOG_AUDIO=1 -DPRODUCT_NAME=AppleALC -I$SDK_DIR/Headers -I$LILU_INC"
CXXFLAGS="-std=c++17 -fapple-kext -fno-exceptions -fno-rtti"
SRCDIR="$STAGE/AppleALC"
LINK_MIN=$(otool -l "$(xcrun --show-sdk-path)/usr/lib/libkmodc++.a" 2>/dev/null | awk '/minos/ {print $2; exit}')
LINK_MIN=${LINK_MIN:-12.0}
objs=()
for src in kern_start.cpp kern_alc.cpp kern_resources.cpp ALCUserClient/ALCUserClient.cpp ALCUserClientProvider/ALCUserClientProvider.cpp; do
  o="$OBJ/alc_$(echo "$src" | tr '/.' '__').o"
  clang++ $COMMON $CXXFLAGS -I"$SRCDIR" -I"$SRCDIR/ALCUserClientProvider" -c "$SRCDIR/$src" -o "$o"
  objs+=("$o")
done

echo "== link $OUT =="
rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS"
# Xcode normally expands these build settings; without them the bundle id is the literal "$(PRODUCT_BUNDLE_IDENTIFIER)"
# and OpenCore/the kernel can never inject the kext (no built-in audio device at all).
sed -e "s/\$(MODULE_VERSION)/$VERSION/g" -e 's/\$(EXECUTABLE_NAME)/AppleALC/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/as.vit9696.AppleALC/g' -e 's/\$(PRODUCT_NAME:rfc1034identifier)/AppleALC/g' -e 's/\$(PRODUCT_NAME)/AppleALC/g' \
    "$SRCDIR/AppleALC-Info.plist" > "$OUT/Contents/Info.plist"
! grep -q '\$(' "$OUT/Contents/Info.plist" || { echo 'unexpanded build setting left in Info.plist'; exit 1; }
# merge_pinconfigs.sh equivalent: publish staged PinConfigs HDAConfigDefault
# as our own personality (stock kexts carry 663 entries here, not a PlugIns kext).
python3 -I - "$OUT/Contents/Info.plist" \
  "$STAGE/Resources/PinConfigs.kext/Contents/Info.plist" <<'EOF'
import plistlib, sys
out_p, pin_p = sys.argv[1], sys.argv[2]
out = plistlib.loads(open(out_p, 'rb').read())
pin = plistlib.loads(open(pin_p, 'rb').read())
src = pin["IOKitPersonalities"]["as.vit9696.AppleALC"]
n = len(src.get("HDAConfigDefault", []))
assert n > 600, n
out["IOKitPersonalities"]["as.vit9696.AppleALC"] = src
open(out_p, 'wb').write(plistlib.dumps(out, fmt=plistlib.FMT_XML, sort_keys=False))
print(f"merged HDAConfigDefault with {n} entries")
EOF
# Lilu plugin entry (defines AppleALC_kern_start/stop, selfInstance, debugEnabled) and the Xcode-generated kmod descriptor.
clang++ $COMMON $CXXFLAGS -I"$LILU_INC" -c "$LILU_INC/Library/plugin_start.cpp" -o "$OBJ/alc_plugin_start.o"
cat > "$OBJ/alc_kmod_info.c" <<KMOD
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(as.vit9696.AppleALC, "$VERSION", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = AppleALC_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = AppleALC_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
KMOD
clang $COMMON -c "$OBJ/alc_kmod_info.c" -o "$OBJ/alc_kmod_info.o"
objs+=("$OBJ/alc_plugin_start.o" "$OBJ/alc_kmod_info.o")
clang++ -arch x86_64 -mmacosx-version-min="$LINK_MIN" -nostdlib -Xlinker -kext -Xlinker -no_data_const \
  -L"$SDK_DIR/Library/x86_64" -lkmodc++ -lkmod -lcc_kext "${objs[@]}" -o "$OUT/Contents/MacOS/AppleALC"
file "$OUT/Contents/MacOS/AppleALC"
echo "--- undefined symbols (expect Lilu + kernel only) ---"
nm -um "$OUT/Contents/MacOS/AppleALC" | grep -v "Lilu\|lilu\|__Z" | head -n 20 || true
echo "built $OUT"
