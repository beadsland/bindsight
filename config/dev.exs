import Config

config :bindsight,
  common_api: :mjpg_streamer,
  cameras: %{
    test: {"http://rfid-access-building.lan:8080/", :mjpg_streamer},
    bind: "http://bricolage.lan:2020/test/stream"
  },
  cowboy_acceptors: 5,
  cluck_errors: true,
  register_shortnames: true

config :logger, :console,
  format: "$time $metadata[$level] $levelpad$message\n",
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]
