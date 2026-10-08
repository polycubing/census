# frozen_string_literal: true

# The scripts have no specs of their own, and one Ruby trap has bitten them
# three times: a keyword-argument shorthand at the end of a line
# (`foo.bar name:`) parses, and quietly swallows the next line as the value.
# This reads every Ruby script and refuses the pattern outside a hash literal.
RSpec.describe "scripts" do
  scripts = Dir.glob(File.expand_path("../script/**/*", __dir__))
                .select { File.file?(it) && File.readlines(it).first.to_s.include?("ruby") }

  # The line with its interpolations, string literals, and comments removed,
  # so a `"done: #{x}"` is not mistaken for a trailing keyword.
  def bare(line)
    line.gsub(/#\{[^}]*\}/, "").gsub(/"[^"]*"|'[^']*'/, "").sub(/#.*/, "").rstrip
  end

  scripts.each do |path|
    it "#{path.sub(%r{.*/script/}, 'script/')} parses, and ends no line with a bare keyword shorthand" do
      expect(system("ruby", "-c", path, out: File::NULL, err: File::NULL)).to be(true)

      lines = File.readlines(path)
      offenders = lines.each_index.select do |index|
        line = bare(lines[index])
        next false unless line.match?(/[a-z_]+:\z/)
        next false if line.match?(/\A\s*[a-z_]+:\z/) && lines[index + 1].to_s.match?(/\A\s*[})]/) # last key of a hash literal

        true
      end
      expect(offenders.map { it + 1 }).to eq([])
    end
  end
end
