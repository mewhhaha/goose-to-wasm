# Growable varint element qualification

Implementation: `fe77800`.
Release compiler SHA-256: `aa9490bc12fd0ae6972d3238d820f4ccafc798c7149466ee72e88bb0a6928d2d`.
Debug compiler SHA-256: `621e489ff97d344942b233477b1df52a0a102f71d59fbdadecfd76ca458534ce`.
Both prepared compiler header trees match this implementation byte for byte.

- Full Release matrix **6533/6533**, native/C-Wasm/direct at O0/O2 on V8
  and Wasmtime, including the retained compile refusals.
- Full Debug direct matrix **2615/2615** and focused matrix **360/360**.
- On both final builds: resources **104/104**, sessions **11/11**, captured
  alias boundaries **8/8**, enum boundaries **6/6**, variant/owner/dynamic
  boundaries **4/4 each**, packed boundaries **3/3**, array/sparse checks
  **3/3 each**, record/enum images **5/5 each**, compact tags **3/3**, enum
  returns **2/2**, static capacity **5/5**, padding bytes/boundaries **5/5
  each**, varint record bytes **3/3**, varint array bytes **4/4**, varint
  boundaries **7/7**, captured-varint boundary **1/1**, varint array
  boundaries **3/3**, Grow bytes **3/3** and Grow boundaries **3/3**.
- Release extensions **100/100**, scalar-cache checks **13/13** and static
  data checks **4/4**.

Layout 12 adds raw sequential `varint[>..]` elements. Push reserves an entire
canonical encoding before writing. Borrowed append copies encoded bytes; fresh
append constructs into private natural-type controls in the receiver's region,
publishing its count only after success. Clear and assignment retain native
cursor behavior. Canceled append keeps committed bytes without publishing its
count, and returned push references identify the newly written physical bytes.

Astra independently reviewed forwarding, cancellation and resource behavior.
Review found a natural-type FV carrier mismatch and an escaping Value dispatch
that could leave a length prefix in raw elements. The final candidate fixes the
carrier and gates transitive-needs Value-to-raw landings. Named Grow later
observations and actual encoded nonlocal targets remain explicitly refused.
Tests retain the minimized cases, exact-width exhaustion and neighbor canaries,
including 10,000 recursive and canceled appends. Unsigned length prefixes,
containing walkers, general variable elements and serialization are separate
checkpoints.

Reports in the varint-grow worktree:
`build/varint-grow-release-qualified/report.json`,
`build/varint-grow-candidate-direct/report.json`,
`build/varint-grow-candidate-focused/report.json`,
`build/varint-grow-release-extensions/report.json`.
Auxiliary logs: `/tmp/varint-grow-{candidate,release}-*.log`.
