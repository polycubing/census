# frozen_string_literal: true

# The @home specs truncate what they touch, so they get their own database —
# running the suite must never disturb a live coordinator's queue.
ENV["POLYCUBE_AT_HOME_URL"] ||= "postgres:///polycube_at_home_test"

require_relative "../lib/census"

# Whether a coordinator database is actually there and usable.
#
# Building a Store proves nothing, because the pool opens connections lazily.
# The old guard did exactly that and so never skipped anything, which turned
# every @home spec into a failure on machines without Postgres.
#
# Loading the schema is the check, rather than a query against it. An empty
# database answers a connection but raises PG::UndefinedTable on the first
# select, so querying would report a brand new database as unreachable. This
# is also idempotent, and exactly what every :home spec does next anyway.
module CoordinatorDatabase
  def self.reachable?
    return @reachable unless @reachable.nil?

    store = Census::AtHome::Store.new
    store.load_schema File.expand_path("../db/at_home.sql", __dir__)
    store.close
    @reachable = true
  rescue StandardError => error
    warn "coordinator database unavailable (#{error.class}): @home specs will skip"
    @reachable = false
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!

  # polycubing@home specs need a live coordinator database; skip them when
  # one isn't configured so the core suite runs anywhere.
  config.before(:each, :home) do
    skip "coordinator database unavailable — run script/at_home/setup" unless CoordinatorDatabase.reachable?
  end

  # Proof checking needs the vendored drat-trim, which has no Homebrew formula
  # and is built by script/setup. Skipping keeps a fresh clone from drowning in
  # failures. CI asserts the binary exists before it runs any spec, so a broken
  # build there is loud rather than quietly skipped into a green run.
  config.before(:each, :checker) do
    skip "drat-trim not built — run script/setup" unless Census::SAT::DratTrim.available?
  end
  config.order = :random
  Kernel.srand config.seed
end
