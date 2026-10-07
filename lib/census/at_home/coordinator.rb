# frozen_string_literal: true

require "digest"
require "fileutils"
require "tempfile"

module Census
  module AtHome
    # The trust boundary. Workers may be strangers, buggy, or hostile; every
    # result they return is re-derived here with plain geometry before it is
    # accepted. A tiling certificate must cover its lattice exactly once; a
    # corona witness must cover the frontier without overlaps. Anything that
    # fails is rejected and its unit returns to the queue — no reputation
    # system required, because nothing is ever believed on a worker's word.
    class Coordinator
      # A SHA-256, lowercase hex. Anything else did not come from hashing a file.
      DIGEST = /\A[0-9a-f]{64}\z/

      # The default ceiling on a proof we will take by upload. GitHub refuses
      # blobs past 100 MB, so anything larger could not join the archive even
      # if checked. A campaign whose proofs are bound for S3 rather than git
      # raises it. A record saying "too large to check this way" is worth more
      # than silence about it.
      MAX_PROOF_BYTES = 100 * 1024 * 1024

      DEFAULT_PROOFS = "proofs"

      # Which claimed proofs get asked for. `on_request` leaves it to a human
      # (script/at_home/audit) and lets a parent settle on claimed digests.
      # `every` asks for each proof the moment it is claimed and lets a parent
      # settle only on checked ones, which is what a proof-backed theorem
      # needs.
      PROOF_POLICIES = %i[on_request every].freeze

      attr_reader :max_proof_bytes, :proof_policy

      def initialize(store:, lease_seconds: 900, proofs: DEFAULT_PROOFS, proof_policy: :on_request,
                     max_proof_bytes: MAX_PROOF_BYTES, check_timeout: SAT::DratTrim::DEFAULT_TIMEOUT)
        raise ArgumentError, "proof_policy must be one of #{PROOF_POLICIES.inspect}" unless PROOF_POLICIES.include?(proof_policy)

        @store = store
        @lease_seconds = lease_seconds
        @proofs = proofs
        @proof_policy = proof_policy
        @max_proof_bytes = max_proof_bytes
        @check_timeout = check_timeout
      end

      def every_proof? = proof_policy == :every

      def register(handle:, display_name: nil, contact: nil) = store.register_client(handle:, display_name:, contact:)

      def lease(client_id:)
        unit = store.lease_unit(client_id:, seconds: lease_seconds)
        return nil unless unit

        { id: unit[:id], kind: unit[:kind], shape_id: unit[:shape_id] }.merge(presented(unit[:payload]))
      end

      # The formula behind a cube unit, by unit id.
      #
      # A volunteer is not on this coordinator's filesystem, so a cube unit
      # cannot name its formula by path and expect anyone to open it. Only
      # paths this coordinator recorded when it made the unit are served.
      def formula_path(unit_id)
        unit = store.unit(unit_id)
        return nil unless unit && unit[:kind] == "cube"

        path = unit[:payload][:cnf_path]
        path if path && File.exist?(path)
      end

      # verdicts: "tiler" (certificate attached), "exhausted" (budgets spent),
      # "unsat"/"sat" (cube units), "error".
      def submit(unit_id:, client_id:, verdict:, payload: {}, seconds: nil)
        unit = store.unit(unit_id)
        return { accepted: false, note: "no such unit" } unless unit

        accepted, note = verify(unit:, verdict:, payload:)

        # A digest is only worth recording once its result was believed. The
        # proof is claimed, not held: the bytes are still on the worker's disk.
        proof = accepted ? payload[:proof] : nil
        store.record_result(unit_id:, client_id:, verdict:, payload:, seconds:, verified: accepted, note:,
                            proof:, proof_state: proof ? "claimed" : "none")
        store.want_proof(proof[:sha256]) if proof && every_proof?
        store.credit_client(id: client_id, accepted:)

        unless accepted
          store.release_unit(unit_id)
          return { accepted:, note: }
        end

        return { accepted:, note: }.merge(split(unit)) if splittable?(unit:, verdict:)

        store.close_unit(id: unit_id, status: verdict == "exhausted" ? "exhausted" : "done")
        rolled = roll_up(unit) if verdict == "unsat"

        { accepted:, note: rolled ? "#{note}, and it settled #{rolled}" : note }
      end

      def status = store.status.merge(proofs: store.proof_states)

      # Ask for a claimed proof. Nothing arrives unasked, so an upload nobody
      # requested has nowhere to land.
      def want_proof(sha256) = store.want_proof(sha256).positive?

      def wanted_proofs(client_id:) = store.wanted_proofs(client_id:)

      # Close every split of a shape whose children are all refuted, deepest
      # first, until nothing changes. The roll-up does this as results land,
      # so this is for repair: a roll-up that was missed (the coordinator was
      # down, or an earlier version counted wrong) never fires again on its
      # own. Returns how many it closed.
      def settle(shape_id:)
        closed = 0
        loop do
          progressed = store.split_units(shape_id:).count do |id|
            next false unless store.children_all_refuted?(id, proofs_required: every_proof?)

            store.close_unit(id:, status: "done")
            true
          end
          closed += progressed
          break if progressed.zero?
        end
        closed
      end

      # Take delivery of a proof and check it.
      #
      # Four things hold before the checker is worth running: we asked for this
      # proof, it fits, the bytes hash to what was promised, and the formula it
      # claims to refute is one we rebuild ourselves. That last one is the whole
      # point. Checking a proof against a formula the sender chose proves only
      # that they can write two matching files.
      def deliver_proof(sha256:, bytes:)
        wanted = store.wanted_proofs_named(sha256)
        return refusal("no proof was asked for with that digest") if wanted.empty?

        if bytes.bytesize > max_proof_bytes
          wanted.each { store.record_proof(id: it[:id], state: "too_large", note: "#{bytes.bytesize} bytes exceeds the upload cap") }
          return refusal("proof exceeds the #{max_proof_bytes} byte cap")
        end

        digest = Digest::SHA256.hexdigest(bytes)
        return refusal("bytes hash to #{digest[0, 12]}, not the promised #{sha256[0, 12]}") unless digest == sha256

        # One upload, checked once per unit that claimed it: the same bytes
        # can refute several cubes, and each cube is a different formula.
        path = stored_at(sha256, bytes)
        outcomes = wanted.map { check_delivered(wanted: it, path:) }
        return outcomes.first if outcomes.size == 1

        verified = outcomes.count { it[:accepted] }
        { accepted: verified == outcomes.size,
          note: "proof checked against #{outcomes.size} units: #{verified} verified, #{outcomes.size - verified} not" }
      end

      private

      attr_reader :check_timeout, :lease_seconds, :proofs, :store

      def refusal(note) = { accepted: false, note: }

      # Only a cube can be halved. A shape reporting `exhausted` spent its box
      # and torus budgets, which is an answer about the shape rather than a
      # question that got too big.
      def splittable?(unit:, verdict:) = verdict == "exhausted" && unit[:kind] == "cube"

      # A cube nobody could finish becomes two, branching on a variable it does
      # not already fix.
      #
      # Soundness rests on one thing: v and not-v together cover every
      # assignment, so no solution can hide in the gap between the halves. If
      # both children come back refuted, the parent is refuted. A child too
      # hard in turn is split the same way, which is the escalation the n=9
      # campaign performed by hand.
      def split(unit)
        variable = branching_variable(unit[:payload])
        return { note: "nothing left to branch on" } unless variable

        cube = unit[:payload].fetch(:cube, [])
        children = [variable, -variable].filter_map do |literal|
          store.add_unit(kind: "cube", shape_id: unit[:shape_id], parent_id: unit[:id],
                         payload: unit[:payload].merge(cube: cube + [literal]))
        end

        store.close_unit(id: unit[:id], status: "split")

        { note: "too hard, split on variable #{variable} into #{children.size}", children: }
      end

      # The lowest variable the cube does not already fix. Deterministic and
      # sound. A lookahead solver would choose a variable that splits the work
      # more evenly, which is an optimization, not a correctness matter.
      def branching_variable(payload)
        fixed = payload.fetch(:cube, []).map(&:abs)

        (1..variable_count(payload[:cnf_path])).find { !fixed.include?(it) }
      end

      def variable_count(cnf_path)
        return 0 unless cnf_path && File.exist?(cnf_path)

        File.open(cnf_path) { Integer(it.readline.split[2]) }
      end

      # A parent is settled once every child it was split into is refuted, and
      # settling one may settle its own parent, so this walks up. No result row
      # is written for a parent: its evidence is its children's, and inventing
      # a result would mean inventing a worker who produced it.
      def roll_up(unit)
        parent_id = unit[:parent_id]
        return nil unless parent_id && store.children_all_refuted?(parent_id, proofs_required: every_proof?)

        store.close_unit(id: parent_id, status: "done")
        parent = store.unit(parent_id)

        roll_up(parent) || "unit #{parent_id}"
      end

      # A local filesystem path means nothing to a volunteer and tells them
      # about a machine they have no business knowing. They fetch the formula
      # by unit id instead, and check it against the digest they were given.
      def presented(payload) = payload.except(:cnf_path)

      # Rebuild the exact formula the proof claims to refute, from the base CNF
      # and the cube this coordinator handed out, then let drat-trim decide.
      def check_delivered(wanted:, path:)
        unit = wanted[:unit]

        result = Tempfile.create(["census-cube", ".cnf"]) do |formula|
          SAT::CubeFile.stream_augmented(cnf_path: unit.fetch(:cnf_path), cube: unit.fetch(:cube, []), io: formula)
          formula.flush
          SAT::DratTrim.check(cnf_path: formula.path, proof_path: path, timeout: check_timeout)
        end

        state = result.verified? ? "verified" : "refuted"
        store.record_proof(id: wanted[:id], state:, path:, note: result.summary)
        note = "proof #{state}: #{result.summary}"

        # A checked proof may be the last one a parent was waiting on.
        rolled = roll_up(store.unit(wanted[:unit_id])) if result.verified? && every_proof?

        { accepted: result.verified?, note: rolled ? "#{note}, and it settled #{rolled}" : note }
      rescue SAT::DratTrim::Missing, KeyError => error
        # Could not check is not the same answer as did not hold.
        store.record_proof(id: wanted[:id], state: "stored", path:, note: "unchecked: #{error.message}")
        { accepted: false, note: "proof stored but unchecked: #{error.message}" }
      end

      def stored_at(sha256, bytes)
        FileUtils.mkdir_p(proofs)
        path = File.join(proofs, "#{sha256}.drat")
        File.binwrite(path, bytes) unless File.exist?(path)

        path
      end

      def verify(unit:, verdict:, payload:)
        if (reason = SubmissionGuard.new(payload:, verdict:).rejection)
          return [false, "rejected before verification: #{reason}"]
        end

        case verdict
        when "tiler" then verify_certificate(unit:, payload:)
        when "exhausted" then [true, "budgets accepted as reported"]
        when "sat" then verify_cube_model(unit:, payload:)
        when "unsat" then verify_cube_refutation(payload:)
        else [false, "unknown verdict #{verdict}"]
        end
      end

      def verify_certificate(unit:, payload:)
        certificate = payload[:certificate]
        return [false, "no certificate"] unless certificate

        shape = Polycube.new(cells: unit[:payload].fetch(:cells))
        valid = Verifier.new(certificate:, shape:).valid?
        [valid, valid ? "certificate verified by geometry" : "certificate failed geometric verification"]
      rescue StandardError => error
        [false, "verification error: #{error.message}"]
      end

      # A refutation is accepted only if it names a proof. That is weaker than
      # checking one, and much stronger than the bare word "unsat": the digest
      # binds the volunteer to a specific artifact they must still be able to
      # produce, which is what makes a later audit possible at all. Checking
      # the proof itself is the next pass, and needs a checker.
      def verify_cube_refutation(payload:)
        proof = payload[:proof]
        return [false, "refutation names no proof"] unless proof.is_a?(Hash)

        digest = proof[:sha256]
        return [false, "proof digest missing or malformed"] unless digest.is_a?(String) && digest.match?(DIGEST)
        return [false, "proof is empty, which refutes nothing"] unless proof[:bytes].is_a?(Integer) && proof[:bytes].positive?

        [true, "refutation accepted, proof #{digest[0, 12]} unchecked"]
      end

      def verify_cube_model(unit:, payload:)
        literals = payload[:model]
        return [false, "no model"] unless literals.is_a?(Array) && literals.any?

        cube = unit[:payload].fetch(:cube, [])
        satisfies_cube = cube.all? { literals.include?(it) }
        [satisfies_cube, satisfies_cube ? "model agrees with its cube" : "model contradicts its own cube"]
      end
    end
  end
end
