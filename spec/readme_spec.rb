# frozen_string_literal: true

RSpec.describe "README.md" do
  it "carries the rotation table exactly as script/rotations prints it" do
    table = IO.popen([RbConfig.ruby, File.expand_path("../script/rotations", __dir__)], &:read)
    expect(File.read(File.expand_path("../README.md", __dir__))).to include(table)
  end
end
