class AlpacaService
  include HTTParty
  base_uri ENV['BASE_URL']

  DEFAULT_QTY = 5
  BUDGET_FRACTION = 5
  DEFAULT_STRIKE_OFFSET = 12
  STRIKE_INTERVAL = 5

  RSI_OVERBOUGHT = 56
  RSI_OVERBOUGHT_SCALE_2 = 65
  RSI_OVERBOUGHT_SCALE_3 = 74
  RSI_OVERSOLD = 43
  RSI_OVERSOLD_SCALE_2 = 34
  RSI_OVERSOLD_SCALE_3 = 25
  RSI_PROFIT_MARGIN = 0.2

  SR_UPPER = 60
  SR_TAKE_PROFIT_CEILING = 88
  SR_CALL_ENTRY_CEILING = 70
  SR_TAKE_PROFIT_FLOOR = 30
  SR_PUT_ENTRY_FLOOR = 50
  SR_PROFIT_MARGIN = 0.4

  MOMENTUM_GAP = 7
  SURF_CALL_CEILING = 83
  SURF_PUT_FLOOR = 21
  SURF_CALL_PROFIT_MARGIN = 0.2
  SURF_PUT_PROFIT_MARGIN = 0.25
  SELL_TRANCHE_FRACTION = 10
  SMALL_DIP_PCT = 30
  SMALL_DIP_QTY_FRACTION = 50
  CALL_AVG_DOWN_PCT = 11
  PUT_AVG_DOWN_PCT = 7
  MAX_POSITION_MULTIPLE = 6

  @headers = {
    'apca-api-key-id' => ENV['APCA_API_KEY'],
    'apca-api-secret-key' => ENV['APCA_API_SECRET_KEY'],
    'accept' => 'application/json',
  }

  def self.create_order options={}
    opts = options.with_indifferent_access
    body = opts[:body]
    post(ENV['ORDERS_URL'], body: body, headers: @headers)
  end

  def self.option_contracts options
    opts = options.with_indifferent_access
    query = opts[:query] || {}
    response = get(ENV['OPTIONS_CONTRACTS_URL'], headers: @headers, query: query).with_indifferent_access
    response[:option_contracts]
  end

  def self.orders options={}
    opts = options.with_indifferent_access
    query = opts[:query] || {}
    query[:after] ||= Time.now.beginning_of_day.strftime('%Y-%m-%d')
    get(ENV['ORDERS_URL'], headers: @headers, query: opts[:query])
  end

  def self.positions
    get(ENV['POSITIONS_URL'], headers: @headers)
  end

  def self.portfolio
    get(ENV['PORTFOLIO_ENDPOINT'], headers: @headers).with_indifferent_access
  end

  def self.latest_quote_for ticker, feed=:sip
    get(ENV['LATEST_QUOTE_ENDPOINT'], headers: @headers, query: { symbols: ticker, feed: feed })
  end

  def self.latest_option_quote_for ticker, feed=:opra
    get(ENV['LATEST_OPTIONS_QUOTE_ENDPOINT'], headers: @headers, query: { symbols: ticker, feed: feed })
  end

  def self.contract_data_for options={}
    opts = options.with_indifferent_access
    query = {
      underlying_symbols: opts[:ticker],
      status: "active",
      expiration_date_gte: opts[:date].beginning_of_month.strftime('%Y-%m-%d'),
      expiration_date_lte: opts[:date].end_of_month.strftime('%Y-%m-%d'),
      strike_price_gte: opts[:strike_price],
      strike_price_lte: opts[:strike_price],
      type: opts[:options_type]
    }
    option_contracts(query: query)
  end
  
  def self.create_options_order options={}
    opts = options.with_indifferent_access
    side = opts[:side]
    type = opts[:type] || :market
    qty = opts[:qty] || DEFAULT_QTY
    limit = opts[:limit]
    strike_price = opts[:strike_price]
    date = opts[:date] || Date.today.beginning_of_month + 1.months
    body = JSON.generate({
      symbol: opts[:symbol],
      qty: qty,
      side: side,
      type: type,
      limit_price: limit,
      time_in_force: :day
    })
    create_order body: body
  end

  def self.buy_call options={}
    opts = options.with_indifferent_access.merge(side: :buy, options_type: :call)
    opts[:symbol] ||= opts[:call_symbol]
    trade_options opts
  end

  def self.sell_call options={}
    opts = options.with_indifferent_access.merge(side: :sell, options_type: :call)
    opts[:symbol] ||= opts[:call_symbol]
    trade_options opts
  end

  def self.buy_put options={}
    opts = options.with_indifferent_access.merge(side: :buy, options_type: :put)
    opts[:symbol] ||= opts[:put_symbol]
    trade_options opts
  end

  def self.sell_put options={}
    opts = options.with_indifferent_access.merge(side: :sell, options_type: :put)
    opts[:symbol] ||= opts[:put_symbol]
    trade_options opts
  end

  def self.trade_options options={}
    opts = options.with_indifferent_access
    opts[:type] ||= :market
    opts[:qty] ||= DEFAULT_QTY
    opts[:date] ||= Date.today.beginning_of_month + 1.months
    opts[:symbol] ||= contract_data_for(opts).last[:symbol]
    create_options_order opts
  end

  def self.fetch_bars options={}
    opts = options.with_indifferent_access
    opts[:timeframe] ||= '1T'
    opts[:limit] ||= 2000
    opts[:start] ||= (Date.today - 7.day).beginning_of_day.rfc3339
    opts[:date] ||= Date.today.beginning_of_month + 1.months
    query = {
      timeframe: opts[:timeframe],
      limit: opts[:limit]
    }
    url = ENV['HISTORICAL_BARS_BASE_URL'] + "/#{opts[:ticker]}/bars"
    response = get(url, headers: @headers, query: query)['bars']
    response.map{ |d| {date_time: d["t"], close: d["c"],  high: d["h"], open: d["o"], low: d["l"], value: d["c"]} }
  end

  def self.fetch_options_bars options={}
    opts = options.with_indifferent_access
    opts[:options_type] ||= :call
    opts[:timeframe] ||= '3T'
    opts[:limit] ||= 2000
    opts[:date] ||= Date.today.beginning_of_month + 1.months
    opts[:start] ||= (Date.today - 7.day).beginning_of_day.rfc3339
    query = {
      symbols: opts[:symbol],
      timeframe: opts[:timeframe],
      limit: opts[:limit],
      start: opts[:start]
    }
    get(ENV['HISTORICAL_BARS_OPTIONS_URL'], headers: @headers, query: query)
  end

  def self.calculate_signals data, options={}
    opts = options.with_indifferent_access
    period = opts[:period] || 30
    indicator = opts[:indicator]
    values = "TechnicalAnalysis::#{opts[:indicator]}".constantize.calculate(data, period: period)
    return values.map{|v| v.rsi.to_f} if indicator.downcase.to_sym.eql? :rsi
    return values.map{|v| v.sr_signal.to_f} if indicator.downcase.to_sym.eql? :sr
  end

  def self.straddle_rsi options={}
    opts = options.with_indifferent_access
    data = fetch_bars opts
    signals = calculate_signals(data, {indicator: "Rsi"})
    call_positions = positions.select{|p| p["symbol"].include? "0C00"}
    put_positions = positions.select{|p| p["symbol"].include? "0P00"}
    if signals.first >= RSI_OVERBOUGHT
      pq = put_positions.inject(0) {|s, p| s += p["qty"].to_i}
      call_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_call(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + RSI_PROFIT_MARGIN)
      end
      if pq.eql? 0
        buy_put opts
      elsif pq > 0 and pq < (opts[:qty] * 2) and signals.first >= RSI_OVERBOUGHT_SCALE_2 and !put_positions.select{|p| p["symbol"].eql? opts[:put_symbol]}.first.present?
        buy_put opts
      elsif pq > 0 and pq < (opts[:qty] * 3) and signals.first >= RSI_OVERBOUGHT_SCALE_3 and !put_positions.select{|p| p["symbol"].eql? opts[:put_symbol]}.first.present?
        buy_put opts
      end
    elsif signals.first <= RSI_OVERSOLD
      cq = call_positions.inject(0) { |s, p| s += p["qty"].to_i }
      put_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_put(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + RSI_PROFIT_MARGIN)
      end
      if cq.eql? 0
        buy_call opts
      elsif cq > 0 and cq < (opts[:qty] * 2) and signals.first <= RSI_OVERSOLD_SCALE_2 and !call_positions.select{|p| p["symbol"].eql? opts[:call_symbol]}.first.present?
        buy_call opts
      elsif cq > 0 and cq < (opts[:qty] * 3) and signals.first <= RSI_OVERSOLD_SCALE_3 and !call_positions.select{|p| p["symbol"].eql? opts[:call_symbol]}.first.present?
        buy_call opts
      end
    end
  end

  def self.straddle_sr options={}
    opts = options.with_indifferent_access
    data = fetch_bars opts
    signals = calculate_signals(data, {indicator: "Sr"})
    call_positions = positions.select{|p| p["symbol"].include? "0C00"}
    put_positions = positions.select{|p| p["symbol"].include? "0P00"}
    if signals.first >= SR_UPPER
      cq = call_positions.inject(0) {|s, p| s += p["qty"].to_i}
      call_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_call(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + SR_PROFIT_MARGIN)
      end if signals.first >= SR_TAKE_PROFIT_CEILING
      buy_call opts if cq.eql? 0 and signals.first <= SR_CALL_ENTRY_CEILING
    elsif signals.first <= SR_UPPER
      pq = put_positions.inject(0) { |s, p| s += p["qty"].to_i }
      put_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_put(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + SR_PROFIT_MARGIN)
      end if signals.first <= SR_TAKE_PROFIT_FLOOR
      buy_put opts if pq.eql? 0 and signals.first >= SR_PUT_ENTRY_FLOOR
    end
  end

  def self.surf_straddle options={}
    opts = options.with_indifferent_access
    data = fetch_bars opts
    signals = calculate_signals(data, {indicator: "Sr"})
    call_positions = positions.select{|p| p["symbol"].include? "C00"}
    put_positions = positions.select{|p| p["symbol"].include? "P00"}
    cq = call_positions.inject(0) {|s, p| s += p["qty"].to_i}
    pq = put_positions.inject(0) { |s, p| s += p["qty"].to_i }
    buy_call opts.merge(qty: opts[:call_qty]) if cq.eql? 0 and signals[0] - signals[3] >= MOMENTUM_GAP and signals[0] < SURF_CALL_CEILING
    buy_put opts.merge(qty: opts[:put_qty]) if pq.eql? 0 and signals[3] - signals[0] >= MOMENTUM_GAP and signals[0] > SURF_PUT_FLOOR
    positions.each do |position|
      sell_qty = (position["qty"].to_f/SELL_TRANCHE_FRACTION).ceil
      quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
      current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
      avg = position["avg_entry_price"].to_f
      qty = (position["qty"].to_i/SMALL_DIP_QTY_FRACTION).to_i if ((avg - current_price) * 100)/avg <= SMALL_DIP_PCT
      qty ||= calc_qty (current_price * 100), true
      new_avg = ((avg * position["qty"].to_i) + (current_price * qty))/(position["qty"].to_i + qty)
      averaging_percentage = ((avg - new_avg) * 100.0)/avg if new_avg < avg
      sell_call(symbol: position["symbol"], qty: sell_qty) if position["symbol"].include? "0C00" and current_price > (avg + SURF_CALL_PROFIT_MARGIN)
      sell_put(symbol: position["symbol"], qty: sell_qty) if position["symbol"].include? "0P00" and current_price > (avg + SURF_PUT_PROFIT_MARGIN)
      buy_call opts.merge(qty: qty) if position["symbol"].include? "C00" and averaging_percentage and averaging_percentage >= CALL_AVG_DOWN_PCT and cq < opts[:call_qty] * MAX_POSITION_MULTIPLE
      buy_put opts.merge(qty: qty) if position["symbol"].include? "P00" and averaging_percentage and averaging_percentage >= PUT_AVG_DOWN_PCT and pq < opts[:put_qty] * MAX_POSITION_MULTIPLE
    end
  end

  def self.calc_qty price, full_budget=false
    equity = portfolio[:equity].last.to_f
    purchasing_power = equity - positions.inject(0) {|s, p| s += p["market_value"].to_f}
    qty = (purchasing_power/price).to_i if full_budget
    qty ||= (purchasing_power/(BUDGET_FRACTION * price)).round
    qty
  end 

  def self.intra_day options={}
    opts = options.with_indifferent_access
    opts[:diff] ||= DEFAULT_STRIKE_OFFSET
    opts[:date] ||= Date.today + 1.months
    quotes = latest_quote_for(opts[:ticker]).with_indifferent_access
    call_positions = positions.select{|p| p["symbol"].include? "C00"}
    put_positions = positions.select{|p| p["symbol"].include? "P00"}
    latest_quote = ((quotes[:quotes][opts[:ticker]][:ap] + quotes[:quotes][opts[:ticker]][:bp])/2).round
    put_offset = (latest_quote - opts[:diff]) % STRIKE_INTERVAL
    call_offset = (latest_quote + opts[:diff]) % STRIKE_INTERVAL
    put_strike_price = latest_quote - opts[:diff] - put_offset
    call_strike_price = latest_quote + opts[:diff] - call_offset

    opts[:put_symbol] = (put_positions.first || {})["symbol"]
    opts[:call_symbol] = (call_positions.first || {})["symbol"]
    opts[:put_symbol] ||= contract_data_for(opts.merge(strike_price: put_strike_price, options_type: :put)).last[:symbol]
    opts[:call_symbol] ||= contract_data_for(opts.merge(strike_price: call_strike_price, options_type: :call)).last[:symbol]

    put_option_quotes = latest_option_quote_for(opts[:put_symbol]).with_indifferent_access
    put_quote = ((put_option_quotes[:quotes][opts[:put_symbol]][:ap] + put_option_quotes[:quotes][opts[:put_symbol]][:bp])/2.0) * 100
    call_option_quotes = latest_option_quote_for(opts[:call_symbol]).with_indifferent_access
    call_quote = ((call_option_quotes[:quotes][opts[:call_symbol]][:ap] + call_option_quotes[:quotes][opts[:call_symbol]][:bp])/2.0) * 100
    opts[:put_qty] ||= calc_qty put_quote
    opts[:call_qty] ||= calc_qty call_quote
    surf_straddle opts
  end
end