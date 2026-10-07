# Polycube Tiling Census — Technical Plan

A machine-verified census of the tiling behavior of all small polycubes: which ones tile 3D space, which provably can't (and their 3D Heesch numbers), and which resist classification. Modeled on Craig Kaplan's 2D census (_Heesch Numbers of Unmarked Polyforms_, [arXiv:2105.09438](https://arxiv.org/abs/2105.09438)), which has no 3D counterpart.

## Goal

For every polycube up to size 9, produce a verdict with a machine-checkable certificate:

- `TILER` — with the strongest certificate found (translation lattice, box, or periodic block)
- `NON_TILER` — with its 3D Heesch number and the frozen maximal corona
- `OPEN` — survived all tests within documented budgets (the interesting shortlist)

Headline unclaimed facts this settles, in order of reachability:

1. Certify the folklore that all polycubes through n=6 tile space (currently rests on hand-found patterns catalogued on [the Poly Pages](http://www.recmath.com/PolyPages/PolyPages/Tiling.htm), not proofs).
2. Find the smallest non-tiling polycube (2D analogue — a heptomino — known for decades; 3D answer undocumented).
3. Tabulate the first 3D Heesch numbers.
4. Identify the smallest anisohedral polycube (tiles, but never tile-transitively).
5. Publish anything that lands in `OPEN` as einstein candidates.

## Scale

| n   | shapes (rotations only, [A000162](https://oeis.org/A000162)) | mirror-identified ([A038119](https://oeis.org/A038119)) | cumulative shapes |
| --- | -----------------------------------------------------------: | ------------------------------------------------------: | ----------------: |
| 1   |                                                            1 |                                                       1 |                 1 |
| 2   |                                                            1 |                                                       1 |                 2 |
| 3   |                                                            2 |                                                       2 |                 4 |
| 4   |                                                            8 |                                                       7 |                12 |
| 5   |                                                           29 |                                                      23 |                41 |
| 6   |                                                          166 |                                                     112 |               207 |
| 7   |                                                        1,023 |                                                     607 |             1,230 |
| 8   |                                                        6,922 |                                                   3,811 |             8,152 |
| 9   |                                                       48,311 |                                                  25,413 |            56,463 |

P tiles iff its mirror tiles (reflect the whole tiling), so compute once per mirror-identified class (753 classes through n=7) and report per shape. First paper target: n ≤ 8 (complete — the square ring theorem, below). Underway: n = 9.

## Why no 3D census existed (literature framing, 2026-08-10 research session)

- Kaplan's 2D method leans on a finite classification: the 93 isohedral tiling types of the plane (Grünbaum–Shephard) can be marched through exhaustively. **In 3D there are infinitely many types of tile-transitive periodic tilings** (Dress–Huson–Molnár), so no march exists, and the 2D fast paths (Keating–Vince 1999 polynomial-time isohedral decision; Langerman–Winslow 2016 quasilinear) do not lift. The certificate-per-shape pipeline is the correct response to a genuine structural obstruction, not to neglect — the paper should say so explicitly. (Partial finiteness returns under stronger transitivity — Dress–Huson–Molnár's 88 face-transitive equivariant types via Delaney–Dress symbols; whether a constraint useful here restores finiteness is an open research question, possibly a paper in itself. Delaney–Dress symbols deserve a literature pass.)
- **The translational periodic tiling conjecture ladder:** d=1 true (Newman); d=2 true (Bhattacharya, Amer. J. Math. 2020; also Greenfeld–Tao), making tiling of Z² decidable; **d=3 OPEN** — no tile of any kind is known to tile space aperiodically by translations alone, nor is that ruled out; high dimensions false (Greenfeld–Tao, Ann. of Math. 2024, via Sudoku-like constraint-system encodings — worth reading for technique). The census's `OPEN` bucket sits exactly on the open rung: the strongest framing available for the shortlist, abstract-worthy.
- **Group-of-motions discipline:** translations-only admits no 2D aperiodic monotile (Bhattacharya); adding rotations+reflections admits the Hat; rotations-without-reflections the Spectre. Rotation is what buys aperiodicity in the plane. Every open/closed claim in the write-up must name its motion group — D2's two columns, carried into the prose.
- **The polycube einstein search space is combinatorial.** The Schmitt–Conway–Danzer tile closes the general rotation-allowed 3D case, but it works by irrational-angle slab rotations — unavailable to a lattice-locked polycube. Any polycube einstein must therefore be aperiodic for a combinatorial reason, not a metric one. Paper-worthy observation.
- **Hilbert 18 caution:** part two is settled (Reinhardt 1928, anisohedral polyhedra that tile periodically) — never frame this project as attacking it. The live descendant is whether isohedral numbers of monotiles are bounded above (Berglund 1993), which is goal #4's neighborhood; Myers's anisohedral enumerations are the 2D baseline.
- Stage-3 completeness was queried and withdrawn (recorded so it isn't re-raised): the torus encoding covers every periodic tiling with period lattice L — any copies per fundamental domain, any orientations — not merely lattice tilings. The only residual gap is a period exceeding the index budget, already under Risks.

## Definitions (decision log)

- **D1 — Shape identity:** polycubes equivalent under the 24 proper rotations. Mirror twins are distinct shapes cross-linked by `mirror_id` (a printed left screw can't become a right screw).
- **D2 — Allowed motions in tilings:** two columns. `tiles_rotations_only` (24 orientations — the physical/printable reading) and `tiles_with_reflections` (48 — i.e., tiling by the pair {P, mirror(P)}). The gap between them (chiral shapes needing their mirror) is itself census content; this distinction is exactly where the 2D Spectre story lived.
- **D3 — Corona (for Heesch numbers):** corona i is a set of non-overlapping copies covering every cell 26-adjacent (face, edge, or vertex) to the configuration through corona i−1. Lift of Kaplan's 2D conventions; run face-only adjacency as a sensitivity check on any record-holders.
- **D4 — Verdicts are about tilings of all of ℝ³**, not slabs or boxes per se (a box certificate implies a space tiling).

## Pipeline

Each shape runs through increasingly expensive stages; stop at the first certificate.

- **Stage 0 — cheap filters.** Enclosed-cavity detection (a cavity smaller than n cells is an instant non-tiling proof; irrelevant at n ≤ 8, matters later). Symmetry group, chirality, bounding box.
- **Stage 1 — translation lattice.** Torus test (Stage 3) restricted to the identity orientation. Catches most small shapes instantly.
- **Stage 2 — box tiling.** Exact cover of an a×b×c box by all placements of all orientations. Try boxes in increasing volume (multiples of n) up to budget. Certificate: placement list. Cross-validate against [BurrTools](https://burrtools.sourceforge.net) on a sample.
- **Stage 3 — periodic tiling (torus SAT).** Tile the quotient ℤ³/L for sublattices L, enumerated by Hermite normal form in increasing index (index a multiple of n). Skew lattices matter: periodic tilings need not have orthogonal periods, and diagonal-only tori would miss them. SAT (Boolean satisfiability — encode constraints as a true/false formula, hand it to an off-the-shelf solver): one variable per (orientation, offset mod L), exactly-one constraint per quotient cell. Certificate: L plus placement list.
- **Stage 4 — Heesch / corona SAT.** Seed copy fixed at origin (breaks symmetry). Ask SAT for k complete coronas per D3; UNSAT at k+1 after SAT at k ⇒ Heesch number k, shape is a certified non-tiler. Budgets on k and on placement-universe radius.
- **Stage 5 — shortlist.** Anything still unresolved: record exact budgets exhausted (max torus index, max corona depth, solver time) so `OPEN` is a precise statement, then publish the shortlist.

Order the sweep so Stages 1–3 run over everything first (most shapes are tilers); Stage 4 only sees the survivors.

## Data model

One folder per shape — a folder of folders keyed by cube count, then a stable 1-based index within that count:

```sh
data/
  1/
    1/          # the monocube
  2/
    1/
  3/
    1/
    2/
  ...
  8/
    1/
    ...
    6922/
  9/
    1/
    ...
    48311/
```

Each shape folder holds:

- `shape.json` — the record below; with its certificate, the single source of truth
- `model.stl` — the shape alone, watertight and printable (GitHub previews STL in-browser)
- `tiling.obj` + `tiling.mtl` — tilers only: a chunk of one certified tiling, one color per copy (OBJ because STL carries no color)
- `corona.obj` — certified non-tilers only: the maximal corona, seed highlighted, layers colored by corona number (the 3D Heesch witness)
- `render.png` — quick browsing without a 3D viewer
- `cnf/` — published instances backing UNSAT claims

All meshes are generated from certificates by `script/gallery` — derived data, regenerable, never hand-edited. Rollup tables likewise.

Index stability rule: within each n, shapes are numbered by the lexicographic order of their canonical forms, assigned once and never renumbered — so `7/412` is a permanent, citable name for a shape.

```json
{
  "id": "7/412",
  "cells": [
    [0, 0, 0],
    [1, 0, 0]
  ],
  "n": 7,
  "symmetry_order": 1,
  "chiral": true,
  "mirror_id": "7/413",
  "verdict": "tiler",
  "tiles_rotations_only": true,
  "tiles_with_reflections": true,
  "certificate": {
    "type": "torus",
    "lattice": [
      [4, 0, 0],
      [1, 2, 0],
      [0, 0, 7]
    ],
    "placements": [{ "rotation": 5, "offset": [0, 0, 0] }]
  },
  "heesch": null,
  "budgets": { "box_max_volume": 96, "torus_max_index": 48 },
  "credits": {
    "solved_by": "polycube-census v0.1.0",
    "verified_by": null,
    "prior_art": null
  }
}
```

`cells` is the canonical form: translate to the origin corner, take the lexicographically minimal cell list over all 24 rotations.

Schema semantics (2026-08-14 migration): **`budgets`** records the search limits a shape was given (box volume, torus index, corona depth attempted); **`reached`** records outcomes (`corona_sat: k` — a verified depth-k witness exists; `corona_refuted: k` — depth k proven impossible), so "we gave up here" and "we proved it here" can never be confused. Heesch certificates carry their convention and provenance inline: `adjacency: "26"` (D3's corona definition — the number is meaningless without it), `refutation_sha256` (checksum of the DRAT artifact, which may live outside git), and `solved_with` (solver + version + verification notes). The tiling booleans are tri-state: `true`/`false` are proven claims; `null` means undetermined within stated budgets.

**`attempts`** (added 2026-10-06) records work that produced neither a witness nor a refutation. A depth in `budgets` with no matching outcome in `reached` already says "attempted, not settled". `attempts` says what that cost: one entry per depth with `as_of`, `core_hours`, `depth`, `notes`, and `status` (`running` or `stopped`). The first entry is 9/2127's corona-3, declared while its two colo solvers were still running, because a budget that waits for the solvers to stop is not a budget. Update the entry when they stop or speak.

**Refutation provenance** (added 2026-10-06). A heesch certificate says what its refutation is and who did the work, so a reader counts independent computations without parsing prose. `refutation_kind` is `proof` (one DRAT artifact for the whole formula, named by `refutation_sha256`), `ledger` (cube-and-conquer ledgers, solver say-so, audited by `script/audit-cubes`), or `cube_proofs` (decided 2026-10-07: a cube-and-conquer cover where every leaf cube has its own DRAT proof, each checked by drat-trim on delivery to the @home coordinator). For `cube_proofs`, `refutation` names a manifest in git, `cnf/corona<k>.proofs.json`, one line per leaf cube with its literals, its proof's digest and size, and the checker's verdict and seconds, and `refutation_sha256` is that manifest's digest. The proof bytes themselves travel as one bundle, `cnf/corona<k>.proofs.tar.xz`, published to S3 and listed in `data/artifacts.json`. `script/at_home/archive-cubes` writes all of it from the coordinator's verified results. `provenance` is `computed` (this record's own solve) or `derived` (leaning on the mirror twin named in `derived_from`, which must itself be `computed` and hold the same kind, checksum, and Heesch number, all of which `script/verify` asserts). Six non-tilers rest on four computations: three proofs (`8/1309`, `9/48258`, `9/8219`) and one ledger (`9/42947`).

**`checked`** (added 2026-10-06) records that a checker actually ran, as opposed to an artifact merely existing. `script/check-proof <id>` confirms the proof bytes hash to `refutation_sha256`, runs drat-trim against `cnf/corona<depth>.cnf`, and on `s VERIFIED` stamps `checker` (with its vendored commit), `date`, `seconds`, and `verdict` inside the certificate. Anything but VERIFIED stamps nothing. Only `computed` records carry it, since a derived twin's evidence is its mirror's.

**`stages`** (added 2026-10-06) says where a shape went through the pipeline and how each stage ended, so a shape that stalled in torus (a translational-einstein candidate) no longer serializes like one that stalled in corona. One entry per stage visited: `stage` is `box`, `torus`, or `corona`. `outcome` is `certified` (a tiling found, with its `volume` or `index`), `exhausted` (searched to the `volume` or `index` limit, nothing), `witnessed` (a corona of that `depth` exists), `refuted` (none of that `depth` exists), or `attempted` (that `depth` tried, nothing settled). A mirrored record carries its twin's stages, since a reflected certificate is exactly as strong and `credits.solved_by` already says where it came from. The array is derived from `budgets`, `reached`, `attempts`, and the certificate by `Census::Stages`, every writer stamps it, `script/stamp-stages` repairs it, and `script/verify` fails on any record where the stored array disagrees with its own fields. One known softness: on n=9 records certified by torus in the raised-budget triage rounds, the box limit is the budget the round was given, which earlier rounds had covered below `--min-volume`. True, but recorded from the budget, not observed in that run.

Credits follow the [WHUTS](https://whuts.org) model: every verdict names its solver (a human, or the pipeline at a specific version) and, once someone independently rechecks it, its verifier. Where a shape was already settled by prior work — the 261 tesseract unfoldings on WHUTS, hand-found Poly Pages patterns — import the solution as a certificate, cross-check it, and credit the original solver with a link in `prior_art`.

## Verification

Trust nothing from the solver directly:

- `script/verify` independently rechecks every certificate with plain geometry (coverage exactly once, placements congruent to the canonical shape) — no SAT involved. This is what makes the census citable.
- UNSAT verdicts (non-tilers, Heesch bounds): publish the CNF (conjunctive normal form) instances; produce DRAT proofs (a machine-checkable trace of the solver's reasoning, verified with [drat-trim](https://github.com/marijnheule/drat-trim)) for record-holders and headline facts only — proof files are huge.
- Global sanity check: enumeration counts must reproduce [OEIS](https://oeis.org) (Online Encyclopedia of Integer Sequences) [A000162](https://oeis.org/A000162) and [A038119](https://oeis.org/A038119) exactly before anything downstream runs.

## Tooling

- **Ruby** for everything orchestral: enumeration, canonical forms, CNF generation, certificate verification, reporting. Shapes at this scale are trivial for Ruby.
- **[kissat](https://github.com/arminbiere/kissat)** (via Homebrew) as the SAT workhorse; DIMACS files (the standard plain-text CNF format) in, witness out. [CaDiCaL](https://github.com/arminbiere/cadical) as fallback / second opinion.
- **RSpec** with real fixture files in `spec/fixtures/` (known tilers, known certificates, hand-built coronas).
- **Mesh export written directly in Ruby** — STL (the standard 3D-printing mesh format) for single shapes, OBJ/MTL for colored multi-copy assemblies; both are simple text formats, no mesh library needed. GLB for the web gallery can come at M6 from the same certificates.
- Scripts to Rule Them All:

```sh
script/setup      # brew install kissat, bundle install
script/test       # rspec --format progress
script/enumerate  # generate data/shapes/ for n ≤ N, check counts vs OEIS
script/census     # run pipeline stages over unresolved shapes
script/verify     # independently recheck every stored certificate
script/gallery    # emit STLs and renders
```

- **TODO: bring RuboCop back.** It was dropped early on and style passes have been manual since, checked against the suite and the generated output. That worked when the codebase was small. It now spans `lib/`, a dozen scripts, and the @home server and client, which is past the point where reading every file catches drift. Pin a config, run `rubocop -A` over the whole codebase once as its own commit, wire it into `script/test` and `script/cibuild`, and fix `script/test`'s header, which already claims to run a linter that isn't installed.

## Milestones

- **M1 — Scaffold + enumerator.** Repo, canonical forms, enumeration through n=8, counts match A000162/A038119. Acceptance: `script/enumerate 8` reproduces OEIS.
- **M2 — SAT plumbing.** Box + torus stages working; all shapes n ≤ 4 certified, results hand-checkable (screws pair into a 2×2×2 cube, etc.).
- **M3 — Folklore certified.** All 207 shapes through n=6 carry `TILER` certificates. (Publishing anything, incl. OEIS submissions, waits until after M5 — see M6–M8.)
- **M4 — The heptacube sweep.** All 1,023 n=7 shapes resolved or budgeted-OPEN. Headline: smallest non-tiler (or proof all heptacubes tile), first 3D Heesch table. This is the paper.
- **M5 — n=8.** Records hunt: max 3D Heesch, first anisohedral, shortlist growth. Includes the 261 tesseract unfoldings already settled by the [WHUTS](https://whuts.org) community (all tile; solutions collected via Moritz Firsching's code, independently verified by Georgios Papoutsis) — import their tilings as certificates with per-shape solver credits, and use the overlap as an external cross-check of our pipeline. (Done — including the square ring resolution below and the WHUTS import.)
- **N9 — sweep (added 2026-07, underway).** Enumerate the 48,311 nonacubes (OEIS-exact), run the full gauntlet, triage the survivors. Sweep found 48,200 tilers; 111 survivors (60 mirror classes, none ring-derived) in raised-budget triage, surround/corona next.
- **M6 — Publish: gallery.** Browsable gallery generated from certificates, printed record-holders.
- **M7 — Publish: OEIS.** New sequences submitted (number of n-polycubes that tile a box, that tile space, non-tilers by Heesch number, …).
- **M8 — Publish: paper.** [Geombinatorics](https://geombina.uccs.edu) fits the genre; arXiv math.CO/math.MG with endorsement. Writing convention: keep standard math idioms (`iff`, coronas, anisohedral, …) in the text, and include a glossary footnote/appendix expanding them for non-mathematicians.

## The square ring (8/1309): does chainmail tile?

**RESOLVED: no.** The flat 3×3 ring — the only non-simply-connected polycube in range — has Heesch number 1 and is the unique smallest non-tiling polycube. The original plan (surround test → Heesch escalation → deeper periodic search in parallel) ran to completion:

- **Corona 1 is SAT:** a verified 28-copy wrap — chainmail gets one layer. Witness frozen in `data/8/1309/corona1.json`, rechecked by `script/verify`.
- **Corona 2 is UNSAT:** reproduced by kissat and CaDiCaL; DRAT proof checked by drat-trim (`s VERIFIED`); CNF instances published under `data/8/1309/cnf/`.
- **No periodic escape:** no box through volume 128 (16 copies), no periodic block through lattice index 152 (19 rings), after lattice-orbit dedup under the 24 rotations (~20x fewer solves).

Still open from the original plan, both feeding the paper:

- **Pen-and-paper track.** Counting argument: one hole per ring, one donated cell per hole, and only the 4 edge-middle cells of a ring can sit in a hole (hand-checked; corners cannot). Target: a human-readable hole-cascade proof of corona-2 impossibility; even partial results are lemmas.
- **Deeper literature pass** through puzzle literature before any write-up (passive only until comms open, per the scoop-risk policy below).

## Names, addresses, and the public face (decided 2026-08-15)

The census will outlive any one person's accounts, so identity decisions are made once, early, and with an eye to what a paper can cite permanently.

- **Domain: [`polycubes.org`](https://polycubes.org)** — registered 2026-08-15. The subject noun is what people search and cite; `.org` for non-commercial science. Still worth registering `polycubing.org` as a redirect so the org name, the program name, and the gerund all land in the right place.
- **GitHub org: [`polycubing`](https://github.com/polycubing)** — acquired. Contributor-facing infrastructure: `polycubing/census` (data + pipeline, transferred from `veganstraightedge/polycube-census` on 2026-10-06), the @home coordinator and clients, the site. Role names, not prefixed names, because the org is the subject. (`polycubes` is taken by an apparently-dormant org; not worth banking on.)
- **Org avatar: the triskelion, `9/42947`** (decided 2026-10-06). Three bars braided around a vacant corner, seen from a generic angle so it reads as three sticks and not as a triangle. The square ring was the other candidate and lost on being flat, which reads as a polyomino. Render settings, so it can be regenerated: rotation 0 of the canonical cells, camera azimuth 30°, elevation 20°, perspective at 3 shape-widths, key light above-left of the camera, Lambert-shaded grey faces with dark edges, on a square `#f6f8fa` background, 1024 px. No rounded corners: each site rounds its own avatars. Regenerate with `script/render 9/42947 --size 1024 --background "#f6f8fa"`, whose defaults are these settings.
- **Crowdsourced compute program: Polycubing@home** — Folding@home's grammar, the activity as a gerund, matching the org name. The subject is polycubes; the activity is polycubing; the volunteer program is where the two meet.
- **Citation rule: the paper cites `polycubes.org`, never a `github.com` URL.** A domain we control keeps hosting, org naming, and even the choice of forge reversible forever; a printed GitHub URL does not.

### Site structure

Shape ids _are_ paths — `9/2127` is already the citable name in `data/`, in the paper, and in conversation, so it addresses the page too. Never prefix it (`/shapes/9/2127`), never renumber.

```txt
/                      the census: what it is, the scoreboard
/8                     octacubes index (per-n indexes, bare number)
/9/2127                shape permalink — the id is the path
/open                  the OPEN shortlist and the Heesch >= 2 club
/heesch                the 3D Heesch table
/verify                don't trust us, check us: clone, script/verify, drat-trim
/data                  the dataset itself — structure, CC0, downloads, artifact manifest
/at-home               Polycubing@home (canonical)
/@home                 pretty alias, redirects to /at-home
/at-home/volunteers    compute donors, generated from the coordinator's moderated display names
/code                  links to the org and its repos
/papers                published papers and pre-publication drafts
/papers/<title-slug>   paper permalink; /papers/arxiv/<id> redirects to it
/thanks                hand-curated humans: reviewers, advisors, lenders of servers
/about /contact        the usual
/contribute            one page covering compute (-> /at-home), code (-> /code), and mathematics
/glossary              for readers who arrive without the vocabulary
```

Notes on the choices: `@` is a legal path character and `/@home` looks good, but `/at-home` is canonical because static-site generators can balk at a directory named `@home`, chat clients try to turn it into a mention, and an `@` inside a printed citation reads ambiguously. Paper URLs use title slugs rather than arXiv ids so they survive preprint-to-journal moves. The volunteer list is machine-generated and potentially enormous; `/thanks` is hand-written and small — different pages for different provenance. No `/donate`: there is no money in this, and a donate link would create an expectation to manage.

## Someday / future

- **Lean (formal verification), two hooks.** At M4: check solver UNSAT proofs with a formally verified checker (Lean 4's LRAT checker or cake_lpr) for headline claims — drat-trim is itself unverified C. Post-M8 stretch: formalize the encoding's soundness ("CNF UNSAT ⇒ no tiling of ℤ³") in Lean, making the smallest-non-tiler result a fully machine-checked theorem; potential Lean-community collaboration.
- **Box-order addendum.** For shapes holding only torus certificates, rerun the box stage at rising budgets (an "upgrade pass" — the pipeline must revisit already-stamped shapes seeking stronger certificates). First box found in ascending volume = the shape's exact box order (Klarner's "order", unexplored in 3D; Dahlke's heptominoes hit orders 76 and 92 in 2D). Survivors get certified lower bounds ("no box through k copies"); diffable data releases per budget raise.
- **Manim visualizations + YouTube.** After M6, use the census as source material for Manim animations (tilings assembling, coronas growing and getting stuck) and a video or few. Certificates are the animation data — placements are keyframes — so this stays a pure consumer of `data/` and needs nothing from the pipeline now.
- **Unfoldings track.** The open problem (Wikipedia, unsolved): can every polycube with a connected boundary be unfolded to a polyomino, and if so, to one that tiles the plane? Our results don't bear on it (interior-tiles-space vs boundary-unfolds-to-plane-tiler are independent invariants), but this project holds the raw materials its attacker needs: the canonically-indexed catalog with stable citable ids, topology annotations (first tunnel 8/1309 with its genus-1 boundary, the staircase's pinched hole, cavities at larger n — their hypothesis's fine print), and the SAT-plus-certificates playbook ("tiles the plane" is our torus test one dimension down; unfolding search is a combinatorial cut-tree hunt, also SAT-shaped). Natural third member of the WHUTS family: cube unfoldings tile the plane (all 11 hexominoes, classical), tesseract unfoldings tile space (all 261, WHUTS), polycube unfoldings tile the plane (open). Could become a census track of its own after n=9 settles.

## Risks and open questions

- **Scoop / prior-art risk.** The folklore claim and the unanswered forum question suggest this is unclaimed. Passive literature searches (which reveal nothing) continue throughout. Active outreach — Poly Pages maintainer, [the tiling group thread](https://www.facebook.com/groups/tiling/posts/1150714768685400), Kaplan — is deliberately deferred until after n=8 is done (decided 2026-07-06): math first, packaging and comms after, with results in hand.
- **Corona SAT blowup in 3D.** Placement universes grow much faster than in 2D. Mitigations: tight radius bounds, incremental solving, aggressive symmetry breaking on the seed. Unknown until measured — measure early on a few n=7 shapes.
- **Torus budget misses long-period tilers.** A tiler whose minimal periodic block exceeds the budget lands in `OPEN`. Acceptable: `OPEN` verdicts state their budgets.
- **Definition sensitivity.** Heesch values can depend on D3's adjacency choice; report the convention prominently and sensitivity-check records.
- **The einstein jackpot is not the plan.** Anything in `OPEN` after honest budgets is a finding to publish, not a proof of aperiodicity — proving that would be a separate (human) project. The census is the contribution either way.
