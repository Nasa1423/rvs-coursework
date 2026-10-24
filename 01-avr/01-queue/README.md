# Периодические сообщения ATmega8

Исходник: [serial_scheduler.asm](serial_scheduler/serial_scheduler.asm).
Описание: [report.pdf](report.pdf).

```sh
cd serial_scheduler
python3 build_and_check.py
python3 checks/timing_audit.py
```

Нужны Python 3, git, make и C-компилятор. Сборщик и симулятор скачиваются
из зафиксированных ревизий. На плате не проверялось.
Команды USART реализованы, но средняя и высокая сложности не подтверждены:
точность физического вывода в 4 такта и требуемый минимум не обеспечены.
