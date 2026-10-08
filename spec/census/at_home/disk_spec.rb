# frozen_string_literal: true

RSpec.describe Census::AtHome::Disk do
  it "reports free bytes on a real filesystem" do
    free = described_class.free_bytes(Dir.pwd)
    expect(free).to be_an(Integer)
    expect(free).to be_positive
  end

  it "is nil for a path that is not there" do
    expect(described_class.free_bytes("/nonexistent/path")).to be_nil
  end
end
