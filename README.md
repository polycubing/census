# A Polycube Tiling Census

A machine-verified census of the tiling behavior of every small polycube: which shapes tile 3D space, which provably cannot — with their 3D Heesch numbers, tabulated for the first time — and which resist classification.

In 2D this work has been done: exhaustive censuses classify every small polyomino, polyhex, and polyiamond as tiler or non-tiler, crowned by Craig Kaplan's [_Heesch Numbers of Unmarked Polyforms_](https://arxiv.org/abs/2105.09438). In 3D, no equivalent existed. Even the smallest polycube that fails to tile space was undocumented — the 2D answer has been known for decades. This census settled that question (the 3×3 square ring, 8 cells — see below) and keeps going, in public, with a machine-checkable certificate behind every claim.

## Verdicts

Every polycube through `n = 9` cells — all 56,463 of them — carries exactly one:

| Verdict     | Meaning                                   | Certificate                                        |
| ----------- | ----------------------------------------- | -------------------------------------------------- |
| `TILER`     | fills all of space                        | a repeating block you can verify by hand or script |
| `NON_TILER` | provably cannot tile                      | an exhausted maximal corona (its Heesch number)    |
| `OPEN`      | survived every test within stated budgets | the budgets themselves                             |

`OPEN` is the interesting bucket: shapes that tile far but have no small periodic pattern. Anything that lands there is a candidate for deeper study — the 3D analogue of the hunt that produced the 2023 aperiodic monotile. (The Hat: [Numberphile 1](https://youtu.be/ArADlJx7SlU), [Numberphile 2](https://youtu.be/_ZS3Oqg1AX0). Spectre: [Ayliean 1](https://youtu.be/IfVwelta1fE), [Ayliean 2](https://youtu.be/sLQrHz7CQf4).)

## Questions this aims to answer

1. Do all 207 polycubes through `n = 6` tile space? (Folklore says yes, but folklore isn't proof.) **Answered: yes — all 207 carry verified certificates.**
2. What is the smallest polycube that does not tile space? **Answered: [`8/1309`](data/8/1309/shape.json), the flat 3×3 square ring — the only non-simply-connected polycube through `n = 8`, and the unique non-tiler among all 8,152 shapes. Every polycube with 1–7 cells tiles space.**
3. What are the first 3D Heesch numbers? (AFAICT, no table of them already exists anywhere.) **Answered, and the table has two rows.** Heesch 1: the square ring, wrapped once by 28 copies and provably never twice (drat-trim `s VERIFIED`), joined at `n = 9` by [`9/48258`](data/9/48258/shape.json) (the 5×5 Greek cross, also verified), the chiral pair [`9/8219`](data/9/8219/shape.json)/`9/8220`, and the chiral pair [`9/42947`](data/9/42947/shape.json)/`9/42969` (the triskelion — three perpendicular arms braided around a vacant corner, refuted by a 12,861-cube cube-and-conquer campaign). Heesch ≥ 2: **eight nonacubes wrap twice** — the first shapes ever known to do so in three dimensions, each with an independently verified two-layer witness (the largest: 370 copies).
4. What is the smallest polycube that tiles only anisohedrally — never tile-transitively?
5. Does anything through `n = 9` resist classification entirely? **Every shape through `n = 9` now carries a verdict.** Eight of them are `OPEN` with documented budgets — shapes that wrap twice, admit no box through volume 128, and admit no periodic block through lattice index 72. One question remains genuinely unanswered: does [`9/2127`](data/9/2127/shape.json), the staircase, wrap a _third_ time? Its corona-3 has resisted ~900 core-hours across six solvers and three cube-and-conquer campaigns.

## How it works

Each shape runs a gauntlet of increasingly expensive stages, stopping at the first certificate: translation-lattice check, box tiling, periodic tiling on skew tori, then corona-by-corona SAT (Boolean satisfiability) search until the shape is certified either way or budgets are exhausted. Details, definitions, and decision log: [PLAN.md](PLAN.md).

Three rules keep it honest:

- **No claim without a certificate.** Solver output is never trusted directly. An independent script rechecks every certificate with plain geometry.
- **The enumeration must reproduce OEIS** (the Online Encyclopedia of Integer Sequences: [A000162](https://oeis.org/A000162), [A038119](https://oeis.org/A038119)) before anything downstream runs.
- **Every verdict names its solver and verifier**, in the style of [WHUTS](https://whuts.org) — including imported prior work, credited to the people who did it.

## The data

One folder per shape, one JSON record per folder:

```sh
data/
  1/1/shape.json     # the monocube
  ...
  6/122/shape.json   # "6/122" is this shape's permanent id
  ...
  9/48311/shape.json
```

Indices are assigned once, by lexicographic order of canonical forms, and never renumbered — `6/122` is a citable name whose ID is literally its path. Records carry the shape's geometry (canonical cells, symmetry order, chirality, a link to its mirror twin) and its verdict fields, which fill in as the pipeline runs. Meshes (`model.stl`, tiling and corona assemblies) are generated from certificates and land beside each record.

## Status

- [x] **M1 — Enumeration.** All 8,152 shapes through `n = 8` with counts matching OEIS [A000162](https://oeis.org/A000162) and [A038119](https://oeis.org/A038119) exactly.
- [x] **M2 — SAT plumbing.** Box and torus stages with everything through `n = 4` certified.
- [x] **M3 — Folklore certified.** All 207 shapes through `n = 6` carrying `TILER` certificates (16 of 29 pentacubes and 68 of 166 hexacubes tile a box within budget; the rest are periodic via skew lattices — many are translations-only lattice tiles).
- [x] **M4 — The heptacube sweep.** All 1,023 heptacubes tile space (36 box, 987 skew-lattice) — so the smallest non-tiling polycube, if any exists through `n = 8`, has exactly 8 cells. A first divergence from 2D, where non-tilers already appear among the heptominoes.
- [x] **M5 — N8.** Sweep: 6,921 of 6,922 octacubes tile (383 box, 6,538 skew-lattice), all certificates independently verified. The lone holdout, [`8/1309`](data/8/1309/shape.json) — the flat 3×3 square ring (the holey octomino) — is a certified **non-tiler with Heesch number 1**: its hole is an open channel that perpendicular rings can thread, and chainmail gets exactly one layer — corona-1 has a verified 28-copy witness, corona-2 is UNSAT (kissat and CaDiCaL agree; DRAT proof checked by drat-trim: `s VERIFIED`). The census through `n = 8` is complete: zero open shapes. WHUTS cross-check done — all 261 tesseract unfoldings imported with per-shape solver credits.
- [x] **N9 — the nonacube sweep.** All 48,311 nonacubes enumerated (OEIS-exact) and resolved: **48,298 certified tilers** (782 box, 47,516 skew-lattice), **5 certified non-tilers** (the Greek cross `9/48258`, and the chiral pairs `9/8219`/`9/8220` and `9/42947`/`9/42969`), and **8 `OPEN` shapes with verified Heesch ≥ 2 witnesses** — the first shapes known to wrap twice in three dimensions. Every certificate independently verified; the last holdouts fell to mirror propagation, corona SAT, and a cube-and-conquer campaign run across a borrowed 64-core server. Zero unresolved shapes.
- [ ] **M6 — Publish.** Browsable gallery (meshes done for all 56,463 shapes — models, tilings, corona witnesses; the web viewer is what remains).
- [ ] **M7 — Publish.** OEIS sequences.
- [ ] **M8 — Publish.** Paper.

## Running it

```sh
script/setup        # brew bundle (kissat) + bundle install
script/enumerate 9  # regenerate data/, verified against OEIS
script/test         # specs + linter
```

Ruby version is pinned in `.ruby-version`.

## Kin and prior art

- [BurrTools](https://burrtools.sourceforge.net) — independent cross-check for box tilings
- [Kaplan, _Heesch Numbers of Unmarked Polyforms_](https://arxiv.org/abs/2105.09438) and [isohedral/heesch-sat](https://github.com/isohedral/heesch-sat) — the 2D prior art and inspiration for this census
- [Kaplan, _Detecting Isohedral Polyforms with a SAT Solver_](https://arxiv.org/abs/2406.16407) — the SAT approach to isohedrality, relevant to the smallest-anisohedral-polycube question
- [Myers, _Polyform tiling_](https://www.polyomino.org.uk/mathematics/polyform-tiling/) — the software and data behind the 2D tiling censuses (2000–2024), this repo's closest sibling; his anisohedral enumerations ([OEIS A075206](https://oeis.org/A075206)) are the 2D baseline for the anisohedral question
- Keating & Vince, _Isohedral polyomino tiling of the plane_ (Discrete Comput. Geom. 21, 1999) and Langerman & Winslow (SoCG 2016) — fast 2D isohedral decision procedures with no 3D counterpart (see PLAN.md on why)
- Rhoads, _Planar tilings and the search for an aperiodic prototile_ (PhD diss., Rutgers 2003) — search-census methodology, pre-SAT
- Bašić, _A figure with Heesch number 6_ (Math. Intelligencer 43(3), 2021) — the standing 2D Heesch record, calibration for our 3D table
- Brakensiek–Heule–Mackey–Narváez, _Keller's conjecture in dimension 7_ (2020) — a cube-tiling problem resolved by reduction to SAT; the closest methodological kin to this census
- [OEIS](https://oeis.org) — ground truth for counts, and will be the destination for any new sequences
- [The Poly Pages](http://www.recmath.com/PolyPages/PolyPages/Tiling.htm) — the hand-found folklore that this census aims to certify
- [WHUTS](https://whuts.org) — hypercube unfoldings (a slice of our `n = 8`), and an example of attribution/credit to contributors (solvers/verifiers)
- [The polycube unfolding problem](https://en.wikipedia.org/wiki/Polycube) (open) — does every polycube with connected boundary unfold to a polyomino, ideally one that tiles the plane? Independent of our question, but this catalog and toolkit are its natural substrate; see PLAN.md's Someday list

## Glossary

- **anisohedral** — tiles space, but no tiling treats every copy identically
- **certificate** — data that lets anyone recheck a claim without trusting us
- **chiral** — differs from its mirror image, no rotation turns one into the other
- **Heesch number** — how many complete layers (coronas) of copies you can wrap around a shape before getting stuck, measures how far a non-tiler gets
- **periodic** — a tiling that repeats on a lattice, like 3D wallpaper
- **polycube** — a solid made of unit cubes glued face-to-face, like Tetris pieces (tetracubes)
- **SAT solver** — a program that decides whether a huge `true/false` formula can be satisfied, our tiling questions are encoded as such formulas
- **tiling** — filling all of space with copies of a shape, no gaps or overlaps

## Author and license

By [Shane Becker](https://veganstraightedge.com). Dedicated to the public domain under [CC0 1.0](LICENSE) — reuse anything, credit is appreciated but not required.

---

Your heart is as free as the air you breathe. \
The ground you stand on is liberated territory.
