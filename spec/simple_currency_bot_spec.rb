require 'spec_helper'
require 'simple_currency_bot'
require 'telegram/bot'

RSpec.describe SimpleCurrencyBot::Bot do
  let(:token) { 'fake_token' }
  let(:bot_instance) { SimpleCurrencyBot::Bot.new(token) }

  describe '#initialize' do
    it 'initializes with a token and empty user states' do
      expect(bot_instance.instance_variable_get(:@token)).to eq(token)
      expect(bot_instance.instance_variable_get(:@user_states)).to eq({})
    end
  end

  describe '#handle_text_message' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }
    let(:message) { double('message') }
    let(:chat) { double('chat', id: 123) }

    before do
      allow(bot).to receive(:api).and_return(api)
      allow(message).to receive(:chat).and_return(chat)
      allow(message).to receive(:text)
    end

    context 'when message is /start' do
      before { allow(message).to receive(:text).and_return('/start') }

      it 'resets user state and sends welcome message' do
        expect(bot_instance).to receive(:reset_user_state).with(123)
        expect(bot_instance).to receive(:send_welcome_message).with(bot, 123)

        bot_instance.send(:handle_text_message, bot, message)
      end
    end

    context 'when message is /help' do
      before { allow(message).to receive(:text).and_return('/help') }

      it 'sends help message' do
        expect(bot_instance).to receive(:send_help_message).with(bot, 123)

        bot_instance.send(:handle_text_message, bot, message)
      end
    end

    context 'when message is /convert' do
      before { allow(message).to receive(:text).and_return('/convert') }

      it 'starts conversion process' do
        expect(bot_instance).to receive(:start_conversion_process).with(bot, 123)

        bot_instance.send(:handle_text_message, bot, message)
      end
    end

    context 'when message is /rates' do
      before { allow(message).to receive(:text).and_return('/rates') }

      it 'sends rates message' do
        expect(bot_instance).to receive(:send_rates_message).with(bot, 123)

        bot_instance.send(:handle_text_message, bot, message)
      end
    end

    context 'when message is other text' do
      before { allow(message).to receive(:text).and_return('some text') }

      it 'handles conversion input' do
        expect(bot_instance).to receive(:handle_conversion_input).with(bot, 123, 'some text')

        bot_instance.send(:handle_text_message, bot, message)
      end
    end
  end

  describe '#handle_callback' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }
    let(:chat) { double('chat', id: 123) }
    let(:message) { double('message', chat: chat) }
    let(:callback) { double('callback', message: message, id: 'callback-id') }

    before do
      allow(bot).to receive(:api).and_return(api)
      allow(api).to receive(:answer_callback_query)
    end

    context 'when callback is /start' do
      before { allow(callback).to receive(:data).and_return('/start') }

      it 'sends welcome message and resets state' do
        expect(bot_instance).to receive(:reset_user_state).with(123)
        expect(bot_instance).to receive(:send_welcome_message).with(bot, 123)

        bot_instance.send(:handle_callback, bot, callback)
      end
    end

    context 'when callback is /convert' do
      before { allow(callback).to receive(:data).and_return('/convert') }

      it 'starts conversion process' do
        expect(bot_instance).to receive(:start_conversion_process).with(bot, 123)

        bot_instance.send(:handle_callback, bot, callback)
      end
    end

    context 'when callback is /rates' do
      before { allow(callback).to receive(:data).and_return('/rates') }

      it 'sends rates message' do
        expect(bot_instance).to receive(:send_rates_message).with(bot, 123)

        bot_instance.send(:handle_callback, bot, callback)
      end
    end

    context 'when callback is currency selection while waiting_for_from' do
      before do
        bot_instance.instance_variable_get(:@user_states)[123] = { step: :waiting_for_from }
        allow(callback).to receive(:data).and_return('USD')
      end

      it 'moves to waiting_for_to and sends currency selection' do
        expect(bot_instance).to receive(:send_currency_selection).with(bot, 123, a_string_including('Выберите валюту'), :to)

        bot_instance.send(:handle_callback, bot, callback)

        state = bot_instance.instance_variable_get(:@user_states)[123]
        expect(state[:from]).to eq('USD')
        expect(state[:step]).to eq(:waiting_for_to)
      end
    end
  end

  describe '#send_welcome_message' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }

    before do
      allow(bot).to receive(:api).and_return(api)
    end

    it 'sends a welcome message with inline keyboard' do
      expect(api).to receive(:send_message).with(
        chat_id: 123,
        text: a_string_including('Добро пожаловать'),
        parse_mode: 'Markdown',
        reply_markup: an_instance_of(Telegram::Bot::Types::InlineKeyboardMarkup)
      )

      bot_instance.send(:send_welcome_message, bot, 123)
    end
  end

  describe '#send_help_message' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }

    before do
      allow(bot).to receive(:api).and_return(api)
    end

    it 'sends a help message' do
      expect(api).to receive(:send_message).with(
        chat_id: 123,
        text: a_string_including('Справка'),
        parse_mode: 'Markdown'
      )

      bot_instance.send(:send_help_message, bot, 123)
    end
  end

  describe '#send_rates_message' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }

    before do
      allow(bot).to receive(:api).and_return(api)
      allow(SimpleCurrencyCacher).to receive(:convert).and_return(75.0)
    end

    it 'sends a rates message with current exchange rates' do
      expect(api).to receive(:send_message).with(
        chat_id: 123,
        text: a_string_including('Текущие курсы валют'),
        parse_mode: 'Markdown',
        reply_markup: an_instance_of(Telegram::Bot::Types::InlineKeyboardMarkup)
      )

      bot_instance.send(:send_rates_message, bot, 123)
    end
  end

  describe '#start_conversion_process' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }

    before do
      allow(bot).to receive(:api).and_return(api)
    end

    it 'sets user state to waiting_for_amount and sends message' do
      expect(api).to receive(:send_message).with(chat_id: 123, text: a_string_including('Введите сумму'))

      bot_instance.send(:start_conversion_process, bot, 123)

      states = bot_instance.instance_variable_get(:@user_states)
      expect(states[123][:step]).to eq(:waiting_for_amount)
    end
  end

  describe '#handle_conversion_input' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }

    before do
      allow(bot).to receive(:api).and_return(api)
    end

    context 'when waiting for amount and valid amount provided' do
      before do
        bot_instance.instance_variable_get(:@user_states)[123] = { step: :waiting_for_amount }
      end

      it 'updates state and sends currency selection' do
        expect(bot_instance).to receive(:send_currency_selection).with(bot, 123, a_string_including('валюту, из которой'), :from)

        bot_instance.send(:handle_conversion_input, bot, 123, '100.5')

        states = bot_instance.instance_variable_get(:@user_states)
        expect(states[123][:amount]).to eq(100.5)
        expect(states[123][:step]).to eq(:waiting_for_from)
      end
    end

    context 'when waiting for amount and invalid amount provided' do
      before do
        bot_instance.instance_variable_get(:@user_states)[123] = { step: :waiting_for_amount }
      end

      it 'sends error message' do
        expect(api).to receive(:send_message).with(chat_id: 123, text: a_string_including('корректную сумму'))

        bot_instance.send(:handle_conversion_input, bot, 123, 'invalid')
      end
    end

    context 'when no active conversion' do
      it 'sends welcome message' do
        expect(bot_instance).to receive(:send_welcome_message).with(bot, 123)

        bot_instance.send(:handle_conversion_input, bot, 123, 'some text')
      end
    end
  end

  describe '#perform_conversion' do
    let(:bot) { double('Telegram::Bot::Client') }
    let(:api) { double('api') }
    let(:state) { { amount: 100, from: 'USD', to: 'RUB' } }

    before do
      allow(bot).to receive(:api).and_return(api)
      allow(SimpleCurrencyCacher).to receive(:convert).and_return(7500.0)
    end

    it 'converts currency and sends result with markup' do
      expect(api).to receive(:send_message).with(
        chat_id: 123,
        text: a_string_including('Результат конвертации'),
        parse_mode: 'Markdown',
        reply_markup: an_instance_of(Telegram::Bot::Types::InlineKeyboardMarkup)
      )

      bot_instance.send(:perform_conversion, bot, 123, state)
    end
  end

  describe '#parse_amount' do
    it 'parses valid float' do
      expect(bot_instance.send(:parse_amount, '123.45')).to eq(123.45)
    end

    it 'returns nil for invalid input' do
      expect(bot_instance.send(:parse_amount, 'invalid')).to be_nil
    end
  end

  describe '#parse_direct_conversion' do
    it 'parses "100 $ ₽" correctly' do
      result = bot_instance.send(:parse_direct_conversion, '100 $ ₽')
      expect(result).to eq({ amount: 100.0, from: 'USD', to: 'RUB' })
    end

    it 'parses "50 € £" correctly' do
      result = bot_instance.send(:parse_direct_conversion, '50 € £')
      expect(result).to eq({ amount: 50.0, from: 'EUR', to: 'GBP' })
    end

    it 'parses "1000 ¥ $" correctly' do
      result = bot_instance.send(:parse_direct_conversion, '1000 ¥ $')
      expect(result).to eq({ amount: 1000.0, from: 'JPY', to: 'USD' })
    end

    it 'parses "200 USD EUR" with currency codes' do
      result = bot_instance.send(:parse_direct_conversion, '200 USD EUR')
      expect(result).to eq({ amount: 200.0, from: 'USD', to: 'EUR' })
    end

    it 'returns nil for invalid format' do
      result = bot_instance.send(:parse_direct_conversion, 'hello world')
      expect(result).to be_nil
    end

    it 'returns nil for unsupported currency' do
      result = bot_instance.send(:parse_direct_conversion, '100 XYZ ABC')
      expect(result).to be_nil
    end
  end
end