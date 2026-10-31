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



# Minimal
atm_deps=("accesstoken_cjson_utils" "accesstoken_manager_service" "accesstoken_json_parse" "accesstoken_common_cxx" "accesstoken_communication_adapter_cxx" "libaccesstoken_sdk" "libtokenid_sdk" "libtoken_callback_sdk" "libtokensetproc_shared" "libpermsetproc_shared" "libprivacy_sdk" "privacy_communication_adapter_cxx" )
hilog_deps=("libffrt" "shared_libz" "hilogd" "hilog" "libhilog" "hilog_rust" "libsandboxlog")
safwk_deps=(
  "sa_main"
  "ipc_single" "ipc_core" "ipc_common"
  "system_ability_fwk" "samgr_common" "samgr_proxy"
  "utils" "libeventhandler" "libffrt" "libhicollie"
  "libhilog" "libsandboxlog" "libhisysevent" "libhitracechain" "hitrace_meter"
  "libfaultloggerd" "libbacktrace_local" "libunwinder" "libdfx_procinfo"
  "libucollection_client"
  "libaccesstoken_sdk" "accesstoken_common_cxx" "accesstoken_communication_adapter_cxx"
  "libbegetutil" "libsystemparam" "configpolicy_util"
  "libsec_shared" "cjson" "libpcre2" "libselinux"
  "storage_manager_acl"
)
samgr_deps=("samgr" "accesstoken_common_cxx" "accesstoken_communication_adapter_cxx" "base" "cesfwk_core" "cesfwk_innerkits" "cjson" "concurrent_task_client" "configpolicy_util" "dataobs_manager" "devicemanagerjson" "devicemanagersdk" "hitrace_meter" "ipc_common" "ipc_core" "jsoncpp" "libaccesstoken_sdk" "libbacktrace_local" "libbeget_proxy" "libbegetutil" "libdbinder" "libdfx_procinfo" "libeventhandler" "libfaultloggerd" "libffrt" "libhicollie" "libhilog" "libhisysevent" "libhitracechain" "libpcre2" "libsandboxlog" "libsec_shared" "libselinux" "libsystemparam" "libucollection_client" "libunwinder" "libxml2" "native_preferences" "qos" "samgr_common" "samgr_proxy" "storage_manager_acl" "utils" "want" "zuri" )
faultloggerd_deps=("faultloggerd" "processdump" "dumpcatcher" "crashvalidator" "dfx_signalhandler" "libfaultloggerd" "libdfx_dumpcatcher" "libunwinder" "libbacktrace_local" "libstack_printer" "libjson_stack_formatter" "libasync_stack" "libdfx_procinfo" "crash_exception" "kernel_snapshot" "panic_handler" "stacktrace_rust" "rustc_demangle" )
hiview_deps=("hiview" "hiviewbase" "sys_event_service_adapter" "libfaultlogger" "eventloggerso" "libcrashvalidator" "crashvalidator" "libtrace_manager" "libucollection_client" "libucollection_utility" "xperfservice_client" "xperfservice_server" "libxpower_event" "adft" "bdfr" "bdfr_base" "analysis_faultlog" "usage_report" )
token_init_deps=("token_init")
param_service_deps=("oneir_param_service" "param" "libbegetutil" "libbeget_proxy" "libsystemparam")
param_watcher_deps=("param_watcher")
hitrace_deps=("hitrace" "libhitracechain" "hitrace_dump" "hitrace_meter" "libhitrace_option")


processdump_deps=("api_cache_manager" "appexecfwk_base" "appexecfwk_core" "base" "cesfwk_core" "cesfwk_innerkits" "cjson" "configpolicy_util" "crash_exception" "extractortool" "global_resmgr" "histogrammanager" "hitrace_meter" "ipc_common" "ipc_core" "jsoncpp" "libappexecfwk_common" "libasync_stack" "libbacktrace_local" "libbegetutil" "libdfx_procinfo" "libeventhandler" "libfaultloggerd" "libffrt" "libhicollie" "libhilog" "libhisysevent" "libhitracechain" "libpcre2" "libsandboxlog" "libsec_shared" "libselinux" "libstack_printer" "libsystemparam" "libucollection_client" "libunwinder" "samgr_proxy" "shared_icui18n" "shared_icuuc" "storage_manager_acl" "string_utils" "utils" "want" "zuri")


# CFG
hilog_cfg=("hilogd.cfg" "hilog.para" "hilog.para.dac")
atm_cfg=("access_token.rc" "access_token.para" "access_token.para.dac")
faultloggerd_cfg=("faultloggerd.cfg" "faultloggerd.para" "faultloggerd.para.dac")
hiview_cfg=("hiview.cfg" "hiview.para.dac")
hitrace_cfg=("hitrace.para" "hitrace.para.dac")
hdf_cfg=("hdf_devmgr.cfg" "hdf_devmgr.para.dac")


# Network

wpa_deps=(
   "wpa_supplicant" "wpa_cli" "wpa"
   "cjson" 
   "configpolicy_util" 
   "hostapd_hdi_client"
   "ipc_common"
   "ipc_core"
   "libbacktrace_local"
   "libbegetutil" 
   "libcrypto_shared" "libdfx_procinfo" "libfaultloggerd" "libffrt" "libhilog" "libhisysevent" "libhitracechain"
   "libhukssdk" "libnl_share" "libpcre2" "libsandboxlog" "libsec_shared" "libselinux" "libssl_shared" "libsystemparam" "libunwinder" "samgr_proxy" "utils" "wpa" "wpa_hdi_client")
hostapd_deps=("hostapd" "hostapd_cli" "libhitracechain" "libhukssdk" "libnl_share" "libpcre2" "libsandboxlog" "libsec_shared" "libselinux" )


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



# Функция для минимальной установки
install_minimal() {
   echo "Запуск минимальной установки..."
   echo "	Установка samgr"
   process_and_install_deps "${samgr_deps[@]}"

   echo "	Установка safwk"
   process_and_install_deps "${safwk_deps[@]}"
   echo "	Установка HiLog"
   process_and_install_deps "${hilog_deps[@]}"

   echo "	Установка ATM"
   process_and_install_deps "${atm_deps[@]}"

   echo "       Установка faultloggerd_deps"
   process_and_install_deps "${faultloggerd_deps[@]}"
   ln -s /data/log "$MOUNT_DIR/log"
 
   echo "       Установка hiview_deps"
   process_and_install_deps "${hiview_deps[@]}"
   # Создание сервиса для  ohos-hiview
   #echo "       Установка token_init" # init выдаёт токены сам
   #process_and_install_deps "${token_init_deps[@]}"

   #echo "       Установка param_service" # сервис параметров встроен в init
   #process_and_install_deps "${param_service_deps[@]}"


   echo "       Установка param_watcher"
   process_and_install_deps "${param_watcher_deps[@]}"

   echo "       Установка hitrace"
   process_and_install_deps "${hitrace_deps[@]}"

}


install_network() {
   echo "Установка сети..."
   echo "	Установка wpa_supplicant"
   process_and_install_deps "${wpa_deps[@]}"

   echo "	Установка hostapd (тестовая точка доступа для QEMU)"
   process_and_install_deps "${hostapd_deps[@]}"
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
ln -s /vendor       "$MOUNT_DIR/chipset"

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




# Шаг 5: конфиги init
process_and_install_deps \
  init.cfg ueventd ueventd.cfg ueventd.config init.reboot console.cfg watchdog.cfg \
  ohos.para ohos.para.dac ohos_const.para ohos.startup.para ohos.para.size \
  passwd group boot.group







# Шаг 6: тесты ядра OpenHarmony
TESTS_SRC="$OUT_DIR/tests/unittest/linux-linux"
mkdir -p "$MOUNT_DIR/system/tests"
for t in accesstokenid_test rtg_test; do
  if [[ -f "$TESTS_SRC/$t" ]]; then
    cp "$TESTS_SRC/$t" "$MOUNT_DIR/system/tests/"
    chmod 755 "$MOUNT_DIR/system/tests/$t"
    echo -e "${GREEN}+ system/tests/$t${NC}"
  else
    echo -e "${RED}Не найден: $TESTS_SRC/$t${NC}"
  fi
done


# Шаг 7: кладем профили SA

mkdir -p "$MOUNT_DIR/system/profile/"


cp ${SCRIPT_DIR}/profile/*.json "$MOUNT_DIR/system/profile/"
process_and_install_deps hdf_devmgr.cfg hiview.cfg faultloggerd.cfg hilogd.cfg console.cfg access_token.rc param_watcher.rc samgr_init graphic.rc


process_and_install_deps \
  hilog.para hilog.para.dac \
  access_token.para access_token.para.dac \
  faultloggerd.para faultloggerd.para.dac \
  hiview.para.dac \
  hitrace.para hitrace.para.dac \
  hdf_devmgr.para.dac

process_and_install_deps \
  syscap.para i18n.para i18n.para.dac libuv.para libuv.para.dac \
  Runtime.para Runtime.para.dac Interop.para Interop.para.dac \
  hichecker.para hichecker.para.dac customization.para.dac




 
install_minimal


process_and_install_deps "${processdump_deps[@]}"

# network
install_network

#process_and_install_deps "${wpa_deps[@]}"





# Шаг 4 (перенесён): файлы платы из oneir/rootfs — последними, чтобы переопределять стандартные
OVERLAY_DIR="$SCRIPT_DIR/rootfs"
if [[ -d "$OVERLAY_DIR" ]]; then
  # проверка синтаксиса JSON — init молча пропустит битый файл
  for cfg in $(find "$OVERLAY_DIR" -name "*.cfg" -o -name "*.json"); do
    jq empty "$cfg" || { echo -e "${RED}Ошибка JSON: $cfg${NC}"; exit 1; }
  done

  cp -a "$OVERLAY_DIR/." "$MOUNT_DIR/"

  # владелец — root (cp -a сохраняет uid хоста, а uid 1000 в OpenHarmony — это system)
  chown -R 0:0 "$MOUNT_DIR/vendor" "$MOUNT_DIR/system"

  # конфиги и параметры — 644, как у штатных файлов
  find "$OVERLAY_DIR" -type f \( -name "*.cfg" -o -name "*.json" -o -name "*.para" -o -name "*.conf" -o -name "fstab.*" \) \
    | sed "s|^$OVERLAY_DIR|$MOUNT_DIR|" | xargs -r chmod 644

  echo -e "${GREEN}+ файлы платы из $OVERLAY_DIR${NC}"
fi 


ls -la "$MOUNT_DIR"
echo -e "${GREEN}Готово: $FILE${NC}"
