# Medici

An automated options-trading system built on Ruby on Rails and Sidekiq. Medici
pulls market data from the [Alpaca](https://alpaca.markets/) brokerage API,
computes technical indicators, and autonomously executes multi-leg options
strategies during market hours.

> **Note:** This is a personal research project for experimenting with
> algorithmic options strategies. It is not production trading infrastructure
> and is shared to illustrate the engineering — API integration, background
> workers, and real-time market-data processing — not as financial advice.

## What it does

- **Market data ingestion** — fetches historical and latest price bars for
  underlyings and options contracts from Alpaca's REST API, plus a WebSocket
  client for streaming live bars.
- **Signal generation** — computes technical indicators (RSI and a
  support/resistance signal) from price bars via the `technical-analysis` gem.
- **Strategy execution** — several pluggable strategies decide when to open,
  average into, or close call/put positions:
  - `stradle_rsi` / `stradle_sr` — RSI- and support/resistance-driven straddles.
  - `surf_stradle` — momentum-based straddle with cost-averaging and scaled exits.
  - `intra_day` — selects strike prices around the current quote, sizes orders
    against available buying power, and drives `surf_stradle`.
- **Order management** — builds and submits market/limit options orders,
  tracks open orders and positions, and computes dynamic position sizing from
  portfolio equity and purchasing power.
- **Continuous loop** — `IntradayWorker` is a Sidekiq worker that re-enqueues
  itself every 90 seconds, keeping the strategy running throughout the trading
  session.

## Architecture

```
Sidekiq worker (IntradayWorker)        # self-rescheduling strategy loop
        │
        ▼
AlpacaService                          # all market-data + trading logic
   ├── REST (HTTParty) ──► Alpaca API  # bars, quotes, contracts, orders, positions
   ├── WebSocket client  ─► Alpaca     # streaming bars
   └── technical-analysis gem          # RSI / support-resistance signals
```

- **`app/services/alpaca_service.rb`** — the core: Alpaca API client, signal
  calculation, and all strategy/order logic.
- **`app/workers/intraday_worker.rb`** — Sidekiq worker that runs the intraday
  loop on a 90-second cadence.
- Sidekiq web UI is mounted at `/sidekiq`; a health check is exposed at `/up`.

## Tech stack

- **Ruby** 3.3.3, **Rails** 7.1
- **Sidekiq** 7.3 (Redis-backed background jobs)
- **HTTParty** for REST, **websocket-eventmachine-client** for streaming,
  **msgpack** for Alpaca's binary feed
- **alpaca-trade-api** and **technical-analysis** gems
- **PostgreSQL** (`pg`) / SQLite for local
- **Docker** (see `Dockerfile`)

## Configuration

The Alpaca integration is driven entirely by environment variables (loaded via
`dotenv` in development). Create a `.env` with at least:

```bash
BASE_URL=                          # Alpaca API base URL (paper or live)
APCA_API_KEY=                      # Alpaca API key id
APCA_API_SECRET_KEY=               # Alpaca API secret
ORDERS_URL=
POSITIONS_URL=
PORTFOLIO_ENDPOINT=
OPTIONS_CONTRACTS_URL=
LATEST_QUOTE_ENDPOINT=
LATEST_OPTIONS_QUOTE_ENDPOINT=
HISTORICAL_BARS_BASE_URL=
HISTORICAL_BARS_OPTIONS_URL=
```

> Use Alpaca's **paper-trading** environment when experimenting — these
> strategies place real orders against whatever account the keys belong to.

## Running locally

```bash
bundle install
bin/rails db:prepare

# start Redis + Sidekiq (separate terminals)
redis-server
bundle exec sidekiq

# kick off the intraday loop, e.g. from a Rails console:
bin/rails console
> IntradayWorker.fire(ticker: "SPY", diff: 12)
```

## Disclaimer

This software trades financial instruments and can lose money. It is provided
as-is for educational and research purposes, with no warranty and no guarantee
of profitability. Nothing here is financial advice.
