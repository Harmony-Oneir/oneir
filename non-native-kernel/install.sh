#!/bin/bash
# Раскладка собранных компонентов OpenHarmony по путям оригинальной системы.
#
#   ./install.sh minimal              — вся минимальная система
#   ./install.sh runtime hilog samgr  — только выбранные компоненты
#   ./install.sh list                 — список компонентов
#   ./install.sh gen <файл>           — строки lib ... для всех зависимостей файла
#   ./install.sh verify               — у всех установленных ELF есть все NEEDED?
#   ./install.sh uninstall [компонент]— удалить установленное (по журналу)
#
# Скрипт можно класть в любой подкаталог дерева: корень ищется вверх по .gn и build.sh
# (или задаётся OHOS_ROOT). Профили ищутся в profile/ рядом со скриптом, затем
# в profile/ каталогов выше, до корня дерева (или задаются PROFILE_DIR).
#
# Опции (перед командой):
#   --dest DIR     корень установки (по умолчанию /; например ./rootfs для пробы)
#   --out DIR      каталог сборки (по умолчанию out/oneir)
#   --dry-run      только показать, что будет скопировано
#   --keep-going   не останавливаться на отсутствующем файле
#   --reindex      пересобрать индекс файлов сборки
#
# Каталог назначения библиотеки берётся из *_module_info.json сборки (поле dest) —
# туда, где она лежит на оригинальной системе. Если сведений нет — /system/lib64.
# Второй аргумент lib/bin задаёт каталог явно.
set -e
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$(readlink -f "$0")"; }
SELF=$(readlink -f "$0")             # абсолютный путь: дальше скрипт делает cd в корень дерева
T=$(dirname "$SELF")                 # каталог скрипта (здесь же profile/)
# Корень дерева OpenHarmony: OHOS_ROOT или первый каталог вверх от скрипта с .gn и build.sh
ROOT=${OHOS_ROOT:-}
if [ -z "$ROOT" ]; then
  d=$T
  while [ "$d" != / ]; do
    if [ -f "$d/.gn" ] && [ -f "$d/build.sh" ]; then ROOT=$d; break; fi
    d=$(dirname "$d")
  done
fi
[ -n "$ROOT" ] || { echo "не найден корень дерева OpenHarmony (задайте OHOS_ROOT)" >&2; exit 1; }
OUT=out/oneir
DEST=/
DRY=0
KEEP=0
REINDEX=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --keep-going) KEEP=1; shift ;;
    --reindex) REINDEX=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { usage; echo; echo "укажите команду, например: minimal" >&2; exit 1; }
cd "$ROOT"
DEST=${DEST%/}                      # "/" -> "", "./rootfs/" -> "./rootfs"
[ -d "$OUT" ] || { echo "нет каталога сборки $ROOT/$OUT (задайте --out)" >&2; exit 1; }
OUTABS=$(cd "$OUT" && pwd)
LIB64=/system/lib64
BIN=/system/bin
MANIFEST="$DEST/system/etc/.ohos-install.manifest"
IDX="$OUTABS/.install-index"
COMP=""                             # текущий компонент (для журнала)
ERRORS=0

# ---------------------------------------------------------------- индекс
# имя|путь в сборке|путь на системе. Строится один раз, обход out занимает время.
build_index() {
  echo "индексирую $OUT ..." >&2
  python3 - "$OUTABS" "$ROOT" > "$IDX.tmp" <<'PY'
import json, os, sys
out, root = sys.argv[1], sys.argv[2]
skip = {"lib.unstripped", "exe.unstripped", "clang_x64", "thinlto-cache", "NOTICE_FILES", "build_configs"}
bases = [out, os.path.join(root, "prebuilts/clang/ohos/linux-x86_64/llvm/lib/x86_64-linux-ohos")]
src, dest = {}, {}
def better(new, cur):
    nx, cx = "x86_64" in new, "x86_64" in cur
    return (nx and not cx) or (nx == cx and len(new) < len(cur))
for base in bases:
    for dp, dn, fn in os.walk(base):
        dn[:] = [d for d in dn if d not in skip]
        for f in fn:
            p = os.path.join(dp, f)
            if f.endswith("_module_info.json"):
                try:
                    j = json.load(open(p))
                except (OSError, ValueError):
                    continue
                s, d = j.get("source"), j.get("dest")
                if s and d:
                    d = d[0] if isinstance(d, list) else d
                    dest.setdefault(os.path.basename(s), "/" + d.lstrip("/"))
            elif (f.endswith(".so") or ".so." in f) and os.path.isfile(p):
                if f not in src or better(p, src[f]):
                    src[f] = p
for n in sorted(set(src) | set(dest)):
    print(f"{n}|{src.get(n, '')}|{dest.get(n, '')}")
PY
  mv "$IDX.tmp" "$IDX"
}
[ "$REINDEX" = 1 ] || [ ! -s "$IDX" ] && build_index
lookup() { awk -F'|' -v n="$1" '$1==n {print; exit}' "$IDX"; }

# ---------------------------------------------------------------- копирование
fail() {
  echo "  [нет] $*" >&2
  ERRORS=$((ERRORS + 1))
  [ "$KEEP" = 1 ] || { echo "остановлено (используйте --keep-going)" >&2; exit 1; }
}

record() {  # запись в журнал установки: компонент|путь
  mkdir -p "$(dirname "$MANIFEST")"
  grep -qxF "$COMP|$1" "$MANIFEST" 2>/dev/null || echo "$COMP|$1" >> "$MANIFEST"
}

put() {  # put ИСТОЧНИК КАТАЛОГ_НА_СИСТЕМЕ ИМЯ
  local src=$1 dir=$2 name=$3 dst="$DEST$2/$3"
  printf '  %-44s -> %s\n' "$name" "$dir/"
  [ "$DRY" = 1 ] && return
  install -D -m 0755 "$src" "$dst"
  record "$dir/$name"
}

lib() {  # lib ИМЯ [КАТАЛОГ]
  local name=$1 dir=$2 n src dst
  IFS='|' read -r n src dst <<< "$(lookup "$name")"
  [ -n "$src" ] || { fail "$name — не найден в сборке"; return; }
  [ -n "$dir" ] || dir=${dst%/*}
  [ -n "$dir" ] || dir=$LIB64
  put "$src" "$dir" "$name"
}

lib_from() {  # lib_from ПУТЬ [КАТАЛОГ] — библиотека по явному пути
  local src=$1 dir=${2:-$LIB64}
  [ -f "$src" ] || { fail "$src — нет файла"; return; }
  put "$src" "$dir" "$(basename "$src")"
}

bin() {  # bin ИМЯ ПУТЬ_В_OUT [КАТАЛОГ]
  local name=$1 src="$OUTABS/$2" dir=$3 n s dst
  [ -f "$src" ] || { fail "$name — нет $OUT/$2"; return; }
  if [ -z "$dir" ]; then
    IFS='|' read -r n s dst <<< "$(lookup "$name")"
    dir=${dst%/*}; [ -n "$dir" ] || dir=$BIN
  fi
  put "$src" "$dir" "$name"
}

file() {  # file ИСТОЧНИК ПУТЬ_НА_СИСТЕМЕ — обычный файл (профиль, конфиг)
  local src=$1 path=$2
  [ -f "$src" ] || { fail "$src — нет файла"; return; }
  printf '  %-44s -> %s\n' "$(basename "$src")" "$path"
  [ "$DRY" = 1 ] && return
  install -D -m 0644 "$src" "$DEST$path"
  record "$path"
}

profile() {  # путь к профилю: PROFILE_DIR, иначе profile/ рядом со скриптом или выше до корня
  local name=$1 d
  if [ -n "$PROFILE_DIR" ]; then echo "$PROFILE_DIR/$name"; return; fi
  d=$T
  while :; do
    [ -f "$d/profile/$name" ] && { echo "$d/profile/$name"; return; }
    [ "$d" = "$ROOT" ] || [ "$d" = / ] && break
    d=$(dirname "$d")
  done
  echo "$T/profile/$name"   # не найден — сообщение об ошибке покажет ожидаемый путь
}

dir() {  # dir ПУТЬ [ПРАВА] — каталог данных
  printf '  %-44s (каталог)\n' "$1"
  [ "$DRY" = 1 ] && return
  mkdir -p "$DEST$1"; chmod "${2:-0755}" "$DEST$1"
}

interp() {  # загрузчик musl по пути из PT_INTERP бинарника -> libc.so
  local elf="$OUTABS/$1" ip libc
  ip=$(readelf -l "$elf" 2>/dev/null | sed -n 's/.*interpreter: \(.*\)\]/\1/p')
  [ -n "$ip" ] || { fail "не удалось прочитать интерпретатор $1"; return; }
  libc=$(awk -F'|' '$1=="libc.so"{d=$3} END{print d}' "$IDX"); libc=${libc:-$LIB64/libc.so}
  printf '  %-44s -> %s\n' "$ip" "$libc (ссылка)"
  [ "$DRY" = 1 ] && return
  if [ -e "$DEST$ip" ] && [ ! -L "$DEST$ip" ]; then
    echo "  [пропуск] $DEST$ip уже есть и это не ссылка — не трогаю" >&2; return
  fi
  mkdir -p "$(dirname "$DEST$ip")"; ln -sfn "$libc" "$DEST$ip"
  record "$ip"
}

# ================================================================ компоненты
# Каждая строка — одна зависимость. Чего не хватает, покажет ./install.sh verify,
# готовые строки для вставки — ./install.sh gen <файл>.

comp_runtime() {  # базовые библиотеки, нужны всем процессам
  lib libc.so                          # musl libc и динамический загрузчик
  interp systemabilitymgr/safwk/sa_main
  lib libc++.so                        # стандартная библиотека C++ (LLVM)
  lib libsec_shared.z.so               # bounds_checking_function: memcpy_s и т.п.
  lib libutils.z.so                    # c_utils: RefBase, sptr, Parcel
  lib libhilog.so                      # клиент журнала
  lib libbegetutil.z.so                # init: системные параметры
  lib libipc_single.z.so               # IPC/binder (с патчем binder_invoker)
  # --- зависимости второго уровня: ./install.sh gen libipc_single.z.so
}

comp_hilog() {  # журнал
  bin hilogd hiviewdfx/hilog/hilogd
  bin hilog  hiviewdfx/hilog/hilog
  dir /data/log/hilog
}

comp_samgr() {  # реестр системных сервисов
  bin samgr systemabilitymgr/samgr/samgr
  lib libsamgr_common.z.so             # общий код, разбор профилей SA
  lib libsamgr_proxy.z.so              # клиент samgr
  dir /system/profile
  # --- зависимости второго уровня: ./install.sh gen samgr
}

comp_safwk() {  # загрузчик системных сервисов
  bin sa_main systemabilitymgr/safwk/sa_main
  lib libsystem_ability_fwk.z.so       # каркас safwk: LocalAbilityManager, SystemAbility
  # --- зависимости второго уровня: ./install.sh gen sa_main
}

comp_atm() {  # AccessTokenManager (SA 3503)
  lib libaccesstoken_manager_service.z.so   # сам сервис, libpath из профиля
  lib libaccesstoken_json_parse.z.so        # разбор nativetoken.json
  lib libaccesstoken_cjson_utils.z.so       # обёртка над cJSON
  lib libaccesstoken_common_cxx.z.so        # общий код
  lib libaccesstoken_communication_adapter_cxx.z.so  # (де)сериализация IPC
  lib libaccesstoken_sdk.z.so               # клиентский API ATM
  lib libtokenid_sdk.z.so                   # API токенов
  lib libtoken_callback_sdk.z.so            # обратные вызовы ATM
  lib libtokensetproc_shared.z.so           # token_setproc (с патчем)
  lib libpermsetproc_shared.z.so            # установка прав процесса
  file "$(profile accesstoken_service.json)" /system/profile/accesstoken_service.json
  dir /data/service/el0/access_token            # nativetoken.json
  dir /data/service/el0/access_token/bypid      # токены по pid (патч token_setproc)
  dir /data/service/el0/access_token/byname     # токены служб по имени (token_init)
  dir /data/service/el1/public/access_token     # access_token.db
  # --- зависимости второго уровня: ./install.sh gen libaccesstoken_manager_service.z.so
}

COMPONENTS="runtime hilog samgr safwk atm"
MINIMAL="runtime hilog samgr safwk atm"

# ================================================================ служебное
gen() {  # строки lib ... для всех зависимостей файла (по имени в индексе или пути)
  local start=$1 n s d
  if [ ! -f "$start" ]; then
    IFS='|' read -r n s d <<< "$(lookup "$start")"
    [ -n "$s" ] && start=$s
    [ -f "$start" ] || start=$(find "$OUTABS" -path '*unstripped*' -prune -o -name "$1" -type f -print -quit)
  fi
  [ -f "$start" ] || { echo "не найден: $1" >&2; exit 1; }
  declare -A seen; local queue=("$start") cur l
  while [ ${#queue[@]} -gt 0 ]; do
    cur=${queue[0]}; queue=("${queue[@]:1}")
    for l in $(readelf -d "$cur" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
      [ -n "${seen[$l]}" ] && continue; seen[$l]=1
      IFS='|' read -r n s d <<< "$(lookup "$l")"
      if [ -n "$s" ]; then
        d=${d%/*}
        printf '  lib %-40s # для %s -> %s\n' "$l" "$(basename "$cur")" "${d:-$LIB64}"
        queue+=("$s")
      else
        printf '  # lib %-38s # для %s — НЕ НАЙДЕН в сборке\n' "$l" "$(basename "$cur")"
      fi
    done
  done
}

verify() {  # у каждого установленного ELF есть все NEEDED в каталогах библиотек?
  local libdirs f l miss=0 total=0
  libdirs=$(find "$DEST/system/lib64" "$DEST/system/lib" -type d 2>/dev/null || true)
  [ -n "$libdirs" ] || { echo "ничего не установлено в $DEST/system"; exit 1; }
  while IFS= read -r f; do
    readelf -h "$f" >/dev/null 2>&1 || continue
    total=$((total + 1))
    for l in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
      local ok=0 d
      for d in $libdirs; do if [ -e "$d/$l" ]; then ok=1; break; fi; done
      [ "$ok" = 1 ] || { echo "  нет $l  (нужен ${f#$DEST})"; miss=$((miss + 1)); }
    done
  done < <(find "$DEST/system/bin" "$DEST/system/lib64" "$DEST/system/lib" -type f 2>/dev/null)
  echo "проверено ELF: $total, недостающих зависимостей: $miss"
  [ "$miss" = 0 ] || echo "строки для вставки: ./install.sh gen <файл>"
}

uninstall() {  # по журналу установки; без аргумента — всё
  [ -f "$MANIFEST" ] || { echo "журнала нет: $MANIFEST"; exit 0; }
  local c p keep
  keep=$(mktemp)
  while IFS='|' read -r c p; do
    if [ -z "$1" ] || [ "$c" = "$1" ]; then
      echo "  rm $p"; [ "$DRY" = 1 ] || rm -f "$DEST$p"
    else echo "$c|$p" >> "$keep"; fi
  done < "$MANIFEST"
  [ "$DRY" = 1 ] && { rm -f "$keep"; return; }
  if [ -s "$keep" ]; then mv "$keep" "$MANIFEST"; else rm -f "$keep" "$MANIFEST"; fi
}

run_comp() {
  declare -F "comp_$1" >/dev/null || { echo "нет компонента: $1 (см. list)" >&2; exit 1; }
  COMP=$1
  echo "== $1"
  "comp_$1"
}

# ================================================================ команды
if [ "$DEST" = "" ] && [ "$DRY" = 0 ] && [ "$(id -u)" != 0 ] && [[ "$1" != list && "$1" != gen ]]; then
  echo "установка в / требует root (или --dest DIR)" >&2; exit 1
fi
case "$1" in
  list)
    for c in $COMPONENTS; do
      printf '  %-8s %s\n' "$c" "$(grep -m1 "^comp_$c()" "$SELF" | sed 's/.*# *//')"
    done
    echo "  minimal = $MINIMAL" ;;
  minimal|минимальная) for c in $MINIMAL; do run_comp "$c"; done ;;
  gen) gen "$2" ;;
  verify) verify ;;
  uninstall) uninstall "$2" ;;
  *) for c in "$@"; do run_comp "$c"; done ;;
esac
[ "$ERRORS" = 0 ] || echo "пропущено из-за отсутствия: $ERRORS" >&2
