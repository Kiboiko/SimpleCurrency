require 'spec_helper'
require 'simple_currency_cacher'
require 'tmpdir'
require 'json'

RSpec.describe SimpleCurrencyCacher do
  around(:each) do |example|
    original_cache_file = SimpleCurrencyCacher.cache_file
    original_api_enabled = SimpleCurrencyCacher.api_enabled

    Dir.mktmpdir do |tmpdir|
      SimpleCurrencyCacher.cache_file = File.join(tmpdir, 'currency_cache.json')
      SimpleCurrencyCacher.api_enabled = true
      example.run
    end

    SimpleCurrencyCacher.cache_file = original_cache_file
    SimpleCurrencyCacher.api_enabled = original_api_enabled
  end
  describe '.convert' do
    it 'converts an amount from USD to another currency' do
      # В этом тесте предполагается, что API доступен или есть кэш
      result = SimpleCurrencyCacher.convert(100, from: 'USD', to: 'EUR')
      expect(result).to be_a(Float)
      expect(result).to be > 0
    end

    it 'converts between non-USD currencies (EUR -> GBP)' do
      result = SimpleCurrencyCacher.convert(100, from: 'EUR', to: 'GBP')
      expect(result).to be_a(Float)
      expect(result).to be > 0
    end

    it 'converts from EUR to USD' do
      result = SimpleCurrencyCacher.convert(100, from: 'EUR', to: 'USD')
      expect(result).to be_a(Float)
      expect(result).to be > 0
    end

    it 'converts to and from Russian ruble (RUB)' do
      result_to_rub = SimpleCurrencyCacher.convert(100, from: 'USD', to: 'RUB')
      result_from_rub = SimpleCurrencyCacher.convert(100, from: 'RUB', to: 'USD')

      expect(result_to_rub).to be_a(Float)
      expect(result_to_rub).to be > 0

      expect(result_from_rub).to be_a(Float)
      expect(result_from_rub).to be > 0
    end

    it 'считывает кэш при отключенном API' do
      # Принудительно сохраняем фиктивные курсы в кэш
      cache_data = {
        'USD' => {
          'timestamp' => Time.now.to_i,
          'rates' => { 'RUB' => 100.0, 'EUR' => 0.9 }
        },
        'RUB' => {
          'timestamp' => Time.now.to_i,
          'rates' => { 'USD' => 0.01, 'EUR' => 0.009 }
        }
      }
      File.write(SimpleCurrencyCacher.cache_file, JSON.generate(cache_data))

      SimpleCurrencyCacher.api_enabled = false

      expect(SimpleCurrencyCacher.convert(1, from: 'USD', to: 'RUB')).to eq(100.0)
      expect(SimpleCurrencyCacher.convert(1, from: 'USD', to: 'RUB')).to be >= 20

      # Проверяем точность обратной конвертации
      expect(SimpleCurrencyCacher.convert(100, from: 'RUB', to: 'USD')).to be_within(0.0001).of(1.0)
    end

    it 'raises NetworkError при отключенном API и отсутствии кэша' do
      SimpleCurrencyCacher.api_enabled = false
      File.delete(SimpleCurrencyCacher.cache_file) if File.exist?(SimpleCurrencyCacher.cache_file)

      expect {
        SimpleCurrencyCacher.convert(1, from: 'USD', to: 'RUB')
      }.to raise_error(SimpleCurrencyCacher::NetworkError)
    end

    it 'raises CurrencyNotFoundError for invalid currency' do
      expect {
        SimpleCurrencyCacher.convert(100, from: 'INVALID', to: 'USD')
      }.to raise_error(SimpleCurrencyCacher::CurrencyNotFoundError)
    end
  end
end