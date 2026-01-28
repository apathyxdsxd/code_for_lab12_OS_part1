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
