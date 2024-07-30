class IntradayWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'orders'

  def self.fire options={}
    perform_async options
  end

  def self.fire_in time, options={}
    perform_in time, options
  end

  def perform options={}
    AlpacaService.intra_day options
    IntradayWorker.fire_in 29.seconds, options
  end
end