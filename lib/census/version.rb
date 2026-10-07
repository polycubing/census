# frozen_string_literal: true

module Census
  # Not a gem release. This string lands in every record's credits.solved_by,
  # so it says which pipeline stamped a claim. Bump it when a stamp changes
  # shape or meaning. Everything through 2026-10-06 says 0.1.0, which was
  # never bumped, so for those records git history is the real version.
  VERSION = "0.2.0"
end
