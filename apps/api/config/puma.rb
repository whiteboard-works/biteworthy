threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "development")
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] == "true"
