# Variable enum nonlocal image return qualification

Implementation: `7ee9efa`.
Release compiler SHA-256: `053c8e1db9b485959003acf4183f33702a497dbc8d309f70890b0c190bf1bed2`.
Debug compiler SHA-256: `c901599479fe51de1ef3a2d0a49938e93cffeef1fa0c329e55d1e8468e63b6c2`.
Both prepared compiler header trees match the implementation byte for byte.

- Full Release matrix **5693/5693**, native/C-Wasm/direct at O0/O2 on V8
  and Wasmtime, including three compile refusals.
- Full Debug direct matrix **2279/2279**, focused matrix **180/180**.
- Resources **92/92**, sessions **11/11**, capture boundaries **8/8**,
  enum boundaries **6/6**, variant/owner/dynamic boundaries **4/4 each**,
  packed-layout boundaries **3/3**, array/sparse checks **3/3 each**,
  record/enum image checks **5/5 each**, enum-return checks **2/2**, compact
  tags **3/3**, on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Proven nonresizable variable enums can now be actual nonlocal return targets.
Each result stages an active image and private controls, then lands its physical
suffix at the receiving entry anchor. Sparse logical extent stays separate from
the physical cursor. Tuple forwarding preserves each result's original receiver;
pending returns remain protected through landing and cleanup. Existing closed
capture and exact result gates remain in force. Internal layout 7, mailbox shape,
scalar ABI 1 and terminal owner headers are unchanged.

Fixtures exercise canceled prefixes, named anchors, sparse and Limited payloads,
all-starts-before-construction, nested replacement and exact tuple forwarding.
Repeated calls and low-memory probes check canaries, activation exhaustion and
surviving global-owner bounds. Astra independently passed 18 native/direct
comparisons and two repeated-call probes on both engines and optimization levels.
The embedded original-control replacement-range guard was structurally audited;
no valid language source reaching that particular defensive branch was found,
so runtime branch coverage is not claimed.

Reports in the enum-returns worktree:
`build/enum-returns-release-qualified/report.json`,
`build/enum-returns-dev-direct/report.json`,
`build/enum-returns-dev-focused/report.json`,
`build/enum-returns-release-extensions/report.json`.
Auxiliary logs: `/tmp/enum-returns-{dev,release}-*.log`.
