# Owned function-value calls

Static callback parameters and one natural result may use the backend's admitted
region-backed arrays, single-tail records/frame objects, standalone variants and
nonresizable variable-mode enums. Unsupported layouts retain their normal gate.
The callback's checked body type defines its result; contextual array adaptation
does not replace that natural type.

Result storage is prepared before arguments, matching the native callback
emitter. Exact receiving destinations can be reused, including recursive result
forwarding. Other kinds, capacities, length widths and variant-to-enum receivers
first construct the natural result and then adapt the captured value once.

An exact element-run request follows the pinned append convention. For example,
appending a callback's `u8[u8]` result can accept 256 elements; constructing that
callback result as a growable value first checks the natural u8 length and fails.
Normal receivers preserve value checks. This distinction is covered at O0/O2
in normal/debug frontend modes against all three compilation paths.

Parameters evaluate left to right. Each owned parameter receives independent
storage before its argument initializes it. Fixed aggregate arguments are copied
before evaluating later arguments. The body constructs a copy of its tail into
the result destination; callback locals do not receive ordinary named-result
aliasing. Argument temporaries retain the existing enclosing-statement lifetime
where required. Private parameter headers and body locals have their own logical
cleanup depths, while the result survives both watermarks.

Callbacks do not introduce a new return target: a nonlocal return still names the
function selected by the frontend. [Fixed and admitted growable/frame result-group contracts](NONLOCAL_RETURNS.md)
can cross ordinary emitted calls. Other owned targets require further staging
and landing support.

Borrowed/holder results require an additional conservative check. The pinned
checker does not apply ordinary return-root checks to a callback's tail. Its
native emitter can release an owned callback parameter before a later argument
reuses that storage. The direct backend refuses results that may reach callback
parameters or local bindings, including holders nested in aggregate fields and
array elements. This currently also excludes safe direct external-view parameter
pass-throughs; it does not claim complete escape analysis. Stored function values
remain rejected by the language frontend.

Fixtures cover arrays and limited capacity, records/frame objects, enum payloads,
single evaluation, fixed/owned argument snapshots, source/result independence,
multiple ordinary result channels, narrow contracts and recursive forwarding.
Resource checks keep returned data alive across repeated calls and verify that
owned parameter/body storage is reclaimed on both engines.
