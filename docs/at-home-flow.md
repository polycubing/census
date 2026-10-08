# Polycubing@home: flow control

How work and artifacts should move between the hub and the machines that solve and check, so that no machine is ground to a halt and no volunteer pays for the hub's limits. Written 2026-10-08 after the triskelion campaign's first day, which found every one of these gaps by hitting it.

## The bathtub

The hub is a bathtub. The faucet is `/lease`, handing out cubes. The water is proofs: a volunteer produces one per cube and delivers it. The basin is the hub's proof directory and its database rows in state `stored`. The drain is the checker, which verifies a proof and so lets it leave the basin for the archive.

On 2026-10-07 the faucet ran with no knowledge of the basin. Eight clients produced proofs of a few hundred megabytes each faster than forty drat-trims could verify them, the basin filled a disk twice, and the volunteers paid: kissat died flushing proofs, clients crashed, the server died writing its own log. The campaign ran only because a person watched `df` and killed clients by hand.

## What each role knows and limits

**The hub** knows how full the basin is: stored proofs, their bytes, free disk under the proof directory. It must stop the faucet when the basin is near a high-water mark and open it again below a low-water mark, so the level oscillates in a band instead of overflowing. It must never hand out work it cannot take the result of.

**A volunteer** has limits of its own, and only it knows them: free disk, cores, how long it is willing to spend. It declares what it will, and enforces the rest locally: no new solve when its own disk is under a floor, one artifact at a time, delete the artifact the moment the hub has confirmed receipt. "Confirmed" means the hub checked the digest and wrote the bytes atomically, which it does as of 2026-10-07.

**A checker** is the drain, and it cannot be a volunteer. A volunteer saying "I checked it and it holds" is the say-so this whole design refuses. Checkers are machines we control: the colo, the laptop, a cloud box. There can be many, and that is the only way the drain scales, because checking a proof costs more than finding it (9/8219: 35 minutes to refute, 8.4 hours to check).

## The pieces, in the order to build them

1. **Backpressure at the faucet.** `/lease` answers "nothing now, back off N seconds" when stored bytes exceed a high-water mark or free disk under the proof directory is below a floor, and resumes below a low-water mark. Clients already sleep on an empty lease, so no client change is needed. Small, and it would have prevented both disk-full outages. Do first.
2. **Volunteer self-limits.** Client flags for a local free-disk floor and a time cap, and the rule that it holds one artifact and deletes it on confirmed receipt (the deletion is done). Small.
3. **Checkers that pull.** A checker fetches a stored proof from the hub over HTTP, the way clients fetch formulas, checks it against the formula it rebuilds, and posts the verdict. Then the laptop, with its disk and bandwidth, is a checker, the colo is a checker, and the hub needs only enough disk to hold a proof between its arrival and the next checker's pull. This replaces the drain-by-rsync. Medium, and it is the change that makes the hub's disk stop mattering.
4. **Declared limits and size-aware dispatch.** A volunteer registers with what it has, and the hub shapes what it sends: no monster cube to a laptop with 10 GB free. The August ledgers already say which cubes were monsters. BOINC's model, for when strangers exist, which is n=10.

## What stays true throughout

- Positive results (a tiling, a satisfying model) are self-certifying and verified by geometry on arrival. Negative results (a refutation) are a digest until a checker we control has replayed the proof.
- The archive of record is a machine we control with the disk to hold it, today the laptop, with S3 for publication. A volunteer holds nothing it has delivered.
- Every limit is a number in a flag or a column, never a person watching `df`.
