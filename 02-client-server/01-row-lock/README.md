# Обработка чисел: PostgreSQL и общая блокировка

[Отчёт](report.pdf) · [Код](number_service/server.py) · [UML](number_service/architecture.puml)

```sh
cd number_service
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
python3 start.py --pg-bin /path/to/postgresql/bin
```

В другом терминале: `python3 request.py 5`.
Проверка: `python3 verify.py --pg-bin /path/to/postgresql/bin`.
Нужны Python 3.12+ и PostgreSQL. При запуске логи приложения идут в stdout.
`Ctrl-C` останавливает процессы, история остаётся в `.runtime`.
