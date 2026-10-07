# frozen_string_literal: true

require "pg"
require "json"

module Census
  module AtHome
    # Postgres-backed state for the coordinator: clients, units, results.
    # Scheduling state only — the census's truth stays in data/ and git, so
    # losing this database costs in-flight leases and nothing else.
    #
    # Every query is parameterized; no value from a worker is ever
    # interpolated into SQL.
    class Store
      DEFAULT_URL = ENV.fetch("POLYCUBE_AT_HOME_URL", "postgres:///polycube_at_home")

      def initialize(url: DEFAULT_URL, pool_size: 8)
        @pool = Pool.new(url:, size: pool_size)
      end

      def load_schema(path)
        synchronize do |connection|
          connection.exec("SET client_min_messages TO WARNING")
          connection.exec(File.read(path))
        end
      end

      def reset = synchronize { |connection| connection.exec("TRUNCATE results, units, clients RESTART IDENTITY CASCADE") }

      def close = pool.close

      # handle is the permanent scheduling key; display_name is the credit
      # string and starts unapproved — nothing reaches data/ unmoderated.
      def register_client(handle:, display_name: nil, contact: nil)
        row = synchronize do |connection|
          connection.exec_params(<<~SQL, [handle, display_name, contact]).first
            INSERT INTO clients (handle, display_name, contact) VALUES ($1, $2, $3)
            ON CONFLICT (handle) DO UPDATE
              SET last_seen = now(),
                  contact = COALESCE(EXCLUDED.contact, clients.contact),
                  display_name = COALESCE(EXCLUDED.display_name, clients.display_name)
            RETURNING id, handle, display_name, display_state
          SQL
        end
        { id: Integer(row["id"]), handle: row["handle"], display_name: row["display_name"],
          display_state: row["display_state"] }
      end

      # What credits.solved_by may say for this worker: the approved display
      # name, or the opaque handle until a human approves one.
      def credit_string(client_id)
        row = synchronize do |connection|
          connection.exec_params("SELECT handle, display_name, display_state FROM clients WHERE id = $1", [client_id]).first
        end
        return nil unless row

        row["display_state"] == "approved" && row["display_name"] ? row["display_name"] : row["handle"]
      end

      # Names waiting on a human. Until one is approved the volunteer is
      # credited by their opaque handle, so this queue is the only thing
      # standing between a contributor and a permanent citation in data/.
      def pending_display_names
        rows = synchronize do |connection|
          connection.exec(<<~SQL)
            SELECT handle, display_name, contact, accepted, rejected, first_seen
              FROM clients
             WHERE display_state = 'pending' AND display_name IS NOT NULL
             ORDER BY first_seen
          SQL
        end

        rows.map do
          { accepted: Integer(it["accepted"]), contact: it["contact"], display_name: it["display_name"],
            first_seen: it["first_seen"], handle: it["handle"], rejected: Integer(it["rejected"]) }
        end
      end

      # Returns the number of clients changed, so a typo in a handle is caught
      # by the caller rather than reported as a silent success.
      def moderate_display_name(handle:, state:)
        synchronize do |connection|
          connection.exec_params(<<~SQL, [handle, state]).cmd_tuples
            UPDATE clients SET display_state = $2 WHERE handle = $1
          SQL
        end
      end

      def approve_display_name(client_id, approved: true)
        synchronize do |connection|
          connection.exec_params("UPDATE clients SET display_state = $2 WHERE id = $1",
                                 [client_id, approved ? "approved" : "rejected"])
        end
      end

      def add_unit(kind:, shape_id:, payload:, parent_id: nil)
        row = synchronize do |connection|
          connection.exec_params(<<~SQL, [kind, shape_id, parent_id, JSON.generate(payload)]).first
            INSERT INTO units (kind, shape_id, parent_id, payload) VALUES ($1, $2, $3, $4)
            ON CONFLICT DO NOTHING
            RETURNING id
          SQL
        end
        row && Integer(row["id"])
      end

      # Atomically hand out the oldest available unit: pending, or leased with
      # an expired lease (a worker that vanished mid-flight costs one lease).
      def lease_unit(client_id:, seconds:)
        row = synchronize do |connection|
          connection.exec_params(<<~SQL, [client_id, seconds]).first
            UPDATE units SET status = 'leased', lease_client = $1,
                             lease_until = now() + ($2 || ' seconds')::interval,
                             attempts = attempts + 1
            WHERE id = (
              SELECT id FROM units
              WHERE status = 'pending' OR (status = 'leased' AND lease_until < now())
              ORDER BY id
              FOR UPDATE SKIP LOCKED
              LIMIT 1
            )
            RETURNING id, kind, shape_id, parent_id, payload, status
          SQL
        end
        row && unit_from(row)
      end

      def unit(id)
        row = synchronize do |connection|
          connection.exec_params("SELECT id, kind, shape_id, parent_id, payload, status FROM units WHERE id = $1", [id]).first
        end
        row && unit_from(row)
      end

      def record_result(unit_id:, client_id:, verdict:, payload:, seconds:, verified:, note: nil,
                        proof: nil, proof_state: "none")
        values = [unit_id, client_id, verdict, JSON.generate(payload), seconds, verified, note,
                  proof && proof[:sha256], proof && proof[:bytes], proof_state]

        synchronize do |connection|
          connection.exec_params(<<~SQL, values)
            INSERT INTO results (unit_id, client_id, verdict, payload, seconds, verified, verifier_note,
                                 proof_sha256, proof_bytes, proof_state)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
          SQL
        end
      end

      # The proofs the coordinator has decided it wants but has not received.
      # A worker asks on its next visit whether anything is owed.
      def wanted_proofs(client_id:)
        rows = synchronize do |connection|
          connection.exec_params(<<~SQL, [client_id])
            SELECT proof_sha256 FROM results
             WHERE client_id = $1 AND proof_state = 'wanted'
             ORDER BY created_at
          SQL
        end

        rows.map { it["proof_sha256"] }
      end

      # Refutations whose proof is named but not held. These are the claims
      # standing on a volunteer's word alone, so this is the list worth
      # auditing from.
      def claimed_proofs
        rows = synchronize do |connection|
          connection.exec(<<~SQL)
            SELECT results.proof_sha256, results.proof_bytes, results.created_at,
                   units.shape_id, clients.handle
              FROM results
                   JOIN units   ON units.id   = results.unit_id
                   JOIN clients ON clients.id = results.client_id
             WHERE results.proof_state = 'claimed'
             ORDER BY results.created_at
          SQL
        end

        rows.map do
          { bytes: Integer(it["proof_bytes"]), claimed_at: it["created_at"], handle: it["handle"],
            sha256: it["proof_sha256"], shape_id: it["shape_id"] }
        end
      end

      def want_proof(sha256)
        synchronize do |connection|
          connection.exec_params(<<~SQL, [sha256]).cmd_tuples
            UPDATE results SET proof_state = 'wanted'
             WHERE proof_sha256 = $1 AND proof_state = 'claimed'
          SQL
        end
      end

      # Which unit a promised proof belongs to, so the formula it must refute
      # can be rebuilt. Only proofs actually asked for are answerable, so an
      # upload nobody requested has nowhere to land.
      def wanted_proof(sha256)
        row = synchronize do |connection|
          connection.exec_params(<<~SQL, [sha256]).first
            SELECT results.id, results.proof_bytes, results.unit_id, units.payload AS unit_payload
              FROM results JOIN units ON units.id = results.unit_id
             WHERE results.proof_sha256 = $1 AND results.proof_state = 'wanted'
             LIMIT 1
          SQL
        end
        return nil unless row

        { id: Integer(row["id"]),
          bytes: row["proof_bytes"] && Integer(row["proof_bytes"]),
          unit_id: Integer(row["unit_id"]),
          unit: JSON.parse(row["unit_payload"], symbolize_names: true) }
      end

      def record_proof(id:, state:, path: nil, note: nil)
        synchronize do |connection|
          connection.exec_params(<<~SQL, [id, state, path, note])
            UPDATE results SET proof_state = $2, proof_path = $3, checker_note = $4 WHERE id = $1
          SQL
        end
      end

      def proof_states
        synchronize do |connection|
          connection.exec("SELECT proof_state, count(*) FROM results GROUP BY proof_state")
                    .to_h { [it["proof_state"], Integer(it["count"])] }
        end
      end

      def close_unit(id:, status:)
        synchronize do |connection|
          connection.exec_params("UPDATE units SET status = $2, lease_client = NULL, lease_until = NULL WHERE id = $1", [id, status])
        end
      end

      def release_unit(id)
        synchronize do |connection|
          connection.exec_params("UPDATE units SET status = 'pending', lease_client = NULL, lease_until = NULL WHERE id = $1", [id])
        end
      end

      # Whether every child of a split is refuted.
      #
      # A child counts only with a verified `unsat` against it, and when proofs
      # are required, only once its proof has been checked. A child that was
      # itself split has no result of its own, its evidence being its
      # children's, so it counts once the roll-up closed it. A child that came
      # back `sat` does not merely fail to refute its parent, it settles the
      # parent the other way, so "all refuted" must never be inferred from
      # "all finished".
      def children_all_refuted?(parent_id, proofs_required: false)
        row = synchronize do |connection|
          connection.exec_params(<<~SQL, [parent_id, proofs_required]).first
            SELECT count(*) AS children,
                   count(*) FILTER (
                     WHERE EXISTS (
                             SELECT 1 FROM results
                              WHERE results.unit_id = units.id
                                AND results.verdict = 'unsat' AND results.verified IS TRUE
                                AND ($2 IS FALSE OR results.proof_state = 'verified')
                           )
                        OR (units.status = 'done' AND EXISTS (
                             SELECT 1 FROM units AS grandchildren WHERE grandchildren.parent_id = units.id
                           ))
                   ) AS refuted
              FROM units
             WHERE units.parent_id = $1
          SQL
        end

        children = Integer(row["children"])

        children.positive? && children == Integer(row["refuted"])
      end

      def shape_unit(shape_id)
        row = synchronize do |connection|
          connection.exec_params("SELECT id, status FROM units WHERE kind = 'shape' AND shape_id = $1 ORDER BY id LIMIT 1", [shape_id]).first
        end
        row && { id: Integer(row["id"]), status: row["status"] }
      end

      # Units of a shape still marked split, deepest first, for a settle pass.
      def split_units(shape_id:)
        rows = synchronize do |connection|
          connection.exec_params("SELECT id FROM units WHERE shape_id = $1 AND status = 'split' ORDER BY id DESC", [shape_id])
        end
        rows.map { Integer(it["id"]) }
      end

      # Every cube of a shape that was not split further, each with its
      # verified refutation when it has one. A cube tried more than once has
      # several results, and the one whose proof was checked is the one that
      # counts.
      def cube_leaves(shape_id:)
        rows = synchronize do |connection|
          connection.exec_params(<<~SQL, [shape_id])
            SELECT units.id, units.status, units.payload,
                   results.proof_sha256, results.proof_bytes, results.proof_state, results.proof_path, results.seconds
              FROM units
                   LEFT JOIN results ON results.unit_id = units.id
                                    AND results.verdict = 'unsat' AND results.verified IS TRUE
             WHERE units.kind = 'cube' AND units.shape_id = $1
               AND NOT EXISTS (SELECT 1 FROM units AS children WHERE children.parent_id = units.id)
             ORDER BY units.id, (results.proof_state = 'verified') DESC NULLS LAST
          SQL
        end

        rows.map do |row|
          payload = JSON.parse(row["payload"], symbolize_names: true)
          { id: Integer(row["id"]), status: row["status"], cube: payload[:cube], cnf_sha256: payload[:cnf_sha256],
            proof_sha256: row["proof_sha256"], proof_bytes: row["proof_bytes"] && Integer(row["proof_bytes"]),
            proof_state: row["proof_state"], proof_path: row["proof_path"],
            seconds: row["seconds"] && Float(row["seconds"]) }
        end.uniq { it[:id] }
      end

      def credit_client(id:, accepted:)
        synchronize do |connection|
          connection.exec_params(<<~SQL, [id, accepted])
            UPDATE clients
               SET accepted = accepted + CASE WHEN $2 THEN 1 ELSE 0 END,
                   rejected = rejected + CASE WHEN $2 THEN 0 ELSE 1 END,
                   last_seen = now()
             WHERE id = $1
          SQL
        end
      end

      # Verified shape results with their credit strings resolved — the
      # archiver's view. Unapproved display names fall back to the handle,
      # so nothing unmoderated can reach data/.
      def accepted_shape_results
        rows = synchronize do |connection|
          connection.exec(<<~SQL)
            SELECT DISTINCT ON (units.shape_id)
                   units.shape_id,
                   units.payload AS unit_payload,
                   results.payload AS result_payload,
                   CASE WHEN clients.display_state = 'approved' AND clients.display_name IS NOT NULL
                        THEN clients.display_name ELSE clients.handle END AS credit
              FROM results
                   JOIN units   ON units.id   = results.unit_id
                   JOIN clients ON clients.id = results.client_id
             WHERE results.verified IS TRUE
               AND results.verdict = 'tiler'
               AND units.kind = 'shape'
             ORDER BY units.shape_id, results.created_at
          SQL
        end
        rows.map do |row|
          unit = JSON.parse(row["unit_payload"], symbolize_names: true)
          result = JSON.parse(row["result_payload"], symbolize_names: true)
          { shape_id: row["shape_id"], credit: row["credit"], certificate: result[:certificate], budgets: unit[:budgets] }
        end
      end

      def status
        synchronize do |connection|
          units = connection.exec("SELECT status, count(*) FROM units GROUP BY status").to_h { [it["status"], Integer(it["count"])] }
          results = connection.exec("SELECT verdict, count(*) FROM results WHERE verified IS NOT FALSE GROUP BY verdict")
                              .to_h { [it["verdict"], Integer(it["count"])] }
          clients = connection.exec("SELECT handle, display_name, display_state, accepted, rejected FROM clients ORDER BY accepted DESC")
                              .map { { handle: it["handle"], display_name: it["display_name"], display_state: it["display_state"],
                              accepted: Integer(it["accepted"]), rejected: Integer(it["rejected"]) } }
          { units:, results:, clients: }
        end
      end

      private

      attr_reader :pool

      # Each block runs on its own pooled connection.
      def synchronize(&) = pool.with(&)

      def unit_from(row)
        {
          id: Integer(row["id"]),
          kind: row["kind"],
          shape_id: row["shape_id"],
          parent_id: row["parent_id"] && Integer(row["parent_id"]),
          payload: JSON.parse(row["payload"], symbolize_names: true),
          status: row["status"]
        }
      end
    end
  end
end
