#!/bin/bash




SYS=${SYS:-/system}
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
safwk_deps=("sa_main" "system_ability_fwk" "utils" "libhilog" "libbegetutil" "samgr_common" "libsec_shared" "" )
samgr_deps=("samgr" "samgr_proxy" "samgr_common" "samgr_rust")



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
                cp -f "$src_path" "$dest_path" 2>/dev/null

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
   echo "	Установка safwk"
   process_and_install_deps "${safwk_deps[@]}"
   echo "	Установка HiLog"
   process_and_install_deps "${hilog_deps[@]}"
   echo "	Установка ATM"
   process_and_install_deps "${atm_deps[@]}"
}

# Проверяем переданный аргумент ($1)
case "$1" in
    minimal)
        install_minimal
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
