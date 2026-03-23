# simple_currency_cacher

Простой Ruby-гем для конвертации валют через публичный API с локальным кэшированием курсов.

## 📌 Быстрый старт

```bash
bundle install
bundle exec rspec
```

## 🚀 Использование

```ruby
require 'simple_currency_cacher'

# Конвертирует 100 USD в RUB
result = SimpleCurrencyCacher.convert(100, from: 'USD', to: 'RUB')

# Конвертирует 100 EUR в GBP
result = SimpleCurrencyCacher.convert(100, from: 'EUR', to: 'GBP')
```

## 🧠 Логика кэширования

Курс сохраняется в файл `~/.currency_cache.json`.
- Если с момента сохранения прошло меньше 24 часов — используется кэш.
- Если прошло больше 24 часов — скачиваются свежие курсы.

## 🚨 Обработка ошибок

- Если нет интернета и нет сохранённого кэша — вызывается `SimpleCurrencyCacher::NetworkError`.
- Если указана несуществующая валюта — вызывается `SimpleCurrencyCacher::CurrencyNotFoundError`.

## 🧪 Тесты

Запустить тесты:

```bash
bundle exec rspec
```

Тесты проверяют конвертацию между валютами и правильную обработку ошибок.


© 2026. MIT License.
