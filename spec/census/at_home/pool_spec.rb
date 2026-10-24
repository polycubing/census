# frozen_string_literal: true

RSpec.describe Census::AtHome::Pool, :home do
  let(:pool) { described_class.new(url: Census::AtHome::Store::DEFAULT_URL, size: 1) }

  after { pool.close }

  # Postgres restarted under the hub on 2026-10-17, and the hub spent a week
  # answering every request with the dead connection it still held.
  it "drops a connection the server has closed and retries the work on a fresh one" do
    pool.with { |connection| connection.finish }

    expect(pool.with { |connection| connection.exec("SELECT 1").first["?column?"] }).to eq("1")
  end

  it "returns a connection after a failure that is not the connection's fault" do
    expect { pool.with { |connection| connection.exec("SELECT nonsense FROM nowhere") } }.to raise_error(PG::UndefinedTable)

    expect(pool.with { |connection| connection.exec("SELECT 2").first["?column?"] }).to eq("2")
  end
end
