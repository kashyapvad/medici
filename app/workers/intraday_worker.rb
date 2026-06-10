class IntradayWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'orders', retry: false

  INTERVAL = 90.seconds

  def self.fire options={}
    perform_async options
  end

  def self.fire_in time, options={}
    perform_in time, options
  end

  def perform options={}
    AlpacaService.intra_day options
  ensure
    IntradayWorker.fire_in INTERVAL, options
  end
end