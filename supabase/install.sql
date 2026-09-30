-- تثبيت قاعدة البيانات بسطرين (مناسب للهاتف)
create extension if not exists http with schema extensions;
do $b$ begin execute (select content from extensions.http_get('https://raw.githubusercontent.com/almajhool-dev/almajhool-ap/main/supabase/schema.sql')); end $b$;
