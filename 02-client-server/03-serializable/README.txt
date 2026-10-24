Ачивка 2. Вариант 3. PostgreSQL, Python, логирование в stdout.
Журнал events, SERIALIZABLE и до 12 повторов при конфликте транзакций.

Запуск из этого каталога (Python 3.12+, PostgreSQL 17):
  python3 -m venv .venv
  source .venv/bin/activate
  python3 -m pip install -r requirements.txt
  python3 run_local.py --pg-bin /path/to/postgresql/bin
В другом терминале:
  python3 client.py 5
  python3 client.py 5
  python3 client.py 4
  python3 client.py 6
Результаты: 200/result=6, 409/DUPLICATE_NUMBER,
409/PREDECESSOR_OF_PROCESSED, 200/result=7.
Оба бизнес-отказа выводятся JSON-строками в stdout приложения и видны
в терминале run_local.py. Логи не перенаправляются в файл или stderr.
Ctrl-C останавливает процессы. Данные остаются в .runtime.
Порты: веб 8080, приложение 8081, PostgreSQL 54329; задаются аргументами.
Каждому варианту нужен отдельный каталог .runtime и отдельная база.

HTTP: POST /increment, application/json, {"number":5}.
Вход: целое 0..N; N по умолчанию 1000000. Ответ N+1 допустим.
Ошибки: 400 неверный ввод, 409 бизнес-отказ, 503 проблема БД,
502 прокси не может обратиться к приложению.
История включает бизнес-отказы для корректных чисел; повтор отказа - повтор.
В базе сохраняется вход n, а не результат n+1. Проверка повтора первая.

Проверка с временной БД, двумя приложениями и двумя прокси:
  python3 test_integration.py --pg-bin /path/to/postgresql/bin
Тесты раздельно захватывают stdout и stderr. Результат: test_results.json.
Штатный запускатель отдельно проверен: launch_results.json.
Диаграммы компонентов и последовательностей: .puml, .png, .svg.
Отчёт: report.pdf. Результат для сдачи - ссылка на Git-репозиторий.
Это локальная учебная система без авторизации и TLS.
