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

  # Cache duration: 24 hours in seconds
  CACHE_DURATION = 24 * 60 * 60

  # API URL for fetching exchange rates (free API)
  API_URL = 'https://api.exchangerate-api.com/v4/latest/USD'

  # Main method to convert currency
  # @param amount [Float] The amount to convert
  # @param from [String] The source currency code (e.g., 'USD')
  # @param to [String] The target currency code (e.g., 'EUR')
  # @return [Float] The converted amount
  # @raise [CurrencyNotFoundError] If currency is not found
  # @raise [NetworkError] If no internet and no cache
  def self.convert(amount, from:, to:)
    rates = get_rates

    # Calculate conversion rate
    if from == 'USD'
      rate = rates[to]
    else
      from_rate = rates[from]
      to_rate = rates[to]
      rate = to_rate / from_rate if from_rate && to_rate
    end

    raise CurrencyNotFoundError, "Currency #{from} or #{to} not found" unless rate

    amount * rate
  end

  private

  # Get exchange rates, either from cache or API
  def self.get_rates
    if cache_valid?
      load_cache
    else
      fetch_and_cache
    end
  end

  # Check if cache is valid (exists and not older than 24 hours)
  def self.cache_valid?
    return false unless File.exist?(CACHE_FILE)

    data = JSON.parse(File.read(CACHE_FILE))
    timestamp = data['timestamp']
    # Check if current time minus timestamp is less than cache duration
    Time.now.to_i - timestamp < CACHE_DURATION
  end

  # Load rates from cache file
  def self.load_cache
    data = JSON.parse(File.read(CACHE_FILE))
    data['rates']
  end

  # Fetch rates from API and save to cache
  def self.fetch_and_cache
    begin
      uri = URI(API_URL)
      response = Net::HTTP.get(uri)
      data = JSON.parse(response)
      rates = data['rates']

      # Prepare cache data with timestamp
      cache_data = {
        timestamp: Time.now.to_i,
        rates: rates
      }

      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(CACHE_FILE))
      File.write(CACHE_FILE, JSON.generate(cache_data))

      rates
    rescue => e
      # If fetch fails, try to use cache if available
      if File.exist?(CACHE_FILE)
        load_cache
      else
        raise NetworkError, "Unable to fetch rates and no cache available: #{e.message}"
      end
    end
  end
end