import Config

# Keep metadata lookups deterministic and offline during the test suite.
config :queue_party, :youtube_request_options, plug: QueueParty.YouTubeStub
config :queue_party, :youtube_api_key, "test-api-key"
config :queue_party, :youtube_playlist_request_options, plug: QueueParty.YouTubePlaylistStub

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :queue_party, QueuePartyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "B9XqhMN00eqkc+PSrzBg718hPbW4ppG2rZWyaGz8f/gezULpN6XcWxIb6PwCQ84J",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
