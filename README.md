# Диагностика — выбор учебного маршрута

Интерактивный тест из 24 заданий по 8 математическим разделам. Ответы сохраняются в облачной базе Supabase; каждая попытка отдельная.

## Публикация через GitHub Pages

1. Откройте Settings в этом репозитории.
2. В меню слева выберите Pages.
3. В разделе Build and deployment укажите Source: Deploy from a branch.
4. Выберите Branch: main и Folder: /(root), затем нажмите Save.
5. После публикации сайт будет доступен по адресу:
   https://math-start.github.io/diagnostika-marshruta/

## Инфраструктура

- Статическая страница: index.html (GitHub Pages).
- Серверная часть: Supabase Edge Function diagnostic-api.
- База ответов: public.diagnostic_attempts.
- Доступ к таблице для anon/authenticated закрыт; операции с базой выполняются серверной функцией.

Не помещайте секретный ключ Supabase в HTML. В index.html используется только publishable key.
