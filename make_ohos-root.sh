#!/bin/bash
# Создание образа корневой ФС OpenHarmony и установка модулей по *_module_info.json
set -e

if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root." >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)   # .../OpenHarmont7/oneir
ROOT_DIR=$(dirname "$SCRIPT_DIR")                              # .../OpenHarmont7
PROJECT_NAME="oneir"
OUT_DIR="${ROOT_DIR}/out/${PROJECT_NAME}"
IMG_NAME="ohos-root.img"
FILE="${OUT_DIR}/${IMG_NAME}"
MOUNT_DIR="/tmp/ohos-root"
SIZE=2G
REBUILD=${REBUILD:-0}          # REBUILD=1 — пересоздать образ с нуля

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
TOOLCHAIN_LIB="$ROOT_DIR/prebuilts/clang/ohos/linux-x86_64/llvm/lib"



command -v jq >/dev/null || { echo "Нужен jq: apt install jq" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Установка модулей по *_module_info.json
# Аргументы: имена модулей (как в имени файла <имя>_module_info.json)
# Ставит только пути, начинающиеся с system/ или vendor/
# ------------------------------------------------------------------------------
process_and_install_deps() {
  local item found_file source_rel src_path dest_so
  for item in "$@"; do
    # если найдено несколько — предупредить, взять первый
    mapfile -t candidates < <(find "$OUT_DIR" -type f -name "${item}_module_info.json" -not -path "*unstripped*")
    if [[ ${#candidates[@]} -eq 0 ]]; then
      echo -e "${YELLOW}Предупреждение: ${item}_module_info.json не найден${NC}"; continue
    fi
    if [[ ${#candidates[@]} -gt 1 ]]; then
      echo -e "${YELLOW}Внимание: для '${item}' найдено ${#candidates[@]} файлов, беру ${candidates[0]}${NC}"
    fi
    found_file=${candidates[0]}

    source_rel=$(jq -r '.source' "$found_file")
    src_path="${OUT_DIR}/${source_rel}"
    if [[ ! -f "$src_path" ]]; then
      echo -e "${RED}Ошибка: исходный файл не найден: ${src_path}${NC}"; continue
    fi

    while IFS= read -r dest_so; do
      [[ -z "$dest_so" ]] && continue
      case "$dest_so" in system/*|vendor/*) ;; *) continue ;; esac   # только system/ и vendor/
      mkdir -p "$(dirname "${MOUNT_DIR}/${dest_so}")"
      if cp -f "$src_path" "${MOUNT_DIR}/${dest_so}"; then
        echo -e "${GREEN}+ ${dest_so}${NC}"
      else
        echo -e "${RED}Ошибка: не удалось скопировать в ${dest_so}${NC}"
      fi
    done < <(jq -r '.dest[]?' "$found_file")
  done
}

# ------------------------------------------------------------------------------
# Подготовка образа
# ------------------------------------------------------------------------------
if mountpoint -q "$MOUNT_DIR"; then
  echo "Каталог $MOUNT_DIR уже смонтирован. Выполните: cd / && umount $MOUNT_DIR" >&2
  exit 1
fi

if [[ -e "$FILE" && "$REBUILD" != 1 ]]; then
  echo "Образ уже существует: $FILE (для пересоздания: REBUILD=1 $0)" >&2
  exit 1
fi

rm -f "$FILE"
truncate -s "$SIZE" "$FILE"
mkfs.ext4 -q -L ohos-root "$FILE"
file "$FILE"



# Образ /data — создаётся один раз, при REBUILD не трогается
USERDATA="${OUT_DIR}/userdata.img"
if [[ ! -e "$USERDATA" ]]; then
  truncate -s 4G "$USERDATA"
  mkfs.ext4 -q -L userdata "$USERDATA"
  echo -e "${GREEN}Создан образ /data: $USERDATA${NC}"
fi




mkdir -p "$MOUNT_DIR"
mount -o loop "$FILE" "$MOUNT_DIR"
trap 'cd /; umount "$MOUNT_DIR" 2>/dev/null || true' EXIT   # отмонтировать при любом выходе

# Скелет
mkdir -p "$MOUNT_DIR"/system/{bin,lib,lib64,etc/init,etc/param}
mkdir -p "$MOUNT_DIR"/{vendor,data,dev,proc,sys,mnt,tmp,storage}
ln -s /system/bin   "$MOUNT_DIR/bin"
ln -s /system/lib   "$MOUNT_DIR/lib"
ln -s /system/lib64 "$MOUNT_DIR/lib64"
ln -s /system/etc   "$MOUNT_DIR/etc"

# Модули (пример — дополняйте список)
# process_and_install_deps init ueventd begetctl sh toybox




# Шаг 1: загрузчик musl, его конфиг и sh
cp "$OUT_DIR/common/common/libc/ld-musl-x86_64.so.1" "$MOUNT_DIR/system/lib/"
cp "$OUT_DIR/obj/third_party/musl/third_party/musl/config/ld-musl-namespace-x86_64.ini" "$MOUNT_DIR/system/etc/"
cp "$OUT_DIR/thirdparty/mksh/sh" "$MOUNT_DIR/system/bin/"
chmod 755 "$MOUNT_DIR/system/lib/ld-musl-x86_64.so.1" "$MOUNT_DIR/system/bin/sh"


# Шаг 2: toybox и ссылки на его команды
cp "$OUT_DIR/thirdparty/toybox/toybox" "$MOUNT_DIR/system/bin/"
chmod 755 "$MOUNT_DIR/system/bin/toybox"

LDMUSL="$MOUNT_DIR/system/lib/ld-musl-x86_64.so.1"
for cmd in $("$LDMUSL" "$MOUNT_DIR/system/bin/toybox"); do
  # не перезаписывать существующие файлы (например, sh из mksh)
  [ -e "$MOUNT_DIR/system/bin/$cmd" ] || ln -s toybox "$MOUNT_DIR/system/bin/$cmd"
done
echo "toybox: $(ls "$MOUNT_DIR/system/bin" | wc -l) команд в /system/bin"



# Шаг 3: init, его утилиты и библиотеки
cp "$OUT_DIR"/startup/init/{init,ueventd,begetctl,param} "$MOUNT_DIR/system/bin/"
chmod 755 "$MOUNT_DIR"/system/bin/{init,ueventd,begetctl,param}
cp "$OUT_DIR"/startup/init/*.z.so "$MOUNT_DIR/system/lib64/"

cp "$TOOLCHAIN_LIB/x86_64-linux-ohos/libc++.so" "$MOUNT_DIR/system/lib64/libc++.so"
cp "$TOOLCHAIN_LIB/clang/15.0.4/lib/x86_64-linux-ohos/libclang_rt.ubsan_minimal.so" "$MOUNT_DIR/system/lib64/libclang_rt.ubsan_minimal.so"

process_and_install_deps configpolicy_util libhisysevent libsec_shared libhilog libhitracechain libsandboxlog cjson




# Шаг 4: файлы платы из oneir/rootfs (накладываются поверх образа)
OVERLAY_DIR="$SCRIPT_DIR/rootfs"
if [[ -d "$OVERLAY_DIR" ]]; then
  # проверка синтаксиса всех .cfg — init молча пропустит битый JSON
  for cfg in $(find "$OVERLAY_DIR" -name "*.cfg"); do
    jq empty "$cfg" || { echo -e "${RED}Ошибка JSON: $cfg${NC}"; exit 1; }
  done
  cp -a "$OVERLAY_DIR/." "$MOUNT_DIR/"
  echo -e "${GREEN}+ файлы платы из $OVERLAY_DIR${NC}"
fi


# Шаг 5: конфиги init
process_and_install_deps \
  init.cfg ueventd ueventd.cfg console.cfg watchdog.cfg \
  ohos.para ohos.para.dac ohos_const.para ohos.startup.para ohos.para.size \
  passwd group boot.group







# Шаг 6: тесты ядра OpenHarmony
TESTS_SRC="$OUT_DIR/tests/unittest/linux-linux"
mkdir -p "$MOUNT_DIR/system/tests"
for t in accesstokenid_test; do
  if [[ -f "$TESTS_SRC/$t" ]]; then
    cp "$TESTS_SRC/$t" "$MOUNT_DIR/system/tests/"
    chmod 755 "$MOUNT_DIR/system/tests/$t"
    echo -e "${GREEN}+ system/tests/$t${NC}"
  else
    echo -e "${RED}Не найден: $TESTS_SRC/$t${NC}"
  fi
done


ls -la "$MOUNT_DIR"
echo -e "${GREEN}Готово: $FILE${NC}"
