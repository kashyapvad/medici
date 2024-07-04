class AlpacaService

  ORDER_ENDPOINT = 'https://paper-api.alpaca.markets/v2/orders'
  OPTIONS_LIST_ENDPOINT = 'https://paper-api.alpaca.markets/v2/options/contracts'
  HEADERS = {
    'apca-api-key-id' => ENV['APCA_API_KEY'],
    'apca-api-secret-key' => ENV['APCA_API_SECRET_KEY'],
    'accept' => 'application/json',
  }
  def self.create_order options={}
    opts = options.with_indifferent_access
    body = opts[:body]
    HTTParty.post(ORDER_ENDPOINT, body: body, headers: HEADERS)
  end
  
  def self.option_symbols_for ticker, strike_price, date, type=nil
    query = {
      underlying_symbols: ticker,
      status: "active",
      expiration_date_gte: date.beginning_of_month.strftime('%Y-%m-%d'),
      expiration_date_lte: date.end_of_month.strftime('%Y-%m-%d'),
      strike_price_gte: strike_price,
      strike_price_lte: strike_price,
      type: type
    }
    response = HTTParty.get(OPTIONS_LIST_ENDPOINT, headers: HEADERS, query: query).with_indifferent_access
    response[:option_contracts].first[:symbol]
  end
  
  def self.buy_call options={}
    opts = options.with_indifferent_access
    type = opts[:type] || :market
    ticker = opts[:ticker] || :TSLA
    qty = opts[:qty] || 10
    limit = opts[:limit]
    strike_price = opts[:strike_price]
    date = opts[:date] || Date.today.beginning_of_month + 3.months
    
    symbol = option_symbols_for ticker, strike_price, date, :call
    body = JSON.generate({
      symbol: symbol,
      qty: qty,
      side: :buy,
      type: type,
      limit_price: limit,
      time_in_force: :day
    })
    create_order body: body
  end
end