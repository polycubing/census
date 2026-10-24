# frozen_string_literal: true

# Puma configuration for the polycubing@home coordinator.
#
# Single process, many threads: the work is I/O-bound (Postgres, and short
# bursts of geometry verification), and one process keeps the Rack::Attack
# counters and connection pool in one place. Terminate TLS and apply crude
# flood protection at a reverse proxy in front of this.

threads_count = Integer(ENV.fetch("AT_HOME_THREADS", "16"))
threads threads_count, threads_count

# Localhost unless told otherwise: every client so far has been on the hub's
# own machine or came through an ssh tunnel, and the colo's open port drew
# internet scanners within a day. AT_HOME_BIND=0.0.0.0 when volunteers exist,
# behind the reverse proxy above.
bind "tcp://#{ENV.fetch('AT_HOME_BIND', '127.0.0.1')}:#{Integer(ENV.fetch('PORT', '9292'))}"
environment ENV.fetch("RACK_ENV", "production")

log_requests false
