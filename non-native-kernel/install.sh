#!/bin/bash




SYS=${SYS:-/system}

PWD_DIR=$(pwd)
PARENT_DIR=$(cd ../.. && pwd)
PROJECT_NAME="oneir"
OUT_DIR="${PARENT_DIR}/out/${PROJECT_NAME}"
INSTALL_DIR="/"


# ANSI-коды для оформления вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Сброс цвета (No Color)


out_samgr="systemabilitymgr/samgr/"
out_safwk="systemabilitymgr/safwk/"
out_hilog="hiviewdfx/hilog/"
out_atm="security/access_token/"

atm_deps=("accesstoken_cjson_utils" "accesstoken_manager_service" "accesstoken_json_parse" "accesstoken_common_cxx" "accesstoken_communication_adapter_cxx" "libaccesstoken_sdk" "libtokenid_sdk" "libtoken_callback_sdk" "libtokensetproc_shared" "libpermsetproc_shared" "libprivacy_sdk" "privacy_communication_adapter_cxx" )
hilog_deps=("hilogd" "hilog" "libhilog" "hilog_rust" "libsandboxlog")
safwk_deps=("sa_main" "system_ability_fwk" "utils" "libhilog" "libbegetutil" "samgr_common" "libsec_shared" )
samgr_deps=("samgr" "samgr_proxy" "samgr_common" "samgr_rust")
faultloggerd_deps=("faultloggerd" "processdump" "dumpcatcher" "crashvalidator" "dfx_signalhandler" "libfaultloggerd" "libdfx_dumpcatcher" "libunwinder" "libbacktrace_local" "libstack_printer" "libjson_stack_formatter" "libasync_stack" "libdfx_procinfo" "crash_exception" "kernel_snapshot" "panic_handler" "stacktrace_rust" "rustc_demangle" )
hiview_deps=("hiview" "hiviewbase" "sys_event_service_adapter" "libfaultlogger" "eventloggerso" "libcrashvalidator" "crashvalidator" "libtrace_manager" "libucollection_client" "libucollection_utility" "xperfservice_client" "xperfservice_server" "libxpower_event" "adft" "bdfr" "bdfr_base" "analysis_faultlog" "usage_report" )
token_init_deps=("token_init")
param_service_deps=("oneir_param_service" "param" "libbegetutil" "libbeget_proxy" "libsystemparam")

#
render_service_deps=("render_service" "librender_service" "librender_service_base" "librender_service_client" "libcomposer" "libvsync" "libhyper_graphic_manager" "2d_graphics" "rosen_text" "EGL" "GLESv3" "color_manager" "libnative_color_space_manager" "color_space_object_convertor" "create_pixelmap_surface" "socketpair" "libframe_analyzer" "window_animation" )
render_service2_deps=("libdisplay_buffer_hdi_impl_v1_4" "libdisplay_buffer_proxy_1.0" "libdisplay_buffer_proxy_1.1" "libdisplay_buffer_proxy_1.3" "libdisplay_buffer_proxy_1.4" "libdisplay_buffer_proxy_1.2" "libdisplay_commontype_proxy_1.0" "libdisplay_commontype_proxy_2.4" "libdisplay_commontype_proxy_1.1" "libdisplay_commontype_proxy_2.0" "libdisplay_commontype_proxy_2.1" "libdisplay_commontype_proxy_2.2" "libdisplay_commontype_proxy_2.3" "libhdifd_parcelable" )


skia_deps=("skia_canvaskit")
hdf_deps=("hdf_devmgr" "hdf_devhost" "libhdf_host" "libhdf_utils" "libhdf_ipc_adapter" "libhdi" "libhdi_base" "libpub_utils" )
display_buffer_deps=("oneir_display_buffer_vdi_impl" "oneir_display_buffer_vendor")
display_composer_deps=("oneir_display_composer_vdi_impl" "oneir_display_composer_vendor" "oneir_display_gfx")



echo "$PARENT_DIR"
echo $SYS
echo "$OUT_DIR"






# ==============================================================================
# Функция: process_and_install_deps
# Назначение: Поиск, парсинг .json файлов зависимостей и копирование .so файлов
#              по всем путям, указанным в массиве "dest"
# ==============================================================================
process_and_install_deps() {
    # Сохраняем переданные аргументы в локальный массив
    local deps=("$@")

    for item in "${deps[@]}"; do
        # Ищем файл в каталоге OUT_DIR по имени из массива
        local found_file
        found_file=$(find "$OUT_DIR" -type f -name "${item}_module_info.json" -print -quit)

        if [[ -n "$found_file" && -f "$found_file" ]]; then
            # Считываем путь к исходному файлу
            local source_so
            source_so=$(jq -r '.source' "$found_file")
            local src_path="${OUT_DIR}/${source_so}"

            # Считываем ВСЕ пути из массива "dest" в массив Bash
            local dest_paths=()
            readarray -t dest_paths < <(jq -r '.dest[]' "$found_file")

            # Проверяем, существует ли исходный .so файл
            if [[ ! -f "$src_path" ]]; then
                echo -e "${RED}Ошибка: исходный файл не найден: ${src_path}${NC}"
                continue
            fi

            # Внутренний цикл: копируем исходный файл по каждому пути из массива dest
            for dest_so in "${dest_paths[@]}"; do
                # Игнорируем пустые строки, если jq ничего не вернул
                [[ -z "$dest_so" ]] && continue

                local dest_path="${INSTALL_DIR}/${dest_so}"

                # Создаем целевую директорию (например, system/lib64 или updater/lib64)
                mkdir -p "$(dirname "$dest_path")"

                # Копируем файл с принудительной перезаписью
                cp -f "$src_path" "$dest_path" 




                # Проверяем код возврата команды cp ($?)
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}Установка ${dest_so} успешно${NC}"
                else
                    echo -e "${RED}Ошибка: не удалось скопировать в ${dest_so}${NC}"
                fi
            done
        else
            echo "Предупреждение: файл '${item}_module_info.json' не найден в $OUT_DIR"
        fi
    done
}




# Функция для минимальной установки
install_minimal() {
   echo "Запуск минимальной установки..."
   echo "	Установка samgr"
   process_and_install_deps "${samgr_deps[@]}"

   # Создание сервиса для samgr
   if ! cp "${PWD_DIR}/services/ohos-samgr.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-samgr.service${NC}"
   fi


   echo "	Установка safwk"
   process_and_install_deps "${safwk_deps[@]}"
   echo "	Установка HiLog"
   process_and_install_deps "${hilog_deps[@]}"
   
   # Создание сервиса для hilog
   if ! cp "${PWD_DIR}/services/ohos-hilogd.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-hilogd.service${NC}"
   fi


   echo "	Установка ATM"
   process_and_install_deps "${atm_deps[@]}"

   # Создание сервиса для ATM
   if ! cp "${PWD_DIR}/services/ohos-atm.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-atm.service${NC}"
   fi

   if ! cp "${PWD_DIR}/../profile/accesstoken_service.json" "${SYS}/profile/accesstoken_service.json"; then
    echo -e "${RED}Ошибка: не удалось скопировать accesstoken_service.json${NC}"
   fi

   echo "       Установка faultloggerd_deps"
   process_and_install_deps "${faultloggerd_deps[@]}"
   mkdir -p /log/crash
   # Создание сервиса для ohos-faultloggerd
   if ! cp "${PWD_DIR}/services/ohos-faultloggerd.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-faultloggerd.service${NC}"
   fi


   echo "       Установка hiview_deps"
   process_and_install_deps "${hiview_deps[@]}"
   # Создание сервиса для  ohos-hiview
   if ! cp "${PWD_DIR}/services/ohos-hiview.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-hiview.service${NC}"
   fi
   echo "       Установка token_init"
   process_and_install_deps "${token_init_deps[@]}"

   echo "       Установка param_service"
   process_and_install_deps "${param_service_deps[@]}"


   if ! cp "${PWD_DIR}/services/ohos-param.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-param.service${NC}"
   fi


   systemctl daemon-reload
}

install_graphics(){
   echo "Запуск установки графики"
   echo "       Установка render_service"
   process_and_install_deps "${render_service_deps[@]}"
   process_and_install_deps "${render_service2_deps[@]}"

   echo "       Установка Skia"
   process_and_install_deps "${skia_deps[@]}"


   echo "       Установка hdf"
   process_and_install_deps "${hdf_deps[@]}"


   echo "       Установка hdf_devhost.cfg"
   mkdir -p /vendor/etc/init/
   if ! cp "${PARENT_DIR}/out/oneir/gen/oneir/hdf_config/uhdf/hdf_devhost.cfg" "/vendor/etc/init/hdf_devhost.cfg"; then
    echo -e "${RED}Ошибка: не удалось скопировать hdf_devhost.cfg${NC}"
   fi

   if ! cp "${PARENT_DIR}/out/oneir/gen/oneir/hdf_config/uhdf/hdf_default.hcb" "/vendor/etc/hdfconfig/hdf_default.hcb"; then
    echo -e "${RED}Ошибка: не удалось скопировать hdf_default.hcb${NC}"
   fi


   if ! cp "${PWD_DIR}/services/ohos-hdf-devmgr.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-hdf-devmgr.service${NC}"
   fi


   if ! cp "${PWD_DIR}/services/ohos-allocator-host.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-allocator-host.service${NC}"
   fi

   echo "       Установка display_buffer"
   process_and_install_deps "${display_buffer_deps[@]}"

   echo "       Установка display_composer_deps"
   process_and_install_deps "${display_composer_deps[@]}"
   if ! cp "${PWD_DIR}/services/ohos-composer-host.service" "/etc/systemd/system/"; then
    echo -e "${RED}Ошибка: не удалось скопировать ohos-composer-host.service${NC}"
   fi

   systemctl daemon-reload
}

# Проверяем переданный аргумент ($1)
case "$1" in
    minimal)
        install_minimal
        ;;
    graphics)
        install_graphics
        ;;
    full)
        install_full
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo "Ошибка: неизвестный аргумент '$1'"
        show_help
        exit 1
        ;;
esac
