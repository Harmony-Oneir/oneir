#!/bin/bash
# Создаёт кросс-файл meson и .pc-файлы для сборки Mesa (anv) под OpenHarmony x86_64.
# Штатный ohos/meson_cross_process64.py рассчитан на aarch64, поэтому свой генератор.
#
# Особенности Mesa из дерева OpenHarmony при сборке под x86_64:
#   0. Mesa собирается с -Dplatforms=ohos: так src/util/meson.build подключает
#      sys_param.cpp (флаг трассировки open_mesa3d_trace) и зависимости libhilog,
#      libhitrace, libbegetutil, libqos — для них этот скрипт создаёт .pc-файлы.
#   1. Под OHOS (компилятор сам задаёт __OHOS__) Mesa использует hitrace, hilog,
#      системные параметры init (sys_param.h) — src/util/perf/cpu_trace.h,
#      src/util/meson.build — и QoS потоков из qos_manager (C-API NDK: qos.h с
#      OH_QoS_SetThreadQoS, не C++ inner_api) — src/util/u_queue.c.
#      Пути и библиотеки для них прописываются этим скриптом.
#   2. src/util/u_mm.c: memcpy_neon() на инструкциях ARM NEON подключается по
#      условию DETECT_OS_OHOS без проверки архитектуры и не собирается под x86_64.
#      Нужен патч исходников (не этот скрипт): в строках с
#      "#if DETECT_OS_OHOS" у #include <arm_neon.h> и в начале memcpy_neon()
#      условие заменить на
#      "#if DETECT_OS_OHOS && (defined(__aarch64__) || defined(__ARM_NEON))",
#      тогда на x86_64 используется ветка #else (обычное копирование).
#      Патч: oneir_patches/mesa_x86_64_no_neon.patch
#   3. src/intel/compiler/brw_compile_fs.cpp использует std::min без
#      #include <algorithm>: с libc++ из OpenHarmony clang заголовок не подключается
#      транзитивно. Нужен патч исходников — добавить #include <algorithm>.
#      Патч: oneir_patches/mesa_libcxx_algorithm.patch
#   4. В musl OpenHarmony нет pthread_cancel/pthread_setcanceltype, которые
#      использует src/vulkan/wsi/wsi_common_display.c (VK_KHR_display — вывод
#      напрямую через KMS, OpenHarmony он не нужен). Как для Android, файл и
#      -DVK_USE_PLATFORM_DISPLAY_KHR исключаются при with_platform_ohos:
#      src/vulkan/wsi/meson.build и src/vulkan/meson.build.
#      Патч: oneir_patches/mesa_ohos_no_wsi_display.patch
#
# Запуск в контейнере сборки OpenHarmony:
#   ./gen_mesa_cross_x86_64.sh [корень дерева] [каталог сборки]
# по умолчанию: /home/openharmony  out/oneir
set -eu

ROOT=${1:-/home/openharmony}
OUT=${2:-out/oneir}
OUTDIR="$ROOT/$OUT"
DST="$OUTDIR/thirdparty/mesa3d-vk"
LLVM="$ROOT/prebuilts/clang/ohos/linux-x86_64/llvm/bin"
SYSROOT="$OUTDIR/obj/third_party/musl"

[ -x "$LLVM/clang" ] || { echo "нет компилятора: $LLVM/clang"; exit 1; }
[ -d "$SYSROOT/usr/include" ] || { echo "нет sysroot musl: $SYSROOT (соберите что-нибудь под ohos x86_64)"; exit 1; }

find_lib() {  # первое найденное из списка имён (в OpenHarmony разделяемые библиотеки часто *.z.so)
  for name in "$@"; do
    f=$(find "$OUTDIR" -name "$name" -not -path "*unstripped*" 2>/dev/null | head -1)
    [ -n "$f" ] && { echo "$f"; return; }
  done
}

link_flags() {  # флаги линковки для найденного файла библиотеки
  echo "-L$(dirname "$1") -l:$(basename "$1")"
}

LIBDRM=$(find_lib libdrm.so libdrm.z.so)
LIBZ=$(find_lib libz.so libz.z.so libshared_libz.z.so libz.a)
[ -n "$LIBDRM" ] || { echo "не найден libdrm в $OUTDIR — соберите //third_party/libdrm:libdrm"; exit 1; }
[ -n "$LIBZ" ]   || { echo "не найден zlib в $OUTDIR (искал libz.so, libz.z.so, libshared_libz.z.so, libz.a)"; exit 1; }

# Mesa из дерева OpenHarmony при сборке под OHOS (__OHOS__) использует hitrace, hilog
# и системные параметры init (sys_param.h) — см. src/util/perf/cpu_trace.h.
LIBHITRACE=$(find_lib libhitrace_meter.so libhitrace_meter.z.so)
LIBHILOG=$(find_lib libhilog.so libhilog.z.so)
LIBBEGET=$(find_lib libbegetutil.z.so libbegetutil.so)
[ -n "$LIBHITRACE" ] || { echo "не найден libhitrace_meter — соберите hitrace:hitrace_meter"; exit 1; }
[ -n "$LIBHILOG" ]   || { echo "не найден libhilog — соберите hilog:libhilog"; exit 1; }
[ -n "$LIBBEGET" ]   || { echo "не найден libbegetutil — соберите init:libbegetutil"; exit 1; }

HITRACE_INC="$ROOT/base/hiviewdfx/hitrace/interfaces/native/innerkits/include"
HILOG_INC="$ROOT/base/hiviewdfx/hilog/interfaces/native/innerkits/include"
SYSPARAM_H=$(find "$ROOT/base/startup/init" -name sys_param.h 2>/dev/null | head -1)
[ -n "$SYSPARAM_H" ] || { echo "не найден sys_param.h в base/startup/init"; exit 1; }
SYSPARAM_INC=$(dirname "$SYSPARAM_H")

# Mesa (u_queue.c) вызывает OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE) — это C-API NDK.
# В qos_manager есть два qos.h: C++ inner_api (namespace OHOS) и C-заголовок NDK;
# берём тот, где объявлена OH_QoS_SetThreadQoS, и библиотеку, которая её экспортирует.
QOS_H=$(grep -rl "OH_QoS_SetThreadQoS" "$ROOT/foundation/resourceschedule/qos_manager" --include=qos.h 2>/dev/null | head -1)
[ -n "$QOS_H" ] || { echo "не найден qos.h с OH_QoS_SetThreadQoS в qos_manager"; exit 1; }
QOS_INC=$(dirname "$QOS_H")
LIBQOS=""
for f in $(find "$OUTDIR" -name "libqos*.so" -not -path "*unstripped*" 2>/dev/null); do
  if "$LLVM/llvm-nm" -D --defined-only "$f" 2>/dev/null | grep -q " OH_QoS_SetThreadQoS$"; then
    LIBQOS=$f; break
  fi
done
[ -n "$LIBQOS" ] || { echo "не найдена библиотека с OH_QoS_SetThreadQoS (libqos*.so) — соберите NDK-библиотеку qos_manager"; exit 1; }

mkdir -p "$DST/pkgconfig"

ver() {  # версия из исходников, если её не удаётся определить — заглушка
  grep -m1 -oE "version *: *'[0-9.]+'" "$1" 2>/dev/null | grep -oE "[0-9.]+" || echo "$2"
}
DRM_VER=$(ver "$ROOT/third_party/libdrm/meson.build" 2.4.120)

cat > "$DST/pkgconfig/libdrm.pc" <<EOF
Name: libdrm
Description: libdrm (OpenHarmony build)
Version: $DRM_VER
Libs: $(link_flags "$LIBDRM")
Cflags: -I$ROOT/third_party/libdrm -I$ROOT/third_party/libdrm/include/drm
EOF

cat > "$DST/pkgconfig/zlib.pc" <<EOF
Name: zlib
Description: zlib (OpenHarmony build)
Version: 1.2.13
Libs: $(link_flags "$LIBZ")
Cflags: -I$ROOT/third_party/zlib
EOF

cat > "$DST/pkgconfig/libhitrace.pc" <<EOF
Name: libhitrace
Description: hitrace (OpenHarmony build)
Version: 1.0
Libs: $(link_flags "$LIBHITRACE")
Cflags: -I$HITRACE_INC -I$SYSPARAM_INC
EOF

cat > "$DST/pkgconfig/libbegetutil.pc" <<EOF
Name: libbegetutil
Description: init begetutil (OpenHarmony build)
Version: 1.0
Libs: $(link_flags "$LIBBEGET")
Cflags: -I$ROOT/base/startup/init/interfaces/innerkits/include -I$ROOT/base/startup/init/interfaces/innerkits/include/syspara -I$SYSPARAM_INC
EOF

cat > "$DST/pkgconfig/libqos.pc" <<EOF
Name: libqos
Description: qos_manager NDK (OpenHarmony build)
Version: 1.0
Libs: $(link_flags "$LIBQOS")
Cflags: -I$QOS_INC
EOF

cat > "$DST/pkgconfig/libhilog.pc" <<EOF
Name: libhilog
Description: hilog (OpenHarmony build)
Version: 1.0
Libs: $(link_flags "$LIBHILOG")
Cflags: -I$HILOG_INC
EOF

COMMON="'--target=x86_64-linux-ohos', '--sysroot=$SYSROOT', '-fPIC', '-O2', '-D__MUSL__', '-fstack-protector-strong', '-I$HITRACE_INC', '-I$HILOG_INC', '-I$SYSPARAM_INC', '-I$QOS_INC'"
LINK="'--target=x86_64-linux-ohos', '--sysroot=$SYSROOT', '-fuse-ld=lld', '-Wl,--as-needed', '-L$(dirname "$LIBDRM")', '-L$(dirname "$LIBZ")', '-L$(dirname "$LIBHITRACE")', '-L$(dirname "$LIBHILOG")', '-L$(dirname "$LIBBEGET")', '-l:$(basename "$LIBHITRACE")', '-l:$(basename "$LIBHILOG")', '-L$(dirname "$LIBQOS")', '-l:$(basename "$LIBBEGET")', '-l:$(basename "$LIBQOS")'"

cat > "$DST/cross_file" <<EOF
[binaries]
c = '$LLVM/clang'
cpp = '$LLVM/clang++'
ar = '$LLVM/llvm-ar'
strip = '$LLVM/llvm-strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = [$COMMON]
cpp_args = [$COMMON]
c_link_args = [$LINK]
cpp_link_args = [$LINK]

[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$DST/pkgconfig'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

echo "готово:"
echo "  кросс-файл: $DST/cross_file"
echo "  libdrm:     $LIBDRM (версия $DRM_VER)"
echo "  zlib:       $LIBZ"
echo "  hitrace:    $LIBHITRACE"
echo "  hilog:      $LIBHILOG"
echo "  begetutil:  $LIBBEGET"
echo "  sys_param:  $SYSPARAM_INC"
echo "  qos:        $LIBQOS ($QOS_INC)"
