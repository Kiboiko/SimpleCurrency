require 'telegram/bot'
require 'simple_currency_cacher'

module SimpleCurrencyBot
  class Bot
    POPULAR_CURRENCIES = ['USD', 'EUR', 'RUB', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF']

    def initialize(token)
      @token = token
      @user_states = {}  # chat_id => { step: :waiting_for_amount, amount: nil, from: nil, to: nil }
    end

    def start
      Telegram::Bot::Client.run(@token) do |bot|
        bot.listen do |message|
          handle_message(bot, message)
        end
      end
    end

    private

    def handle_message(bot, message)
      chat_id = message.chat.id
      text = message.text

      # Handle callback queries for inline keyboards
      if message.respond_to?(:callback_query) && message.callback_query
        handle_callback(bot, message.callback_query)
        return
      end

      case text
      when '/start'
        reset_user_state(chat_id)
        send_welcome_message(bot, chat_id)
      when '/help'
        send_help_message(bot, chat_id)
      when '/convert'
        start_conversion_process(bot, chat_id)
      else
        handle_conversion_input(bot, chat_id, text)
      end
    end

    def handle_callback(bot, callback)
      chat_id = callback.message.chat.id
      data = callback.data

      state = @user_states[chat_id] || {}

      case state[:step]
      when :waiting_for_from
        state[:from] = data
        state[:step] = :waiting_for_to
        @user_states[chat_id] = state
        send_currency_selection(bot, chat_id, "Выберите валюту, в которую конвертировать:", :to)
      when :waiting_for_to
        state[:to] = data
        perform_conversion(bot, chat_id, state)
        reset_user_state(chat_id)
      end

      bot.api.answer_callback_query(callback_query_id: callback.id)
    end

    def send_welcome_message(bot, chat_id)
      kb = [
        Telegram::Bot::Types::InlineKeyboardButton.new(text: '💱 Конвертировать валюту', callback_data: '/convert'),
        Telegram::Bot::Types::InlineKeyboardButton.new(text: '❓ Помощь', callback_data: '/help')
      ]
      markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)

      text = <<~TEXT
        🌟 *Добро пожаловать в Currency Bot!*

        Я помогу вам конвертировать валюты с актуальными курсами.

        Выберите действие ниже или используйте команды:
        • /convert - начать конвертацию
        • /help - справка
      TEXT

      bot.api.send_message(chat_id: chat_id, text: text, parse_mode: 'Markdown', reply_markup: markup)
    end

    def send_help_message(bot, chat_id)
      text = <<~TEXT
        📖 *Справка по использованию*

        *Команды:*
        • /start - начать заново
        • /convert - конвертировать валюту
        • /help - эта справка

        *Как конвертировать:*
        1. Введите сумму (например: 100)
        2. Выберите валюту из списка
        3. Выберите валюту в которую конвертировать

        *Примеры:*
        • /convert 100 USD RUB
        • 500 EUR to GBP

        Поддерживаемые валюты: USD, EUR, RUB, GBP, JPY, CAD, AUD, CHF и многие другие.
      TEXT

      bot.api.send_message(chat_id: chat_id, text: text, parse_mode: 'Markdown')
    end

    def start_conversion_process(bot, chat_id)
      @user_states[chat_id] = { step: :waiting_for_amount }
      bot.api.send_message(chat_id: chat_id, text: "💰 Введите сумму для конвертации (например: 100.50):")
    end

    def handle_conversion_input(bot, chat_id, text)
      state = @user_states[chat_id] || {}

      case state[:step]
      when :waiting_for_amount
        amount = parse_amount(text)
        if amount
          state[:amount] = amount
          state[:step] = :waiting_for_from
          @user_states[chat_id] = state
          send_currency_selection(bot, chat_id, "Выберите валюту, из которой конвертировать:", :from)
        else
          bot.api.send_message(chat_id: chat_id, text: "❌ Пожалуйста, введите корректную сумму (число).")
        end
      else
        # If no active conversion, show help
        send_welcome_message(bot, chat_id)
      end
    end

    def send_currency_selection(bot, chat_id, message, type)
      buttons = POPULAR_CURRENCIES.map do |currency|
        Telegram::Bot::Types::InlineKeyboardButton.new(text: currency, callback_data: currency)
      end

      # Add "Other" button for custom currency
      buttons << Telegram::Bot::Types::InlineKeyboardButton.new(text: '🔍 Другая', callback_data: 'other')

      # Arrange in rows of 4
      keyboard = buttons.each_slice(4).to_a
      markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)

      bot.api.send_message(chat_id: chat_id, text: message, reply_markup: markup)
    end

    def perform_conversion(bot, chat_id, state)
      amount = state[:amount]
      from = state[:from]
      to = state[:to]

      begin
        result = SimpleCurrencyCacher.convert(amount, from: from, to: to)
        text = <<~TEXT
          ✅ *Результат конвертации*

          #{amount} #{from} = #{result.round(2)} #{to}

          Курс: #{(result / amount).round(4)} #{to}/#{from}
        TEXT

        kb = [
          Telegram::Bot::Types::InlineKeyboardButton.new(text: '🔄 Конвертировать ещё', callback_data: '/convert'),
          Telegram::Bot::Types::InlineKeyboardButton.new(text: '🏠 Главное меню', callback_data: '/start')
        ]
        markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)

        bot.api.send_message(chat_id: chat_id, text: text, parse_mode: 'Markdown', reply_markup: markup)
      rescue SimpleCurrencyCacher::CurrencyNotFoundError => e
        bot.api.send_message(chat_id: chat_id, text: "❌ Ошибка: #{e.message}")
      rescue SimpleCurrencyCacher::NetworkError => e
        bot.api.send_message(chat_id: chat_id, text: "🌐 Ошибка сети: #{e.message}")
      rescue => e
        bot.api.send_message(chat_id: chat_id, text: "❌ Неизвестная ошибка: #{e.message}")
      end
    end

    def parse_amount(text)
      Float(text.strip) rescue nil
    end

    def reset_user_state(chat_id)
      @user_states.delete(chat_id)
    end
  end
end