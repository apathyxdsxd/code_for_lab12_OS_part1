#!/bin/bash

# Скрипт для сбора информации о виртуальной памяти процесса
# Использование: ./collect_memory_map.sh <PID> [MODE]
# где MODE - опциональный параметр (R1 или R2)

# Директория для хранения карт памяти
MAP_DIR="/var/log/my_mem_maps"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция вывода справки
print_usage() {
    echo "Использование: $0 <PID> [MODE]"
    echo "  PID  - идентификатор процесса"
    echo "  MODE - режим работы (R1 или R2), опционально"
    echo ""
    echo "Примеры:"
    echo "  $0 1234"
    echo "  $0 1234 R1"
    echo "  $0 1234 R2"
}

# Функция проверки существования процесса
check_process() {
    local pid=$1
    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "${RED}[Ошибка]${NC} Процесс с PID $pid не существует"
        return 1
    fi
    return 0
}

# Функция создания директории для карт памяти
create_map_directory() {
    if [ ! -d "$MAP_DIR" ]; then
        sudo mkdir -p "$MAP_DIR"
        sudo chmod 755 "$MAP_DIR"
        echo -e "${GREEN}[Создано]${NC} Директория $MAP_DIR"
    fi
}

# Проверка аргументов
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    print_usage
    exit 1
fi

PID=$1
MODE=""

# Проверка, что PID - число
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}[Ошибка]${NC} PID должен быть числом"
    print_usage
    exit 1
fi

# Обработка опционального параметра режима
if [ $# -eq 2 ]; then
    MODE=$2
    # Проверка корректности режима
    if [[ ! "$MODE" =~ ^(R1|R2|r1|r2|1|2)$ ]]; then
        echo -e "${YELLOW}[Предупреждение]${NC} Неизвестный режим '$MODE', будет проигнорирован"
        MODE=""
    else
        # Нормализация режима
        case "$MODE" in
            1|r1|R1) MODE="R1" ;;
            2|r2|R2) MODE="R2" ;;
        esac
    fi
fi

# Проверка существования процесса
if ! check_process "$PID"; then
    exit 1
fi

# Создание директории
create_map_directory

# Формирование имени файла
DATETIME=$(date +"%Y-%m-%d_%H:%M:%S")
if [ -n "$MODE" ]; then
    FILENAME="map_${PID}_${DATETIME}_${MODE}"
else
    FILENAME="map_${PID}_${DATETIME}"
fi

FILEPATH="${MAP_DIR}/${FILENAME}"

echo -e "${GREEN}[Информация]${NC} Сбор карты памяти для процесса PID=$PID"
echo "Дата и время: $DATETIME"
[ -n "$MODE" ] && echo "Режим: $MODE"

# Сбор информации о процессе
{
    echo "=========================================="
    echo "КАРТА ВИРТУАЛЬНОЙ ПАМЯТИ ПРОЦЕССА"
    echo "=========================================="
    echo "PID: $PID"
    echo "Дата создания: $DATETIME"
    [ -n "$MODE" ] && echo "Режим работы: $MODE"
    echo ""
    
    # Имя процесса
    if [ -f "/proc/$PID/comm" ]; then
        echo "Имя процесса: $(cat /proc/$PID/comm)"
    fi
    
    # Командная строка запуска
    if [ -f "/proc/$PID/cmdline" ]; then
        echo "Командная строка: $(tr '\0' ' ' < /proc/$PID/cmdline)"
    fi
    echo ""
    
    echo "=========================================="
    echo "СТАТУС ПАМЯТИ (/proc/$PID/status)"
    echo "=========================================="
    if [ -f "/proc/$PID/status" ]; then
        grep -E "^(VmPeak|VmSize|VmRSS|VmData|VmStk|VmExe|VmLib|VmHWM)" "/proc/$PID/status"
    fi
    echo ""
    
    echo "=========================================="
    echo "СТАТИСТИКА ПАМЯТИ (/proc/$PID/statm)"
    echo "=========================================="
    if [ -f "/proc/$PID/statm" ]; then
        read -r size resident shared text lib data dirty < "/proc/$PID/statm"
        PAGE_SIZE=$(getconf PAGE_SIZE)
        echo "Общий размер (pages): $size ($(( size * PAGE_SIZE / 1024 )) KB)"
        echo "Резидентная память (pages): $resident ($(( resident * PAGE_SIZE / 1024 )) KB)"
        echo "Разделяемая память (pages): $shared ($(( shared * PAGE_SIZE / 1024 )) KB)"
        echo "Код (text, pages): $text ($(( text * PAGE_SIZE / 1024 )) KB)"
        echo "Данные + стек (pages): $data ($(( data * PAGE_SIZE / 1024 )) KB)"
    fi
    echo ""
    
    echo "=========================================="
    echo "КАРТА ПАМЯТИ (pmap -x)"
    echo "=========================================="
    pmap -x "$PID" 2>/dev/null || echo "Не удалось получить карту памяти через pmap"
    echo ""
    
    echo "=========================================="
    echo "ПОДРОБНАЯ КАРТА (/proc/$PID/maps)"
    echo "=========================================="
    if [ -f "/proc/$PID/maps" ]; then
        cat "/proc/$PID/maps"
    fi
    echo ""
    
    echo "=========================================="
    echo "СВОДКА ПО СЕГМЕНТАМ"
    echo "=========================================="
    if [ -f "/proc/$PID/maps" ]; then
        echo "Heap (куча):"
        grep -E "\[heap\]" "/proc/$PID/maps" || echo "  Не найдено"
        echo ""
        echo "Stack (стек):"
        grep -E "\[stack\]" "/proc/$PID/maps" || echo "  Не найдено"
        echo ""
        echo "Анонимная память:"
        grep -c "anon" "/proc/$PID/maps" 2>/dev/null | xargs -I {} echo "  Количество регионов: {}"
    fi
    
} | sudo tee "$FILEPATH" > /dev/null

# Установка прав доступа
sudo chmod 644 "$FILEPATH"

echo -e "${GREEN}[Успех]${NC} Карта памяти сохранена в: $FILEPATH"

# Краткая информация о куче
if [ -f "/proc/$PID/maps" ]; then
    HEAP_INFO=$(grep "\[heap\]" "/proc/$PID/maps" 2>/dev/null)
    if [ -n "$HEAP_INFO" ]; then
        echo -e "${YELLOW}[Куча]${NC} $HEAP_INFO"
    fi
fi

exit 0












#!/bin/bash

# Скрипт установки и управления службой сбора карт памяти
# Использование: ./setup_service.sh <команда> [аргументы]

SCRIPT_DIR="/home/claude/memory_lab"
SERVICE_FILE="memory-map-collector.service"
TIMER_FILE="memory-map-collector.timer"
CONFIG_FILE="/etc/memory-collector.conf"
SYSTEMD_DIR="/etc/systemd/system"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    echo "Использование: $0 <команда> [аргументы]"
    echo ""
    echo "Команды:"
    echo "  install <PID> <MODE>  - Установить и запустить службу для указанного PID и режима"
    echo "  uninstall             - Удалить службу и таймер"
    echo "  start                 - Запустить таймер"
    echo "  stop                  - Остановить таймер"
    echo "  status                - Показать статус службы и таймера"
    echo "  logs                  - Показать логи службы"
    echo "  maps                  - Показать список собранных карт памяти"
    echo ""
    echo "Примеры:"
    echo "  $0 install 1234 R1    - Установить для процесса 1234 в режиме R1"
    echo "  $0 status             - Проверить статус"
    echo "  $0 logs               - Посмотреть логи"
}

install_service() {
    local pid=$1
    local mode=$2
    
    if [ -z "$pid" ] || [ -z "$mode" ]; then
        echo -e "${RED}[Ошибка]${NC} Укажите PID и MODE"
        print_usage
        exit 1
    fi
    
    # Проверка существования процесса
    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "${RED}[Ошибка]${NC} Процесс с PID $pid не существует"
        exit 1
    fi
    
    echo -e "${BLUE}[Установка]${NC} Настройка службы для PID=$pid, MODE=$mode"
    
    # Создание конфигурационного файла
    echo -e "${GREEN}[1/5]${NC} Создание конфигурационного файла..."
    cat > /tmp/memory-collector.conf << EOF
# Конфигурационный файл для Memory Map Collector
# Автоматически сгенерирован $(date)

TARGET_PID=$pid
MODE=$mode
EOF
    sudo mv /tmp/memory-collector.conf "$CONFIG_FILE"
    sudo chmod 644 "$CONFIG_FILE"
    
    # Копирование service файла
    echo -e "${GREEN}[2/5]${NC} Установка service файла..."
    sudo cp "$SCRIPT_DIR/$SERVICE_FILE" "$SYSTEMD_DIR/"
    
    # Копирование timer файла
    echo -e "${GREEN}[3/5]${NC} Установка timer файла..."
    sudo cp "$SCRIPT_DIR/$TIMER_FILE" "$SYSTEMD_DIR/"
    
    # Создание директории для карт памяти
    echo -e "${GREEN}[4/5]${NC} Создание директории для карт памяти..."
    sudo mkdir -p /var/log/my_mem_maps
    sudo chmod 755 /var/log/my_mem_maps
    
    # Перезагрузка systemd и запуск таймера
    echo -e "${GREEN}[5/5]${NC} Активация таймера..."
    sudo systemctl daemon-reload
    sudo systemctl enable memory-map-collector.timer
    sudo systemctl start memory-map-collector.timer
    
    echo ""
    echo -e "${GREEN}[Успех]${NC} Служба установлена и таймер запущен!"
    echo ""
    show_status
}

uninstall_service() {
    echo -e "${BLUE}[Удаление]${NC} Остановка и удаление службы..."
    
    sudo systemctl stop memory-map-collector.timer 2>/dev/null
    sudo systemctl disable memory-map-collector.timer 2>/dev/null
    sudo rm -f "$SYSTEMD_DIR/$SERVICE_FILE"
    sudo rm -f "$SYSTEMD_DIR/$TIMER_FILE"
    sudo rm -f "$CONFIG_FILE"
    sudo systemctl daemon-reload
    
    echo -e "${GREEN}[Успех]${NC} Служба удалена"
    echo -e "${YELLOW}[Заметка]${NC} Карты памяти в /var/log/my_mem_maps сохранены"
}

show_status() {
    echo -e "${BLUE}=== Статус таймера ===${NC}"
    sudo systemctl status memory-map-collector.timer --no-pager 2>/dev/null || echo "Таймер не установлен"
    echo ""
    echo -e "${BLUE}=== Статус службы ===${NC}"
    sudo systemctl status memory-map-collector.service --no-pager 2>/dev/null || echo "Служба не установлена"
    echo ""
    echo -e "${BLUE}=== Конфигурация ===${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo "Конфигурационный файл не найден"
    fi
    echo ""
    echo -e "${BLUE}=== Список таймеров ===${NC}"
    sudo systemctl list-timers --all | grep -E "(memory-map|NEXT|PASSED)" || echo "Нет активных таймеров"
}

show_logs() {
    echo -e "${BLUE}=== Логи службы (последние 50 записей) ===${NC}"
    sudo journalctl -u memory-map-collector.service -n 50 --no-pager
}

show_maps() {
    echo -e "${BLUE}=== Собранные карты памяти ===${NC}"
    if [ -d "/var/log/my_mem_maps" ]; then
        ls -la /var/log/my_mem_maps/
        echo ""
        echo "Всего файлов: $(ls /var/log/my_mem_maps/ 2>/dev/null | wc -l)"
    else
        echo "Директория /var/log/my_mem_maps не существует"
    fi
}

start_timer() {
    sudo systemctl start memory-map-collector.timer
    echo -e "${GREEN}[Успех]${NC} Таймер запущен"
}

stop_timer() {
    sudo systemctl stop memory-map-collector.timer
    echo -e "${GREEN}[Успех]${NC} Таймер остановлен"
}

# Главная логика
case "${1:-}" in
    install)
        install_service "$2" "$3"
        ;;
    uninstall)
        uninstall_service
        ;;
    start)
        start_timer
        ;;
    stop)
        stop_timer
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    maps)
        show_maps
        ;;
    *)
        print_usage
        exit 1
        ;;
esac








#memory-map-collector.timer
[Unit]
Description=Timer for Memory Map Collector (every 30 seconds)
Documentation=man:pmap(1)

[Timer]
# Запуск каждые 30 секунд
OnBootSec=10sec
OnUnitActiveSec=30sec
# Точность таймера
AccuracySec=1sec
# Сохранять время последнего запуска
Persistent=true

[Install]
WantedBy=timers.target






#memory-map-collector.service
[Unit]
Description=Memory Map Collector Service (with config)
Documentation=man:pmap(1)
After=network.target

[Service]
Type=oneshot
# Загружаем конфигурацию из файла
EnvironmentFile=/etc/memory-collector.conf
ExecStart=/home/claude/memory_lab/collect_memory_map.sh ${TARGET_PID} ${MODE}

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target

















#memory-collector.conf
TARGET_PID = 8428
MODE=R1
























































#collect_memory_map.sh
#!/bin/bash

# Скрипт для сбора информации о виртуальной памяти процесса
# Использование: ./collect_memory_map.sh <PID> [MODE]
# где MODE - опциональный параметр (R1 или R2)

# Директория для хранения карт памяти
MAP_DIR="/var/log/my_mem_maps"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция вывода справки
print_usage() {
    echo "Использование: $0 <PID> [MODE]"
    echo "  PID  - идентификатор процесса"
    echo "  MODE - режим работы (R1 или R2), опционально"
    echo ""
    echo "Примеры:"
    echo "  $0 1234"
    echo "  $0 1234 R1"
    echo "  $0 1234 R2"
}

# Функция проверки существования процесса
check_process() {
    local pid=$1
    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "${RED}[Ошибка]${NC} Процесс с PID $pid не существует"
        return 1
    fi
    return 0
}

# Функция создания директории для карт памяти
create_map_directory() {
    if [ ! -d "$MAP_DIR" ]; then
        sudo mkdir -p "$MAP_DIR"
        sudo chmod 755 "$MAP_DIR"
        echo -e "${GREEN}[Создано]${NC} Директория $MAP_DIR"
    fi
}

# Проверка аргументов
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    print_usage
    exit 1
fi

PID=$1
MODE=""

# Проверка, что PID - число
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}[Ошибка]${NC} PID должен быть числом"
    print_usage
    exit 1
fi

# Обработка опционального параметра режима
if [ $# -eq 2 ]; then
    MODE=$2
    # Проверка корректности режима
    if [[ ! "$MODE" =~ ^(R1|R2|r1|r2|1|2)$ ]]; then
        echo -e "${YELLOW}[Предупреждение]${NC} Неизвестный режим '$MODE', будет проигнорирован"
        MODE=""
    else
        # Нормализация режима
        case "$MODE" in
            1|r1|R1) MODE="R1" ;;
            2|r2|R2) MODE="R2" ;;
        esac
    fi
fi

# Проверка существования процесса
if ! check_process "$PID"; then
    exit 1
fi

# Создание директории
create_map_directory

# Формирование имени файла
DATETIME=$(date +"%Y-%m-%d_%H:%M:%S")
if [ -n "$MODE" ]; then
    FILENAME="map_${PID}_${DATETIME}_${MODE}"
else
    FILENAME="map_${PID}_${DATETIME}"
fi

FILEPATH="${MAP_DIR}/${FILENAME}"

echo -e "${GREEN}[Информация]${NC} Сбор карты памяти для процесса PID=$PID"
echo "Дата и время: $DATETIME"
[ -n "$MODE" ] && echo "Режим: $MODE"

# Сбор информации о процессе
{
    echo "=========================================="
    echo "КАРТА ВИРТУАЛЬНОЙ ПАМЯТИ ПРОЦЕССА"
    echo "=========================================="
    echo "PID: $PID"
    echo "Дата создания: $DATETIME"
    [ -n "$MODE" ] && echo "Режим работы: $MODE"
    echo ""
    
    # Имя процесса
    if [ -f "/proc/$PID/comm" ]; then
        echo "Имя процесса: $(cat /proc/$PID/comm)"
    fi
    
    # Командная строка запуска
    if [ -f "/proc/$PID/cmdline" ]; then
        echo "Командная строка: $(tr '\0' ' ' < /proc/$PID/cmdline)"
    fi
    echo ""
    
    echo "=========================================="
    echo "СТАТУС ПАМЯТИ (/proc/$PID/status)"
    echo "=========================================="
    if [ -f "/proc/$PID/status" ]; then
        grep -E "^(VmPeak|VmSize|VmRSS|VmData|VmStk|VmExe|VmLib|VmHWM)" "/proc/$PID/status"
    fi
    echo ""
    
    echo "=========================================="
    echo "СТАТИСТИКА ПАМЯТИ (/proc/$PID/statm)"
    echo "=========================================="
    if [ -f "/proc/$PID/statm" ]; then
        read -r size resident shared text lib data dirty < "/proc/$PID/statm"
        PAGE_SIZE=$(getconf PAGE_SIZE)
        echo "Общий размер (pages): $size ($(( size * PAGE_SIZE / 1024 )) KB)"
        echo "Резидентная память (pages): $resident ($(( resident * PAGE_SIZE / 1024 )) KB)"
        echo "Разделяемая память (pages): $shared ($(( shared * PAGE_SIZE / 1024 )) KB)"
        echo "Код (text, pages): $text ($(( text * PAGE_SIZE / 1024 )) KB)"
        echo "Данные + стек (pages): $data ($(( data * PAGE_SIZE / 1024 )) KB)"
    fi
    echo ""
    
    echo "=========================================="
    echo "КАРТА ПАМЯТИ (pmap -x)"
    echo "=========================================="
    pmap -x "$PID" 2>/dev/null || echo "Не удалось получить карту памяти через pmap"
    echo ""
    
    echo "=========================================="
    echo "ПОДРОБНАЯ КАРТА (/proc/$PID/maps)"
    echo "=========================================="
    if [ -f "/proc/$PID/maps" ]; then
        cat "/proc/$PID/maps"
    fi
    echo ""
    
    echo "=========================================="
    echo "СВОДКА ПО СЕГМЕНТАМ"
    echo "=========================================="
    if [ -f "/proc/$PID/maps" ]; then
        echo "Heap (куча):"
        grep -E "\[heap\]" "/proc/$PID/maps" || echo "  Не найдено"
        echo ""
        echo "Stack (стек):"
        grep -E "\[stack\]" "/proc/$PID/maps" || echo "  Не найдено"
        echo ""
        echo "Анонимная память:"
        grep -c "anon" "/proc/$PID/maps" 2>/dev/null | xargs -I {} echo "  Количество регионов: {}"
    fi
    
} | sudo tee "$FILEPATH" > /dev/null

# Установка прав доступа
sudo chmod 644 "$FILEPATH"

echo -e "${GREEN}[Успех]${NC} Карта памяти сохранена в: $FILEPATH"

# Краткая информация о куче
if [ -f "/proc/$PID/maps" ]; then
    HEAP_INFO=$(grep "\[heap\]" "/proc/$PID/maps" 2>/dev/null)
    if [ -n "$HEAP_INFO" ]; then
        echo -e "${YELLOW}[Куча]${NC} $HEAP_INFO"
    fi
fi

exit 0




















