# Nonlocal return effects

Out-of-line `return ... from` and captured callback returns support targets whose
result types have fixed size, including scalars, references/slices, fixed
aggregates and mixed/multiple fixed results. Existing frontend lifetime checks
still apply. Growable/grow-shrink arrays and fixed-prefix frames may accompany supported
fixed results under the staging and landing contract below. Variable/capacity-
limited arrays and enum/non-frame-record owned kinds remain explicitly gated.

Final checked bodies identify actual escaping returns. Discovery skips raw
declarations/function-value templates, walks checked callback/default bodies and
recognizes direct/inlined local exits. It does not gate optimized code merely
because a checker `needs` set retains obsolete effects. The pinned optimizer
keeps a live nonlocal target out of line while a callee still needs it.

Each target specialization has an active mailbox pointer. Function entry installs
a mailbox in its checked frame and saves the preceding pointer. Recursive calls
therefore select the innermost active target of that concrete specialization.
Normal and propagating exits restore the previous binding. The external scalar
host ABI and owner control layout do not change.

A source return evaluates and snapshots all fixed results in order, copies their
bytes into the target mailbox and only then publishes the pending token. Internal
ordinary and selected case calls check that token before argument cleanup,
publication, conversion or subsequent expressions. The target captures mailbox
values, performs abandoning cleanup while the token remains set, clears it and
finishes normally. Other frames perform cleanup and return dummy Wasm values,
bypassing normal aggregate result copying. An uncaught token at `_start` aborts.

Owner recognition spans physical activations. Each has a fixed table of header
slots with live flags; registrations include locals, caller argument construction,
callee private parameters, shared-region private headers and temporaries. Enum
records also identify their image control interior, so an embedded tail header
passed to an ordinary variant producer can be recognized. Whole-header named
result aliases are never registered as private callee owners.

Lexical cleanup deactivates records. Anonymous records carry their enclosing
temporary scope's logical boundary, surviving incidental early inline exits.
Retained argument groups transfer their temporary clear actions. During nonlocal
cleanup, records stay live until all abandoned-construction checks complete.
Headers owned by the target or a deeper activation die; surviving global/caller
headers still enforce published extent checks. No extra data region is needed
for the registry or fixed mailboxes; their bytes use the checked activation arena.

Three fixtures are unchanged pinned upstream tests: `return_from_cycle`,
`return_from_cached_call` and `return_from_block_target`. The generic test removes
only its final owned-array invocation/output block; its fixed specialization
definitions and calls remain unchanged. Further fixtures cover recursion,
aggregate snapshots before later mutation, selected-case effects, owned callback
scopes, print scratch and retained anonymous arguments. Resource tests repeat
interrupted constructions, including a dying local, a surviving global and an
embedded enum tail, on V8 and Wasmtime.

## Single owned target with a growable tail

An owned escape snapshots the target region's physical cursor before evaluating
its source. A private control record constructs the value behind existing data
without replacing the old receiving header. Only a completed value and its start
address enter the target mailbox. The catch moves the entire physical suffix to
the receiving base, publishes the winning logical length and preserves physical
bytes beyond that length. Staging uses activation bytes, not another data region.

Cancellation does not roll back the physical cursor. A later normal return
stages at the current cursor; it moves its suffix only when a syntactically open
construction or named result requires landing. The compiler tracks that open
construction state separately for function and inline exits. Named Ident returns
keep the existing native shortcut. Ordinary forwarding evaluates its arguments
before selecting the producer's base, while the escape's original start stays
fixed. O0/O2 can therefore expose different, explicitly tested values when an
argument appends to the same receiving region.

A per-region cursor table separates committed physical bytes from logical
length. Grow/shrink mutation reserves and advances that cursor. Modules needing
this contract publish `goose.regions` schema 2 with `cursor_base` and
`cursor_stride: 4`; other modules retain schema 1. The existing 16-byte control
layout and public scalar host ABI remain unchanged.

Interrupted normal construction preserves receiving-channel publication. Grow
receivers expose length before literal element effects, including element-run
calls whose natural result is a variable array. Frame receivers expose fixed
prefix fields in declaration order, then initialize terminal base and zero length
before evaluating the terminal initializer or its arguments. Array producers
receive only the length channel; the frame constructor controls base publication.
Private stage controls forward those writes through active owner mappings;
fixed-field addresses resolve to their receiving storage. Publication mappings
expire on every exit while dying-owner evidence remains available for cleanup.
Variable/capacity-limited array images and non-frame variable record prefixes
remain private. Landing saves the entry base independently of published frame
base changes. Surviving published extents still receive their resource checks;
a replaced target result and dying private owners do not reserve abandoned data.

The initial owned-source admission accepts supported location/copy reads and
closed ordinary producers with fixed, reference-free parameters/captures.
Qualified growable forwarding can evaluate push arguments. Callback-result and
unproved borrowed/owned producer environments receive a diagnostic. Variable,
capacity-limited and enum/non-frame-record owned nonlocal results
require further work; this is not a general owned-effect parity claim.

Differential fixtures cover recursive target identity, local source slices,
argument ordering, canceled partial values followed by literal/copy/forwarded
returns, nested frame publication, inline named alternatives and coexistence
with earlier array/record/enum behavior. Resource tests repeat successful and
interrupted returns under small memory limits with neighboring canaries.

## Frame-valued target landing

A frame target may have fixed prefixes nested to one fixed-element Grow or
GrowShrink tail. Its mailbox stores the original whole-control address, the
physical entry cursor, the escape start and an aligned private control snapshot.
Construction of that snapshot keeps prefix/base/length publication private until
it completes. The target catch moves the complete physical suffix to its saved
entry cursor and publishes the winning prefix and logical length. Its final tail
base is `entry + (winning_base - escape_start)`; the original resource limit is
preserved. Bounds validate the winning length relative to its base within the
suffix. No additional data region is acquired for the snapshot.

Canceled frame attempts retain physical tail bytes and discard their private
prefix. A later named-frame return snapshots its prefix, tail base and length;
restoring only length could retain the canceled attempt's suffix base. Literal,
closed ordinary forwarding, recursive sources, nested prefixes and selected-case
propagation share the same catch. Existing conservative producer gates apply.

## Fixed results beside one owned result

A target can place one admitted owned result at any ordinal beside supported
fixed/scalar/reference/slice results. The mailbox retains the original owned
control, target-entry cursor and attempt start, then stores every result snapshot
at its type's alignment. The owned start is captured before evaluating any
source expression, including earlier fixed expressions that append to the same
receiving region. Explicit expressions evaluate left to right; each fixed
aggregate is copied immediately. All successful snapshots enter the mailbox
before pending publication.

At catch, fixed snapshots and the owned suffix share the existing cleanup and
function epilogue. Canceled attempts keep physical suffix data and publish no
mailbox result. Optimized local returns keep ordinary per-ordinal construction:
their owned ordinal can land before a later ordinal cancels the return. The
qualification matrix records this native O0/O2 distinction.

A single ordinary call can forward the entire tuple when natural result types
match exactly, it has the same one owned ordinal, and the producer/arguments pass
the closed-source proof. Arguments execute once and producer rebasing follows
them. Element-run variable-array producers retain qualified push-argument
support when constructing a separate owned ordinal. Function-value/dispatch tuple
forwarding and cross-kind whole-tuple adaptation remain separate extensions.

## Multiple owned results

Each owned ordinal has a 12-byte metadata record after the mailbox activation
word: original control, successful attempt start and target-entry cursor. Result
snapshots follow these records at their own alignments. Fixed-only and one-owner
mailboxes preserve their earlier layouts.

Every owned cursor is captured in a separate pass before evaluating any source
ordinal. Each destination then receives an independent private stage and
construction state, with publication disabled. Results evaluate left to right;
all snapshots and starts commit only after the attempt succeeds. Catch processes
each result in ordinal order, preserving pending throughout every owned landing
and abandoning cleanup. Replaced-owner recognition covers every terminal header.

Named receivers and anonymous result allocation provide distinct regions per
owned ordinal; exact forwarding preserves those channels. Repeated source owners
still construct independent destination copies. Staging adds activation bytes,
without adding a data-region lease or a recursive back-edge reservation.
Qualification covers scalar effects on both cursors, Grow/Frame combinations,
three heterogeneous owners, aliases, cancellation, nested replacement, generic
by-value copies, recursive forwarding and neighboring-region protection.
