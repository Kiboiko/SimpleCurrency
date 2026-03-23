require 'json'
require 'net/http'
require 'time'
require 'fileutils'
require_relative 'simple_currency_cacher/version'

module SimpleCurrencyCacher
  # Custom error for network issues
  class NetworkError < StandardError; end

  # Custom error for invalid currencies
  class CurrencyNotFoundError < StandardError; end

  # Path to the cache file in user's home directory
  CACHE_FILE = File.expand_path('~/.currency_cache.json')

  # Доступ кэш файла и API можно менять (нужно для тестов)
  @cache_file = CACHE_FILE
  @api_enabled = true

  class << self
    attr_accessor :cache_file, :api_enabled
  end

  # Cache duration: 24 hours in seconds
  CACHE_DURATION = 24 * 60 * 60

  # API URL template for fetching exchange rates (free API)
  # Некоторые API позволяют указывать базовую валюту прямо в URL.
  API_URL_TEMPLATE = 'https://api.exchangerate-api.com/v4/latest/%<base>s'

  # Main method to convert currency
  # @param amount [Float] The amount to convert
  # @param from [String] The source currency code (например, 'USD')
  # @param to [String] The target currency code (например, 'EUR')
  # @return [Float] The converted amount
  # @raise [CurrencyNotFoundError] If currency is not found
  # @raise [NetworkError] If нет интернета и нет кэша
  def self.convert(amount, from:, to:)
    from = from.upcase
    to = to.upcase

    # Быстрый путь: если валюты совпадают
    return amount if from == to

    # Получаем курсы, базируясь на 'from'
    rates = get_rates_for_base(from)

    # Если не удалось получить курсы для базовой валюты — значит валюта не поддерживается
    raise CurrencyNotFoundError, "Currency #{from} not found" unless rates.is_a?(Hash) && !rates.empty?

    rate = rates[to]
    raise CurrencyNotFoundError, "Currency #{to} not found" unless rate

    amount * rate
  end

  private

  # Получаем курсы для заданной базовой валюты, либо из кэша, либо из API
  def self.get_rates_for_base(base)
    if cache_valid?(base)
      load_cache(base)
    elsif api_enabled
      fetch_and_cache(base)
    else
      raise NetworkError, "API disabled and no valid cache for #{base}"
    end
  end

  # Проверяет, валиден ли кэш для конкретной базовой валюты
  # (существует ли и не старше 24 часов)
  def self.cache_valid?(base)
    return false unless File.exist?(cache_file)

    data = JSON.parse(File.read(cache_file))
    base_data = data[base]
    return false unless base_data

    timestamp = base_data['timestamp']
    # Если текущее время минус метка времени меньше CACHE_DURATION — кэш валиден
    Time.now.to_i - timestamp < CACHE_DURATION
  rescue JSON::ParserError
    # Если кэш повреждён, считаем, что он недействителен
    false
  end

  # Загружает курсы из кэша для конкретной базовой валюты
  def self.load_cache(base)
    data = JSON.parse(File.read(cache_file))
    data.dig(base, 'rates') || {}
  rescue JSON::ParserError
    {}
  end
  

  # Загружает курсы из API и сохраняет их в кэш
  def self.fetch_and_cache(base)
    begin
      uri = URI(format(API_URL_TEMPLATE, base: base))
      response = Net::HTTP.get(uri)
      data = JSON.parse(response)
      rates = data['rates']

      # Если API вернуло ответ без ключа 'rates', значит валюта не поддерживается
      raise CurrencyNotFoundError, "Currency #{base} not found" unless rates.is_a?(Hash)

      # Подготовка структуры кэша: несколько базовых валют в одном файле
      cache_data = File.exist?(cache_file) ? JSON.parse(File.read(cache_file)) : {}
      cache_data[base] = {
        'timestamp' => Time.now.to_i,
        'rates' => rates
      }

      # Гарантируем, что папка существует
      FileUtils.mkdir_p(File.dirname(cache_file))
      File.write(cache_file, JSON.generate(cache_data))

      rates
    rescue CurrencyNotFoundError => e
      # Если валюта не поддерживается — передаём ошибку дальше
      raise e
    rescue => e
      # Если не удалось получить данные из сети, пытаемся взять из кэша
      if File.exist?(CACHE_FILE)
        load_cache(base)
      else
        raise NetworkError, "Unable to fetch rates and no cache available: #{e.message}"
      end
    end
  end
end