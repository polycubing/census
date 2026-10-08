# frozen_string_literal: true

RSpec.describe Census::AtHome::Coordinator, :home do
  let(:store) { Census::AtHome::Store.new }
  let(:coordinator) { described_class.new(store:) }
  let(:straight) { Census::Polycube.new(cells: [[0, 0, 0], [0, 0, 1], [0, 0, 2]]) }

  before do
    store.load_schema(File.expand_path("../../../db/at_home.sql", __dir__))
    store.reset
  end

  after { store.close }

  def seed_shape(shape, id: "3/1")
    store.add_unit(kind: "shape", shape_id: id, payload: { cells: shape.cells, budgets: {} })
  end

  it "hands a leased unit everything a worker needs to solve it" do
    seed_shape(straight)
    worker = coordinator.register(handle: "spec")
    unit = coordinator.lease(client_id: worker[:id])
    expect(unit).to include(kind: "shape", shape_id: "3/1", cells: straight.cells)
  end

  it "leases each unit to only one worker at a time" do
    seed_shape(straight)
    first = coordinator.register(handle: "first")
    second = coordinator.register(handle: "second")
    coordinator.lease(client_id: first[:id])
    expect(coordinator.lease(client_id: second[:id])).to be_nil
  end

  it "accepts a valid certificate and closes the unit" do
    seed_shape(straight)
    worker = coordinator.register(handle: "spec")
    unit = coordinator.lease(client_id: worker[:id])
    certificate = Census::TorusSearch.new(shape: straight).certificate

    answer = coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "tiler",
                                payload: { certificate: })
    expect(answer[:accepted]).to be(true)
    expect(coordinator.status[:units]).to eq({ "done" => 1 })
  end

  it "rejects a forged certificate and returns the unit to the queue" do
    seed_shape(straight)
    worker = coordinator.register(handle: "liar")
    unit = coordinator.lease(client_id: worker[:id])
    forged = { "type" => "torus", "lattice" => [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
               "placements" => [{ "rotation" => 0, "offset" => [0, 0, 0] }] }

    answer = coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "tiler",
                                payload: { certificate: forged })
    expect(answer[:accepted]).to be(false)
    expect(coordinator.lease(client_id: worker[:id])).not_to be_nil
  end

  it "counts a worker's accepted and rejected submissions" do
    seed_shape(straight)
    worker = coordinator.register(handle: "mixed")
    unit = coordinator.lease(client_id: worker[:id])
    coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "tiler", payload: { certificate: nil })
    unit = coordinator.lease(client_id: worker[:id])
    coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "tiler",
                       payload: { certificate: Census::TorusSearch.new(shape: straight).certificate })

    expect(coordinator.status[:clients].first).to include(handle: "mixed", accepted: 1, rejected: 1)
  end

  it "credits an unapproved display name as the opaque handle" do
    worker = coordinator.register(handle: "client-abc123", display_name: "Booger Butt")
    expect(store.credit_string(worker[:id])).to eq("client-abc123")
  end

  it "credits an approved display name once a human approves it" do
    worker = coordinator.register(handle: "client-abc123", display_name: "Ada Lovelace")
    store.approve_display_name(worker[:id])
    expect(store.credit_string(worker[:id])).to eq("Ada Lovelace")
  end

  it "rejects a cube model that contradicts its own cube" do
    store.add_unit(kind: "cube", shape_id: "9/2127", payload: { cnf_path: "/nonexistent.cnf", cube: [3, -4] })
    worker = coordinator.register(handle: "spec")
    unit = coordinator.lease(client_id: worker[:id])

    answer = coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "sat", payload: { model: [1, 2, 4] })
    expect(answer[:accepted]).to be(false)
  end

  # A refutation that names no artifact cannot be audited, ever. It used to be
  # taken on the volunteer's word.
  describe "cube refutations" do
    def refute(payload)
      store.add_unit(kind: "cube", shape_id: "9/2127", payload: { cnf_path: "/nonexistent.cnf", cube: [3] })
      worker = coordinator.register(handle: "spec")
      unit = coordinator.lease(client_id: worker[:id])

      coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "unsat", payload:)
    end

    let(:digest) { "a" * 64 }

    it "rejects one that names no proof" do
      expect(refute(cube: [3])).to include(accepted: false, note: /names no proof/)
    end

    it "rejects a digest that did not come from hashing a file" do
      expect(refute(proof: { sha256: "not-a-digest", bytes: 8 })).to include(accepted: false, note: /malformed/)
    end

    # kissat writes nothing when it never derives a clause. An absence of bytes
    # is an absence of evidence.
    it "rejects an empty proof" do
      expect(refute(proof: { sha256: digest, bytes: 0 })).to include(accepted: false, note: /refutes nothing/)
    end

    it "accepts one that names a proof, and says plainly that it is unchecked" do
      expect(refute(proof: { sha256: digest, bytes: 8 })).to include(accepted: true, note: /unchecked/)
    end

    it "returns the unit to the queue when the refutation is refused" do
      refute(cube: [3])

      expect(coordinator.status[:units]).to eq({ "pending" => 1 })
    end
  end

  # A cube nobody can finish becomes two. The whole escalation the n=9
  # campaign ran by hand, expressed as data.
  describe "splitting a cube that was too hard" do
    let(:contradiction) { "spec/fixtures/proof/contradiction.cnf" }

    # Solve a cube the way a worker would, and return what the coordinator said.
    def report(verdict, payload, unit_id: nil, handle: "spec")
      worker = coordinator.register(handle:)
      unit_id ||= coordinator.lease(client_id: worker[:id])[:id]

      coordinator.submit(unit_id:, client_id: worker[:id], verdict:, payload:)
    end

    def seed_cube(cube: [], parent_id: nil)
      store.add_unit(kind: "cube", shape_id: "9/2127", parent_id:,
                     payload: { cnf_path: contradiction, cube: })
    end

    it "halves an exhausted cube on a variable it does not already fix" do
      seed_cube(cube: [1])

      answer = report("exhausted", { cube: [1] })

      expect(answer[:note]).to match(/split on variable 2 into 2/)
      expect(coordinator.status[:units]).to eq({ "split" => 1, "pending" => 2 })
    end

    # v and not-v cover every assignment, which is the only reason a split
    # cannot lose an answer.
    it "gives the two halves opposite literals for that variable" do
      seed_cube(cube: [1])
      report("exhausted", { cube: [1] })

      cubes = [2, 3].map { store.unit(it)[:payload][:cube] }

      expect(cubes).to contain_exactly([1, 2], [1, -2])
    end

    it "hands the children the same formula, so nothing is re-derived" do
      seed_cube
      report("exhausted", { cube: [] })

      expect(store.unit(2)[:payload][:cnf_path]).to eq(contradiction)
    end

    it "leaves a shape's exhausted budgets alone, since that is an answer" do
      seed_shape(straight)

      report("exhausted", { budgets: {} })

      expect(coordinator.status[:units]).to eq({ "exhausted" => 1 })
    end

    it "stops splitting when the cube already fixes every variable" do
      seed_cube(cube: [1, 2])

      expect(report("exhausted", { cube: [1, 2] })[:note]).to match(/nothing left to branch on/)
    end

    describe "settling the parent" do
      let(:proof) { { sha256: "a" * 64, bytes: 8 } }

      before { seed_cube and report("exhausted", { cube: [] }) }

      it "leaves the parent split while one half is unanswered" do
        report("unsat", { cube: [1], proof: }, unit_id: 2)

        expect(store.unit(1)[:status]).to eq("split")
      end

      it "settles the parent once both halves are refuted" do
        report("unsat", { cube: [1], proof: }, unit_id: 2)
        answer = report("unsat", { cube: [-1], proof: }, unit_id: 3)

        expect(store.unit(1)[:status]).to eq("done")
        expect(answer[:note]).to match(/settled unit 1/)
      end

      # A half coming back satisfiable settles the parent the other way. It
      # must never be mistaken for progress toward a refutation.
      it "does not settle the parent when a half is satisfiable" do
        report("unsat", { cube: [1], proof: }, unit_id: 2)
        report("sat", { model: [-1] }, unit_id: 3)

        expect(store.unit(1)[:status]).to eq("split")
      end

      # A split half has no result of its own. Its evidence is its children's,
      # and it must still count for its parent once they close it.
      it "settles the grandparent when a split half's own halves are refuted" do
        report("exhausted", { cube: [-1] }, unit_id: 3)
        report("unsat", { cube: [1], proof: }, unit_id: 2)
        report("unsat", { cube: [-1, 2], proof: }, unit_id: 4)
        answer = report("unsat", { cube: [-1, -2], proof: }, unit_id: 5)

        expect(store.unit(3)[:status]).to eq("done")
        expect(store.unit(1)[:status]).to eq("done")
        expect(answer[:note]).to match(/settled unit 1/)
      end

      it "settles on demand what a missed roll-up left open" do
        report("exhausted", { cube: [-1] }, unit_id: 3)
        [[2, [1]], [4, [-1, 2]], [5, [-1, -2]]].each { |id, cube| report("unsat", { cube:, proof: }, unit_id: id) }
        store.close_unit(id: 1, status: "split")
        store.close_unit(id: 3, status: "split")

        expect(coordinator.settle(shape_id: "9/2127")).to eq(2)
        expect(store.unit(1)[:status]).to eq("done")
      end
    end
  end

  # A volunteer is not on this machine, so a formula cannot be handed over as
  # a path and expected to open.
  describe "serving the formula behind a cube unit" do
    let(:contradiction) { "spec/fixtures/proof/contradiction.cnf" }

    def seed_cube(cnf_path: contradiction)
      store.add_unit(kind: "cube", shape_id: "8/1309", payload: { cnf_path:, cnf_sha256: "abc", cube: [1] })
    end

    it "never tells a client where the formula lives on the coordinator" do
      seed_cube
      worker = coordinator.register(handle: "spec")

      unit = coordinator.lease(client_id: worker[:id])

      expect(unit).to include(cube: [1], cnf_sha256: "abc")
      expect(unit).not_to have_key(:cnf_path)
    end

    it "serves the formula by unit id" do
      id = seed_cube

      expect(coordinator.formula_path(id)).to eq(contradiction)
    end

    it "serves nothing for a unit whose formula is gone" do
      id = seed_cube(cnf_path: "/nonexistent.cnf")

      expect(coordinator.formula_path(id)).to be_nil
    end

    it "serves nothing for a shape unit, which has no formula" do
      seed_shape(straight)

      expect(coordinator.formula_path(1)).to be_nil
    end
  end

  # The two-identity split only means something if a human can bridge it.
  describe "moderating a display name" do
    def volunteer = coordinator.register(handle: "client-laptop-3f9a", display_name: "Ada Lovelace")

    it "credits by the opaque handle until a human approves the name" do
      volunteer

      expect(store.credit_string(volunteer[:id])).to eq("client-laptop-3f9a")
    end

    it "lists a name that is waiting" do
      volunteer

      expect(store.pending_display_names).to contain_exactly(hash_including(display_name: "Ada Lovelace",
                                                                            handle: "client-laptop-3f9a"))
    end

    it "credits by the display name once approved" do
      volunteer
      store.moderate_display_name(handle: "client-laptop-3f9a", state: "approved")

      expect(store.credit_string(volunteer[:id])).to eq("Ada Lovelace")
    end

    # Reversible on purpose: the archive is public and permanent, so a name
    # can be withdrawn later without touching a single result.
    it "falls back to the handle again when a name is rejected" do
      volunteer
      store.moderate_display_name(handle: "client-laptop-3f9a", state: "approved")
      store.moderate_display_name(handle: "client-laptop-3f9a", state: "rejected")

      expect(store.credit_string(volunteer[:id])).to eq("client-laptop-3f9a")
      expect(store.pending_display_names).to be_empty
    end

    it "reports when no client has that handle, rather than silently doing nothing" do
      expect(store.moderate_display_name(handle: "nobody", state: "approved")).to be_zero
    end
  end

  # The digest is a promise. This is the coordinator calling it in.
  describe "taking delivery of a proof" do
    let(:contradiction) { "spec/fixtures/proof/contradiction.cnf" }
    let(:proof)         { "spec/fixtures/proof/contradiction.drat" }
    let(:bytes)         { File.binread(proof) }
    let(:digest)        { Digest::SHA256.hexdigest(bytes) }

    around { |example| Dir.mktmpdir { |dir| @proofs = dir and example.run } }

    let(:coordinator) { described_class.new(store:, proofs: @proofs) }

    # Claim a refutation the way a worker would, then ask for its proof.
    def claim_and_want(cnf_path: contradiction, cube: [])
      store.add_unit(kind: "cube", shape_id: "8/1309", payload: { cnf_path:, cube: })
      worker = coordinator.register(handle: "spec")
      unit = coordinator.lease(client_id: worker[:id])
      coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "unsat",
                         payload: { cube:, proof: { sha256: digest, bytes: bytes.bytesize } })
      coordinator.want_proof(digest)
    end

    it "checks a delivered proof against the formula it rebuilds itself", :checker do
      claim_and_want

      answer = coordinator.deliver_proof(sha256: digest, bytes:)

      expect(answer[:accepted]).to be(true)
      expect(answer[:note]).to match(/verified/)
      expect(coordinator.status[:proofs]).to eq({ "verified" => 1 })
    end

    it "keeps the bytes under the digest they hash to" do
      claim_and_want
      coordinator.deliver_proof(sha256: digest, bytes:)

      expect(File.binread(File.join(@proofs, "#{digest}.drat"))).to eq(bytes)
    end

    # Content addressing is worth nothing if the bytes are not checked
    # against the name they arrived under.
    it "refuses bytes that do not hash to the digest they claim" do
      claim_and_want

      answer = coordinator.deliver_proof(sha256: digest, bytes: "#{bytes}tampered")

      expect(answer).to include(accepted: false, note: /hash to/)
      expect(coordinator.status[:proofs]).to eq({ "wanted" => 1 })
    end

    it "refuses a proof nobody asked for" do
      answer = coordinator.deliver_proof(sha256: digest, bytes:)

      expect(answer).to include(accepted: false, note: /nobody|no proof was asked/)
    end

    # The threat this exists to catch: a volunteer claims a refutation of a
    # formula that is in fact satisfiable, and sends a real proof of some other
    # formula. It checks out on its own terms and against ours it does not.
    # A cube only adds unit clauses, so it can never turn its base formula
    # satisfiable — the lie has to be about which formula was solved.
    it "refutes a real proof aimed at a formula the coordinator did not hand out", :checker do
      claim_and_want(cnf_path: "spec/fixtures/proof/satisfiable.cnf")

      answer = coordinator.deliver_proof(sha256: digest, bytes:)

      expect(answer).to include(accepted: false, note: /refuted/)
      expect(coordinator.status[:proofs]).to eq({ "refuted" => 1 })
    end

    it "asks only for proofs that were claimed" do
      expect(coordinator.want_proof(digest)).to be(false)
    end

    # Unit propagation alone refutes thousands of easy cubes, and kissat
    # writes the identical one-line proof for each. One upload must serve
    # them all, each checked against its own cube's formula.
    describe "a proof several units share" do
      def claim_twice
        [[], [1]].each { store.add_unit(kind: "cube", shape_id: "8/1309", payload: { cnf_path: contradiction, cube: it }) }
        worker = coordinator.register(handle: "spec")
        2.times do
          unit = coordinator.lease(client_id: worker[:id])
          coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "unsat",
                             payload: { cube: unit[:cube], proof: { sha256: digest, bytes: bytes.bytesize } })
        end
        coordinator.want_proof(digest)
        worker
      end

      it "is asked for from the client once" do
        worker = claim_twice
        expect(coordinator.wanted_proofs(client_id: worker[:id])).to eq([digest])
      end

      it "is checked against every unit that claimed it on one delivery", :checker do
        claim_twice

        answer = coordinator.deliver_proof(sha256: digest, bytes:)

        expect(answer).to include(accepted: true, note: /2 units: 2 verified/)
        expect(coordinator.status[:proofs]).to eq({ "verified" => 2 })
      end
    end
  end

  # A proof-backed theorem needs every proof, checked, before anything rests
  # on it. This policy makes the coordinator ask without being told to, and
  # withholds the parent until the checker has spoken.
  describe "wanting every proof" do
    let(:contradiction) { "spec/fixtures/proof/contradiction.cnf" }
    let(:bytes)         { File.binread("spec/fixtures/proof/contradiction.drat") }
    let(:digest)        { Digest::SHA256.hexdigest(bytes) }

    around { |example| Dir.mktmpdir { |dir| @proofs = dir and example.run } }

    let(:coordinator) { described_class.new(store:, proofs: @proofs, proof_policy: :every) }

    # A split cube with one child, the way seed-cubes lays a cover down.
    def seed_split
      parent = store.add_unit(kind: "cube", shape_id: "8/1309", payload: { cnf_path: contradiction, cube: [] })
      store.close_unit(id: parent, status: "split")
      store.add_unit(kind: "cube", shape_id: "8/1309", parent_id: parent, payload: { cnf_path: contradiction, cube: [1] })
      parent
    end

    def refute_the_child
      worker = coordinator.register(handle: "spec")
      unit = coordinator.lease(client_id: worker[:id])
      coordinator.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "unsat",
                         payload: { cube: [1], proof: { sha256: digest, bytes: bytes.bytesize } })
      worker
    end

    it "asks for a refutation's proof the moment it is claimed" do
      seed_split
      worker = refute_the_child

      expect(coordinator.wanted_proofs(client_id: worker[:id])).to eq([digest])
      expect(coordinator.status[:proofs]).to eq({ "wanted" => 1 })
    end

    it "does not settle a parent on a proof nobody has checked" do
      parent = seed_split
      refute_the_child

      expect(store.unit(parent)[:status]).to eq("split")
    end

    it "settles the parent once the proof is delivered and checked", :checker do
      parent = seed_split
      refute_the_child

      answer = coordinator.deliver_proof(sha256: digest, bytes:)

      expect(answer[:note]).to match(/verified.*settled unit #{parent}/)
      expect(store.unit(parent)[:status]).to eq("done")
    end

    it "takes a proof over the default cap when the campaign allows it" do
      big = described_class.new(store:, proofs: @proofs, proof_policy: :every, max_proof_bytes: 4)
      seed_split
      refute_the_child

      expect(big.deliver_proof(sha256: digest, bytes:)).to include(accepted: false, note: /4 byte cap/)
    end

    it "rejects a policy it does not know" do
      expect { described_class.new(store:, proof_policy: :sometimes) }.to raise_error(ArgumentError)
    end

    # A campaign's proofs can be hundreds of megabytes, and a check inside the
    # request holds a server thread for minutes while every client times out
    # behind it. Deferred, delivery is a write and the checker is its own
    # process.
    it "stores a delivered proof and leaves the checking to the checker when told to", :checker do
      deferred = described_class.new(store:, proofs: @proofs, proof_policy: :every, check_on_delivery: false)
      parent = seed_split
      refute_the_child

      expect(deferred.deliver_proof(sha256: digest, bytes:)).to include(accepted: true, note: /queued/)
      expect(deferred.status[:proofs]).to eq({ "stored" => 1 })
      expect(store.unit(parent)[:status]).to eq("split")

      expect(deferred.recheck(states: ["stored"], jobs: 2)).to eq({ "verified" => 1 })
      expect(store.unit(parent)[:status]).to eq("done")
    end

    # A server restart mid-write once left a prefix of a proof under the
    # digest's name, and every later delivery trusted it. Now a file is kept
    # only if it is the whole proof, and a held file the wrong size is asked
    # for again rather than checked.
    it "replaces a truncated proof left under the digest's name", :checker do
      seed_split
      refute_the_child
      File.binwrite(File.join(@proofs, "#{digest}.drat"), bytes[0, 3])

      expect(coordinator.deliver_proof(sha256: digest, bytes:)).to include(accepted: true)
      expect(File.binread(File.join(@proofs, "#{digest}.drat"))).to eq(bytes)
    end

    it "asks again for a held proof whose size disagrees with the claim" do
      deferred = described_class.new(store:, proofs: @proofs, proof_policy: :every, check_on_delivery: false)
      seed_split
      refute_the_child
      deferred.deliver_proof(sha256: digest, bytes:)
      File.binwrite(File.join(@proofs, "#{digest}.drat"), bytes[0, 3])

      expect(deferred.recheck(states: ["stored"])).to eq({ "asked again" => 1 })
      expect(deferred.status[:proofs]).to eq({ "wanted" => 1 })
      expect(File).not_to exist(File.join(@proofs, "#{digest}.drat"))
    end

    # The checker as a service: refills from the database while its workers
    # run, so a proof stored mid-pass is not stuck behind the pass.
    it "checks continuously, smallest first, until told to stop", :checker do
      deferred = described_class.new(store:, proofs: @proofs, proof_policy: :every, check_on_delivery: false)
      parent = seed_split
      refute_the_child
      deferred.deliver_proof(sha256: digest, bytes:)
      lines = []
      rounds = 0

      deferred.check_continuously(jobs: 2, interval: 0, report: ->(line) { lines << line }, stop: -> { (rounds += 1) > 1 })

      expect(lines).to eq(["verified  #{digest[0, 12]}  #{bytes.bytesize} bytes  unit 2"])
      expect(deferred.status[:proofs]).to eq({ "verified" => 1 })
      expect(store.unit(parent)[:status]).to eq("done")
    end

    # The bathtub. The faucet closes when held-plus-expected proof bytes pass
    # the high mark and reopens below the low mark, and closes regardless
    # when the disk is nearly full. This is the control whose absence filled
    # a disk twice on the first campaign day.
    describe "the faucet" do
      def seed_two_leaves
        parent = store.add_unit(kind: "cube", shape_id: "8/1309", payload: { cnf_path: contradiction, cube: [] })
        store.close_unit(id: parent, status: "split")
        [[1], [-1]].each { store.add_unit(kind: "cube", shape_id: "8/1309", parent_id: parent, payload: { cnf_path: contradiction, cube: it }) }
      end

      def claim(hub, worker, cube)
        unit = hub.lease(client_id: worker[:id])
        hub.submit(unit_id: unit[:id], client_id: worker[:id], verdict: "unsat", payload: { cube:, proof: { sha256: digest, bytes: bytes.bytesize } })
      end

      it "closes above the high mark and reopens below the low mark", :checker do
        hub = described_class.new(store:, proofs: @proofs, proof_policy: :every, check_on_delivery: false,
                                  basin_high_bytes: bytes.bytesize + 1, basin_low_bytes: 1)
        seed_two_leaves
        worker = hub.register(handle: "spec")

        claim(hub, worker, [1])
        claim(hub, worker, [-1])
        expect(hub.basin).to include(faucet: "open", bytes: 0)

        hub.deliver_proof(sha256: digest, bytes:)
        expect(hub.basin).to include(faucet: "closed", bytes: 2 * bytes.bytesize)
        expect(hub.lease(client_id: worker[:id])).to be_nil

        hub.recheck(states: ["stored"])
        expect(hub.basin).to include(faucet: "open", bytes: 0)
      end

      it "closes when the disk under the proofs is below the floor, whatever the basin holds" do
        free = 1_000
        hub = described_class.new(store:, proofs: @proofs, disk_floor_bytes: 5_000, free_disk: -> { free })
        seed_two_leaves
        worker = hub.register(handle: "spec")

        expect(hub.lease(client_id: worker[:id])).to be_nil
        expect(hub.basin[:reasons].first).to match(/free disk 1000 bytes under the 5000 floor/)

        free = 10_000
        expect(hub.lease(client_id: worker[:id])).not_to be_nil
      end

      it "counts only what is on the hub's disk, not proofs still on volunteers'" do
        hub = described_class.new(store:, proofs: @proofs, proof_policy: :every, check_on_delivery: false, basin_high_bytes: 1)
        seed_two_leaves
        worker = hub.register(handle: "spec")

        claim(hub, worker, [1])
        expect(hub.basin).to include(faucet: "open", bytes: 0)
        hub.deliver_proof(sha256: digest, bytes:)
        expect(hub.basin).to include(faucet: "closed", bytes: bytes.bytesize)
      end

      # A proof nobody can deliver must not hold a cube, or the faucet, forever.
      it "reopens a cube whose proof was wanted too long and never came" do
        hub = described_class.new(store:, proofs: @proofs, proof_policy: :every)
        seed_two_leaves
        worker = hub.register(handle: "spec")
        claim(hub, worker, [1])
        expect(hub.status[:proofs]).to eq({ "wanted" => 1 })

        expect(hub.reopen_undelivered(older_than: 3600)).to eq([])
        expect(hub.reopen_undelivered(older_than: 0)).to eq([2])
        expect(hub.status[:units]).to include("pending" => 2)
        expect(hub.status[:proofs]).to eq({ "none" => 1 })
        expect(store.children_all_refuted?(1, proofs_required: true)).to be(false)
      end

      it "leases freely with no marks set" do
        seed_two_leaves
        worker = coordinator.register(handle: "spec")
        expect(coordinator.lease(client_id: worker[:id])).not_to be_nil
        expect(coordinator.basin).to include(faucet: "open", high: nil, floor: nil)
      end
    end

    # A proof that arrived while the checker was missing is kept, not lost.
    # Once the checker exists, it gets its turn, and the parent settles.
    it "rechecks held proofs from disk once the checker is available", :checker do
      parent = seed_split
      refute_the_child
      checker = ENV.fetch("CENSUS_DRAT_TRIM", nil)
      ENV["CENSUS_DRAT_TRIM"] = "/nonexistent/drat-trim"
      coordinator.deliver_proof(sha256: digest, bytes:)
      ENV["CENSUS_DRAT_TRIM"] = checker
      expect(coordinator.status[:proofs]).to eq({ "stored" => 1 })

      expect(coordinator.recheck).to eq({ "verified" => 1 })
      expect(coordinator.status[:proofs]).to eq({ "verified" => 1 })
      expect(store.unit(parent)[:status]).to eq("done")
    end
  end
end
