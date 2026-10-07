# frozen_string_literal: true

RSpec.describe Census::Artifact do
  let(:root) { File.expand_path("../fixtures/artifacts", __dir__) }

  def artifact(relative) = described_class.new(path: File.join(root, relative), root:)

  describe "#id" do
    it "is the shape the artifact belongs to" do
      expect(artifact("9/8219/cnf/corona2.drat").id).to eq("9/8219")
    end
  end

  describe "#key" do
    it "is the public object key, compressed" do
      expect(artifact("9/8219/cnf/corona2.drat").key).to eq("public/9/8219/corona2.drat.xz")
    end
  end

  describe "#description" do
    it "names a DRAT proof as the refutation of that corona depth" do
      expect(artifact("9/8219/cnf/corona2.drat").description).to eq("DRAT refutation of corona-2 of 9/8219")
    end

    it "names a CNF as the formula for that corona depth" do
      expect(artifact("9/2127/cnf/corona3.cnf").description).to eq("formula for corona-3 of 9/2127")
    end
  end

  describe "#sha256 and #bytes" do
    it "hash and measure the bytes on disk" do
      proof = artifact("9/8219/cnf/corona2.drat")
      expect(proof.bytes).to eq(File.size(proof.path))
      expect(proof.sha256).to eq(Digest::SHA256.file(proof.path).hexdigest)
    end
  end

  describe "#relative_path" do
    it "is the path a record would use, from the data root" do
      expect(artifact("9/2127/cnf/corona3.cnf").relative_path).to eq("9/2127/cnf/corona3.cnf")
    end
  end
end
