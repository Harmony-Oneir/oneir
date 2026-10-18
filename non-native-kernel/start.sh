#!/bin/bash
#
# Запуск, остановка и состояние служб OpenHarmony на стенде через systemd.
#
#   sudo ./start            запустить все службы по порядку
#   sudo ./start start      то же самое
#   sudo ./start stop       остановить все службы в обратном порядке
#   sudo ./start restart    остановить и запустить заново
#        ./start status     показать состояние служб
#
# Службы описаны в systemd/ohos-*.service и должны быть установлены
# в /etc/systemd/system/ (sudo cp systemd/ohos-*.service /etc/systemd/system/).

# ---------------------------------------------------------------------------
# Порядок запуска. Останавливаются службы в обратном порядке.
#
#   hilogd        журнал — первым, чтобы не потерять записи остальных
#   faultloggerd  приём отчётов о сбоях — до всех, кто может упасть
#   samgr         реестр системных сервисов — до любого SA
#   atm           AccessTokenManager (SA 3503)
#   hiview        системные события и журналы сбоев (SA 1201)
# ---------------------------------------------------------------------------
SERVICES="hilogd faultloggerd samgr atm hiview"

# Выдача токенов службам: должна пройти до samgr, иначе samgr не примет
# регистрацию сервисов (токен вызывающего будет 0).
TOKEN_INIT=/system/bin/token_init

# Сколько секунд ждать, пока служба станет active.
WAIT_SECONDS=5


# ---------------------------------------------------------------------------
# Вспомогательное
# ---------------------------------------------------------------------------

unit_name() {
    echo "ohos-$1.service"
}

need_root() {
    if [ "$(id -u)" != 0 ]; then
        echo "Нужны права root: sudo $0 $*"
        exit 1
    fi
}

reverse() {
    echo "$@" | tr ' ' '\n' | tac | tr '\n' ' '
}

wait_until_active() {
    local unit=$1
    local i
    for i in $(seq "$WAIT_SECONDS"); do
        systemctl is-active --quiet "$unit" && return 0
        sleep 1
    done
    return 1
}

issue_tokens() {
    if [ -x "$TOKEN_INIT" ]; then
        echo "  токены        выдаю ($TOKEN_INIT)"
        "$TOKEN_INIT" > /dev/null || echo "  токены        [ошибка] token_init завершился с ошибкой"
    else
        echo "  токены        [пропуск] нет $TOKEN_INIT — samgr может отклонить регистрацию сервисов"
    fi
}


# ---------------------------------------------------------------------------
# Команды
# ---------------------------------------------------------------------------

start_all() {
    need_root start
    echo "Запуск служб OpenHarmony"

    for service in $SERVICES; do
        unit=$(unit_name "$service")

        # Токены нужны до samgr
        if [ "$service" = samgr ]; then
            issue_tokens
        fi

        if systemctl is-active --quiet "$unit"; then
            printf '  %-13s уже работает\n' "$service"
            continue
        fi

        systemctl start "$unit"

        if wait_until_active "$unit"; then
            printf '  %-13s запущен\n' "$service"
        else
            printf '  %-13s [ошибка] не запустился — journalctl -u %s -n 30\n' "$service" "$unit"
        fi
    done
}

stop_all() {
    need_root stop
    echo "Остановка служб OpenHarmony"

    for service in $(reverse $SERVICES); do
        unit=$(unit_name "$service")

        if ! systemctl is-active --quiet "$unit"; then
            printf '  %-13s не запущен\n' "$service"
            continue
        fi

        systemctl stop "$unit"
        printf '  %-13s остановлен\n' "$service"
    done
}

show_status() {
    echo "Состояние служб OpenHarmony"
    # Заголовок — готовой строкой: printf считает байты, и кириллица сбила бы колонки
    echo "  служба        состояние    pid      перезапусков"

    for service in $SERVICES; do
        unit=$(unit_name "$service")
        state=$(systemctl is-active "$unit" 2>/dev/null)
        pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null)
        restarts=$(systemctl show -p NRestarts --value "$unit" 2>/dev/null)

        [ "$pid" = 0 ] && pid="-"
        printf '  %-13s %-12s %-8s %s\n' "$service" "${state:-нет службы}" "${pid:--}" "${restarts:--}"
    done
}


# ---------------------------------------------------------------------------
# Разбор команды
# ---------------------------------------------------------------------------

case "${1:-start}" in
    start)    start_all ;;
    stop)     stop_all ;;
    restart)  stop_all; start_all ;;
    status)   show_status ;;
    *)
        echo "Неизвестная команда: $1"
        echo "Использование: $0 [start|stop|restart|status]"
        exit 1
        ;;
esac
