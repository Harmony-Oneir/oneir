#!/bin/bash
# Сборка целей: свой out-каталог,
# граф GN строится от выбранной цели (--root-target), собирается только она.
#
#   ./oneir/make.sh                     — oneir:atm (по умолчанию)
#   ./oneir/make.sh sa_main             — цель из oneir/BUILD.gn
#   ./oneir/make.sh tests:all           — цель из другого каталога (= //tests:all)
#   ./oneir/make.sh //base/x/y:z        — полная метка GN
#   ./oneir/make.sh base/x/y            — каталог без имени (= //base/x/y:y)
#   ./oneir/make.sh --out out/atm atm   — отдельный out-каталог
#   ./oneir/make.sh --list              — показать цели в //oneir
#   ./oneir/make.sh --reload ...        — заново прогнать loader (build_configs)
set -e
T=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$T")
OUT=out/oneir
GN=prebuilts/build-tools/linux-x86/bin/gn
NINJA=prebuilts/build-tools/linux-x86/bin/ninja
export PATH=/home/openharmony/prebuilts/python/linux-x86/current/bin:/home/openharmony/prebuilts/build-tools/common/nodejs/node-v18.20.1-linux-x64/bin:$PATH
python3 --version
python3 -c "import yaml" 2>/dev/null || python3 -m pip install pyyaml

cd "$ROOT"

RELOAD=0
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --reload) RELOAD=1; shift ;;
    --list)   LIST=1; shift ;;
    --out)    OUT=$2; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) break ;;
  esac
done
TARGET=${1:-atm}

# Метка GN: "atm" -> //oneir:atm, "tests:all" -> //tests:all, "//a/b:c" как есть
case "$TARGET" in
  //*)  LABEL=$TARGET ;;
  *:*)  LABEL=//$TARGET ;;
  */*)  LABEL=//$TARGET ;;
  *)    LABEL=//oneir:$TARGET ;;
esac
# "//a/b" без имени цели означает //a/b:b
[[ "$LABEL" == *:* ]] || LABEL="$LABEL:${LABEL##*/}"
# Имя для ninja — метка без "//"
NINJA_TARGET=${LABEL#//}

# build_configs генерирует loader; общий с tests, делаем один раз (или с --reload)
if [ ! -d out/sdk/build_configs ] || [ "$RELOAD" = 1 ]; then
  ./build.sh --product-name oneir --no-prebuilt-sdk --skip-partlist-check \
             --load-test-config false --build-only-load
fi

mkdir -p "$OUT"
# свой args.gn, если есть, иначе тот же, что у tests
if [ -f "$T/args.gn" ]; then ARGS="$T/args.gn"; else ARGS="$ROOT/tests/args.gn"; fi
cp "$ARGS" "$OUT/args.gn"
ln -sfn "$ROOT/out/sdk/build_configs" "$OUT/build_configs"

if [ "$LIST" = 1 ]; then
  $GN gen "$OUT" --root-target=//oneir:all > /dev/null
  $GN ls "$OUT" "//oneir:*"
  exit 0
fi

echo "==> $LABEL  (out: $OUT)"
$GN gen "$OUT" --root-target="$LABEL"
$NINJA -w dupbuild=warn -C "$OUT" "$NINJA_TARGET"
