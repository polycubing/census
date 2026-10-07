-- polycubing@home coordinator server schema.
--
-- Two ideas carry the whole design:
--   1. A unit is a question with a self-certifying answer. Positive answers
--      (a tiling, a corona) carry witnesses the coordinator re-verifies with
--      plain geometry; negative answers carry proofs or exhausted budgets.
--      Nothing is ever decided by trusting a worker.
--   2. Units nest. A shape too hard for one worker becomes cubes; a cube too
--      hard becomes sub-cubes (parent_id). The same protocol serves both.

-- Two identities on purpose. `handle` is the scheduling key: opaque,
-- permanent, never displayed — leases and results hang off it forever.
-- `display_name` is what appears in credits.solved_by: mutable, moderated,
-- scrubbable years later without touching a single result.
CREATE TABLE IF NOT EXISTS clients (
  id            BIGSERIAL PRIMARY KEY,
  handle        TEXT NOT NULL UNIQUE,
  display_name  TEXT,
  display_state TEXT NOT NULL DEFAULT 'pending'
                     CHECK (display_state IN ('pending', 'approved', 'rejected')),
  contact       TEXT,
  first_seen    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen     TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted      INTEGER NOT NULL DEFAULT 0,
  rejected      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS units (
  id           BIGSERIAL PRIMARY KEY,
  kind         TEXT NOT NULL CHECK (kind IN ('shape', 'cube')),
  shape_id     TEXT NOT NULL,
  parent_id    BIGINT REFERENCES units (id),
  payload      JSONB NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'leased', 'done', 'exhausted', 'split')),
  lease_client BIGINT REFERENCES clients (id),
  lease_until  TIMESTAMPTZ,
  attempts     INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- NULLS NOT DISTINCT, because a shape unit has no parent, and two NULLs
  -- would otherwise count as different and let the same shape be queued
  -- twice. Re-seeding relies on a duplicate being refused.
  CONSTRAINT units_identity UNIQUE NULLS NOT DISTINCT (kind, shape_id, parent_id, payload)
);

-- A database made before the constraint was named carries the old one, under
-- which NULL parents were distinct. Replace it. Both statements are safe to
-- repeat.
ALTER TABLE units DROP CONSTRAINT IF EXISTS units_kind_shape_id_parent_id_payload_key;
ALTER TABLE units DROP CONSTRAINT IF EXISTS units_identity;
ALTER TABLE units ADD CONSTRAINT units_identity UNIQUE NULLS NOT DISTINCT (kind, shape_id, parent_id, payload);

CREATE INDEX IF NOT EXISTS units_leasable ON units (status, lease_until);
CREATE INDEX IF NOT EXISTS units_shape ON units (shape_id);

CREATE TABLE IF NOT EXISTS results (
  id            BIGSERIAL PRIMARY KEY,
  unit_id       BIGINT NOT NULL REFERENCES units (id),
  client_id     BIGINT NOT NULL REFERENCES clients (id),
  verdict       TEXT NOT NULL
                     CHECK (verdict IN ('tiler', 'exhausted', 'unsat', 'sat', 'error')),
  payload       JSONB NOT NULL DEFAULT '{}'::jsonb,
  seconds       NUMERIC,
  verified      BOOLEAN,
  verifier_note TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS results_unit ON results (unit_id);

-- The life of a refutation's proof.
--
-- A worker reporting `unsat` sends the digest and size of a DRAT proof it keeps
-- on its own disk, never the bytes. These columns follow that promise: what was
-- claimed, whether the coordinator asked for it, where it landed, and what the
-- checker said. Columns rather than payload keys, so the proofs still owed can
-- be found without reading every result's jsonb.
--
--   none       not a refutation, or none claimed
--   claimed    a digest was reported and the bytes are on the worker's disk
--   wanted     the coordinator has asked for the bytes
--   stored     the bytes arrived and hashed to what was promised
--   verified   drat-trim checked the proof against the formula it refutes
--   refuted    the checker ran and the proof did not hold
--   too_large  over the upload cap, so unverifiable this way (pending S3)
ALTER TABLE results ADD COLUMN IF NOT EXISTS proof_sha256 TEXT;
ALTER TABLE results ADD COLUMN IF NOT EXISTS proof_bytes  BIGINT;
ALTER TABLE results ADD COLUMN IF NOT EXISTS proof_path   TEXT;
ALTER TABLE results ADD COLUMN IF NOT EXISTS checker_note TEXT;
ALTER TABLE results ADD COLUMN IF NOT EXISTS proof_state  TEXT NOT NULL DEFAULT 'none';

-- A CHECK takes no IF NOT EXISTS, so it is replaced instead of added.
ALTER TABLE results DROP CONSTRAINT IF EXISTS results_proof_state;
ALTER TABLE results ADD CONSTRAINT results_proof_state CHECK (
  proof_state IN ('none', 'claimed', 'wanted', 'stored', 'verified', 'refuted', 'too_large')
);

CREATE INDEX IF NOT EXISTS results_proof ON results (proof_state);
