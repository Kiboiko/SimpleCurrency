require 'spec_helper'
require 'simple_currency_cacher'

RSpec.describe SimpleCurrencyCacher do
  describe '.convert' do
    it 'converts an amount from USD to another currency' do
      # This test assumes the API is accessible or cache exists
      # In a real scenario, you might mock the API response
      result = SimpleCurrencyCacher.convert(100, from: 'USD', to: 'EUR')
      expect(result).to be_a(Float)
      expect(result).to be > 0
    end

    it 'raises CurrencyNotFoundError for invalid currency' do
      expect {
        SimpleCurrencyCacher.convert(100, from: 'INVALID', to: 'USD')
      }.to raise_error(SimpleCurrencyCacher::CurrencyNotFoundError)
    end
  end
end