#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>

#define BLOCK_SIZE 4096
#define MAX_BLOCKS 10000
#define DELAY_NS 500000

void *allocated_blocks[MAX_BLOCKS];
int block_count = 0;
volatile sig_atomic_t running = 1;

void signal_handler(int signum) {
    printf("\n[Сигнал %d] Получен сигнал завершения. Освобождаю память...\n", signum);
    running = 0;
}

void free_all_memory() {
    int freed_count = 0;
    for (int i = 0; i < block_count; i++) {
        if (allocated_blocks[i] != NULL) {
            free(allocated_blocks[i]);
            allocated_blocks[i] = NULL;
            freed_count++;
        }
    }
    printf("[Очистка] Освобождено %d блоков памяти\n", freed_count);
}

void initialize_block(void *block, size_t size) {
    memset(block, 0xAB, size);
}

void mode_balanced() {
    printf("[Режим 1] Сбалансированное выделение/освобождение памяти\n");
    printf("Нажмите Ctrl+C для завершения\n\n");
    
    void *prev_block = NULL;
    unsigned long iteration = 0;
    struct timespec delay = {0, DELAY_NS};
    
    while (running) {
        void *new_block = malloc(BLOCK_SIZE);
        if (new_block == NULL) {
            fprintf(stderr, "[Ошибка] Не удалось выделить память на итерации %lu\n", iteration);
            break;
        }
        
        initialize_block(new_block, BLOCK_SIZE);
        
        if (prev_block != NULL) {
            free(prev_block);
        }
        
        prev_block = new_block;
        iteration++;
        
        if (iteration % 1000 == 0) {
            printf("[Итерация %lu] Выделен блок %p, размер: %d байт\n", 
                   iteration, new_block, BLOCK_SIZE);
        }
        
        nanosleep(&delay, NULL);
    }
    
    if (prev_block != NULL) {
        free(prev_block);
        printf("[Завершение] Освобождён последний блок\n");
    }
    
    printf("[Режим 1] Завершено после %lu итераций\n", iteration);
}

void mode_leak() {
    printf("[Режим 2] Контролируемая утечка памяти\n");
    printf("Освобождается каждый 5-й блок\n");
    printf("Нажмите Ctrl+C для завершения\n\n");
    
    unsigned long iteration = 0;
    struct timespec delay = {0, DELAY_NS};
    
    while (running && block_count < MAX_BLOCKS) {
        void *new_block = malloc(BLOCK_SIZE);
        if (new_block == NULL) {
            fprintf(stderr, "[Ошибка] Не удалось выделить память на итерации %lu\n", iteration);
            break;
        }
        
        initialize_block(new_block, BLOCK_SIZE);
        
        allocated_blocks[block_count] = new_block;
        block_count++;
        iteration++;
        
        if (iteration % 5 == 0 && block_count >= 5) {
            int index_to_free = block_count - 5;
            if (allocated_blocks[index_to_free] != NULL) {
                free(allocated_blocks[index_to_free]);
                allocated_blocks[index_to_free] = NULL;
            }
        }
        
        if (iteration % 100 == 0) {
            int active_blocks = 0;
            for (int i = 0; i < block_count; i++) {
                if (allocated_blocks[i] != NULL) active_blocks++;
            }
            printf("[Итерация %lu] Активных блоков: %d, Утечка: ~%d КБ\n", 
                   iteration, active_blocks, (active_blocks * BLOCK_SIZE) / 1024);
        }
        
        nanosleep(&delay, NULL);
    }
    
    if (block_count >= MAX_BLOCKS) {
        printf("[Предупреждение] Достигнут лимит блоков (%d)\n", MAX_BLOCKS);
    }
    
    printf("[Режим 2] Завершено после %lu итераций\n", iteration);
    free_all_memory();
}

void print_usage(const char *program_name) {
    printf("Использование: %s <режим>\n", program_name);
    printf("  режим 1 или R1 - Сбалансированное выделение/освобождение\n");
    printf("  режим 2 или R2 - Контролируемая утечка памяти\n");
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }
    
    memset(allocated_blocks, 0, sizeof(allocated_blocks));
    
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    signal(SIGUSR1, signal_handler);
    
    printf("=== Программа исследования памяти ===\n");
    printf("PID процесса: %d\n", getpid());
    printf("Размер блока: %d байт\n", BLOCK_SIZE);
    printf("Задержка: %d нс\n\n", DELAY_NS);
    
    int mode = 0;
    if (strcmp(argv[1], "1") == 0 || strcmp(argv[1], "R1") == 0 || strcmp(argv[1], "r1") == 0) {
        mode = 1;
    } else if (strcmp(argv[1], "2") == 0 || strcmp(argv[1], "R2") == 0 || strcmp(argv[1], "r2") == 0) {
        mode = 2;
    } else {
        fprintf(stderr, "Ошибка: неизвестный режим '%s'\n\n", argv[1]);
        print_usage(argv[0]);
        return 1;
    }
    
    if (mode == 1) {
        mode_balanced();
    } else {
        mode_leak();
    }
    
    printf("\n=== Программа завершена корректно ===\n");
    return 0;
}
