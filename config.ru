# frozen_string_literal: true

# Rack entry point for the polycubing@home server.
#
#   bundle exec puma -C config/puma.rb
#   # or:
#   script/at_home/server
#
# The connection pool is sized to the server's thread count
# so that a saturated server never waits on connections.
# Both the connection pool and the web server use the AT_HOME_THREADS.
# To change the thread count and connection pool size:
#     set AT_HOME_THREADS ENV variable and restart the server.
#
# A campaign that must end in a proof-backed theorem sets
#     AT_HOME_PROOF_POLICY=every
# and, since its proofs go to S3 rather than git, raises the upload cap and
# the checker's time limit with AT_HOME_MAX_PROOF_BYTES and
# AT_HOME_CHECK_TIMEOUT (seconds).

require_relative "lib/census"

threads = Integer(ENV.fetch("AT_HOME_THREADS", "16"))
store = Census::AtHome::Store.new(pool_size: threads)
proofs = ENV.fetch("AT_HOME_PROOFS", Census::AtHome::Coordinator::DEFAULT_PROOFS)
proof_policy = ENV.fetch("AT_HOME_PROOF_POLICY", "on_request").to_sym
max_proof_bytes = Integer(ENV.fetch("AT_HOME_MAX_PROOF_BYTES", Census::AtHome::Coordinator::MAX_PROOF_BYTES))
check_timeout = Integer(ENV.fetch("AT_HOME_CHECK_TIMEOUT", Census::SAT::DratTrim::DEFAULT_TIMEOUT))
# AT_HOME_DEFER_CHECKS=1 stores delivered proofs for script/at_home/check-proofs
# to verify in its own process, instead of checking inside the request.
check_on_delivery = ENV.fetch("AT_HOME_DEFER_CHECKS", "0") != "1"
# The basin: the faucet closes when held-plus-expected proof bytes pass the
# high mark or free disk under the proof directory drops below the floor, and
# reopens below the low mark. Gigabytes. Unset means no limit.
gigabytes = ->(name) { ENV[name] && (Float(ENV[name]) * 1_000_000_000).to_i }
basin_high_bytes = gigabytes.call("AT_HOME_BASIN_HIGH_GB")
basin_low_bytes = gigabytes.call("AT_HOME_BASIN_LOW_GB")
disk_floor_bytes = gigabytes.call("AT_HOME_DISK_FLOOR_GB")
Census::AtHome::Server.coordinator = Census::AtHome::Coordinator.new(store:, proofs:, proof_policy:, max_proof_bytes:,
                                                                     check_timeout:, check_on_delivery:,
                                                                     basin_high_bytes:, basin_low_bytes:, disk_floor_bytes:)

run Census::AtHome::Server
