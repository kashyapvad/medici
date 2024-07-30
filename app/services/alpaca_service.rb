class AlpacaService
  include HTTParty
  base_uri ENV['BASE_URL']

  @headers = {
    'apca-api-key-id' => ENV['APCA_API_KEY'],
    'apca-api-secret-key' => ENV['APCA_API_SECRET_KEY'],
    'accept' => 'application/json',
  }

  @option_socket_headers = {
    'apca-api-key-id' => ENV['APCA_API_KEY'],
    'apca-api-secret-key' => ENV['APCA_API_SECRET_KEY'],
    'accept' => 'application/msgpack',
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
    qty = opts[:qty] || 5
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
    opts[:qty] ||= 5
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
    respose = get(url, headers: @headers, query: query)['bars']
    respose.map{ |d| {date_time: d["t"], close: d["c"],  high: d["h"], open: d["o"], low: d["l"], value: d["c"]} }
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
    respose = get(ENV['HISTORICAL_BARS_OPTIONS_URL'], headers: @headers, query: query)
    #respose.map{|d| {date_time: d["t"], value: d["c"]}}
  end

  def self.calculate_signals data, options={}
    opts = options.with_indifferent_access
    period = opts[:period] || 30
    indicator = opts[:indicator]
    values = "TechnicalAnalysis::#{opts[:indicator]}".constantize.calculate(data, period: period)
    return values.map{|v| v.rsi.to_f} if indicator.downcase.to_sym.eql? :rsi
    return values.map{|v| v.sr_signal.to_f} if indicator.downcase.to_sym.eql? :sr
  end

  def self.execute_trade options={}
    opts = options.with_indifferent_access
    data = fetch_options_bars opts
    signals = calculate_signals(data)
    open_sell_orders = orders(query: {status: :all, side: :sell}).select{|o| !o["filled_at"].present?}
    open_buy_orders = orders(query: {status: :all, side: :buy}).select{|o| !o["filled_at"].present?}
    position = positions.select{|p| p["symbol"].eql? opts[:symbol]}.first&.with_indifferent_access
    buy_call opts if (signals.first < 47 and position and position[:qty].to_i < 30) or (signals.first < 38 and position and position[:qty].to_i >= 30 and position[:qty].to_i < 45) or (signals.first < 56 and signals.first < signals.second and !position)
    position = positions.select{|p| p["symbol"].eql? opts[:symbol]}.first&.with_indifferent_access
    position ||= positions.select{|p| p["symbol"].eql? symbol}.first&.with_indifferent_access
    if position
      avg = position[:avg_entry_price].to_f
      sell_qty = position[:qty].to_i - open_sell_orders.inject(0) {|sum, o| sum + o["qty"].to_i}
      sell_limit = (avg + (opts[:spread]/100.0)).round(2)
      sell_call(strike_price: opts[:strike_price], type: :limit, limit: sell_limit, qty: sell_qty) if sell_qty > 0
    end
  end

  def self.stradle_rsi options={}
    opts = options.with_indifferent_access
    data = fetch_bars opts
    signals = calculate_signals(data, {indicator: "Rsi"})
    call_positions = positions.select{|p| p["symbol"].include? "0C00"}
    put_positions = positions.select{|p| p["symbol"].include? "0P00"}
    if signals.first >= 56
      pq = put_positions.inject(0) {|s, p| s += p["qty"].to_i}
      call_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_call(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + 0.2)
      end
      if pq.eql? 0
        buy_put opts
      elsif pq > 0 and pq < (opts[:qty] * 2) and signals.first >= 65 and !put_positions.select{|p| p["symbol"].eql? opts[:put_symbol]}.first.present?
        buy_put opts
      elsif pq > 0 and pq < (opts[:qty] * 3) and signals.first >= 74 and !put_positions.select{|p| p["symbol"].eql? opts[:put_symbol]}.first.present?
        buy_put opts
      end
    elsif signals.first <= 43
      cq = call_positions.inject(0) { |s, p| s += p["qty"].to_i }
      put_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_put(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + 0.2)
      end
      if cq.eql? 0
        buy_call opts
      elsif cq > 0 and cq < (opts[:qty] * 2) and signals.first <= 34 and !call_positions.select{|p| p["symbol"].eql? opts[:call_symbol]}.first.present?
        buy_call opts
      elsif cq > 0 and cq < (opts[:qty] * 3) and signals.first <= 25 and !call_positions.select{|p| p["symbol"].eql? opts[:call_symbol]}.first.present?
        buy_call opts
      end
    end
  end

  def self.stradle_sr options={}
    opts = options.with_indifferent_access
    data = fetch_bars opts
    signals = calculate_signals(data, {indicator: "Sr"})
    call_positions = positions.select{|p| p["symbol"].include? "0C00"}
    put_positions = positions.select{|p| p["symbol"].include? "0P00"}
    if signals.first >= 60
      cq = call_positions.inject(0) {|s, p| s += p["qty"].to_i}
      call_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_call(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + 0.4)
      end if signals.first >= 88
      buy_call opts if cq.eql? 0 and signals.first <=70
    elsif signals.first <= 60
      pq = put_positions.inject(0) { |s, p| s += p["qty"].to_i }
      put_positions.each do |position|
        avg = position["avg_entry_price"].to_f
        quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
        current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
        sell_put(symbol: position["symbol"], qty: position["qty"]) if current_price > (avg + 0.4)
      end if signals.first <= 30
      buy_put opts if pq.eql? 0 and signals.first >= 50
    end
  end

  def self.stradle_multi_day options={}
    opts = options.with_indifferent_access
    data = fetch_bars opts
    signals = calculate_signals(data, {indicator: "Sr"})
    call_positions = positions.select{|p| p["symbol"].include? "0C00"}
    put_positions = positions.select{|p| p["symbol"].include? "0P00"}
    cq = call_positions.inject(0) {|s, p| s += p["qty"].to_i}
    pq = put_positions.inject(0) { |s, p| s += p["qty"].to_i }
    buy_call opts if cq.eql? 0 and signals[0] - signals[3] >= 7
    buy_put opts if pq.eql? 0 and signals[3] - signals[0] >= 7
    positions.each do |position|
      sell_call(symbol: position["symbol"], qty: position["qty"]) if position["symbol"].include? "0C00" and current_price > (avg + 0.25)
      sell_put(symbol: position["symbol"], qty: position["qty"]) if position["symbol"].include? "0P00" and current_price > (avg + 0.25)
      avg = position["avg_entry_price"].to_f
      if position["symbol"].include? "0C00"
        qty = (opts[:qty]/2).round if cq < (opts[:qty] * 3)
        qty ||= opts[:qty] * 3
      elsif position["symbol"].include? "0P00"
        qty = (opts[:qty]/2).round if pq < (opts[:qty] * 3)
        qty ||= opts[:qty] * 3
      end
      opts[:qty] = qty
      quotes = latest_option_quote_for(position["symbol"]).with_indifferent_access
      current_price = ((quotes[:quotes][position["symbol"]][:ap] + quotes[:quotes][position["symbol"]][:bp])/2).round(2)
      new_avg = ((avg * position["qty"]) + (current_price * qty))/(position["qty"] + qty)
      averaging_percentage = ((avg - new_avg) * 100.0)/ avg if new_avg < avg
      buy_call opts if position["symbol"].include? "0C00" and averaging_percentage and averaging_percentage >= 30 and cq < opts[:qty] * 6
      buy_put opts if position["symbol"].include? "0P00" and averaging_percentage and averaging_percentage >= 20 and pq < opts[:qty] * 6
    end
  end

  def self.intra_day options={}
    opts = options.with_indifferent_access
    opts[:qty] ||= 10
    opts[:diff] ||= 10
    opts[:date] ||= Date.today.beginning_of_month + 1.months
    quotes = latest_quote_for(opts[:ticker]).with_indifferent_access
    call_positions = positions.select{|p| p["symbol"].include? "0C00"}
    put_positions = positions.select{|p| p["symbol"].include? "0P00"}
    opts[:latest_quote] = ((quotes[:quotes][opts[:ticker]][:ap] + quotes[:quotes][opts[:ticker]][:bp])/2).round
    put_offset = (opts[:latest_quote] - opts[:diff]) % 5
    call_offset = (opts[:latest_quote] + opts[:diff]) % 5
    put_strike_price = opts[:latest_quote] - opts[:diff] - put_offset
    call_strike_price = opts[:latest_quote] + opts[:diff] + call_offset
    opts[:put_symbol] = put_positions.first&["symbol"]
    opts[:call_symbol] = call_positions.first&["symbol"]
    opts[:put_symbol] ||= contract_data_for(opts.merge(strike_price: put_strike_price, options_type: :put)).last[:symbol]
    opts[:call_symbol] ||= contract_data_for(opts.merge(strike_price: call_strike_price, options_type: :call)).last[:symbol]
    stradle_multi_day opts
  end

    # def self.init options={}
  #   opts = options.with_indifferent_access
  #   buy_call strike_price: opts[:strike_price]
  #   p = positions.select{|p| p["symbol"].eql? opts[:symbol]}.first
  #   p ||= positions.select{|p| p["symbol"].eql? symbol}.first
  #   avg = p["avg_entry_price"].to_f
  #   limit = (avg + (opts[:spread]/100.0)).round(2)
  #   sell_call(strike_price: opts[:strike_price], type: :limit, limit: limit)
  # end

  # def self.poll_and_process options={}
  #   opts = options.with_indifferent_access
  #   p = positions.select{|p| p["symbol"].eql? opts[:symbol]}.first
  #   return unless p
  #   avg = p["avg_entry_price"].to_f
  #   buy_limit = (avg - (opts[:spread]/100.0)).round(2)
  #   open_sell_orders = orders(query: {status: :all, side: :sell}).select{|o| !o["filled_at"].present?}
  #   open_buy_orders = orders(query: {status: :all, side: :buy}).select{|o| !o["filled_at"].present?}
  #   buy_call(strike_price: opts[:strike_price], type: :limit, limit: buy_limit) if p["qty"].to_i < 20 and open_buy_orders.select{|o| o["limit_price"].to_f.eql? buy_limit}.count.zero?
  #   p = positions.select{|p| p["symbol"].eql? opts[:symbol]}.first
  #   avg = p["avg_entry_price"].to_f
  #   sell_qty = p["qty"].to_i - open_sell_orders.inject(0) {|sum, o| sum + o["qty"].to_i}
  #   sell_limit = (avg + (opts[:spread]/100.0)).round(2)
  #   sell_call(strike_price: opts[:strike_price], type: :limit, limit: sell_limit, qty: sell_qty) if sell_qty > 0
  # end

  def self.connect_and_subscribe(symbol)
    EM.run do
      ws = WebSocket::EventMachine::Client.connect(uri(symbol))

      ws.onopen do
        puts "Connected to WebSocket"
        authenticate(ws)
        subscribe_to_bars(ws, symbol)
      end

      ws.onmessage do |msg, type|
        data = JSON.parse(msg)
        if data['T'] == "b"
          handle_bar_data(data)
        end
      end

      ws.onerror do |error|
        puts "Error: #{error}"
      end

      ws.onclose do |code, reason|
        puts "Closed connection: #{reason}"
        EM.stop
      end
    end
  end

  def self.authenticate(ws)
    auth_msg = {
      action: "auth",
      key_id: APCA_API_KEY,
      secret_key: APCA_API_SECRET_KEY
    }
    ws.send(auth_msg.to_json)
  end

  def self.subscribe_to_bars(ws, symbol)
    sub_msg = {
      action: "subscribe",
      bars: [symbol]
    }
    ws.send(sub_msg.to_json)
  end

  def self.handle_bar_data(data)
    puts "Bar Data: #{data}"
    # Process bar data here
  end
end