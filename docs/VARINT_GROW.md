# Growable varint elements

Layout 12 extends sequential varint elements to standalone `varint[>..]`
owners. Their existing aligned 24-byte control stores a raw element base,
logical count and region limit. Physical cursor storage remains separate.
No length prefix is added to a Grow image and no fixed stride is invented.
GrowShrink/Limited variable elements and containing record/frame/enum forms
retain their pinned frontend or direct-target boundaries.

Push pins the receiver and encoded address, evaluates the i64 value, reserves
its complete canonical zigzag ULEB128 width, writes it and publishes length+1.
It returns the encoded reference. The frontend's no-resize rule prevents the
value initializer from growing that receiver. Existing references stay stable
across subsequent pushes and appends.

Append captures existing array/slice views and copies exact encoded elements.
Fresh literals, calls and control expressions instead construct directly in
the receiver's region with a private raw count/control. The receiver's logical
length changes only after success. The carrier keeps the producer's natural
array type so an exact function-value element-run request forwards through
callbacks. It leases no additional data region, including recursive forwarding.

Committed bytes survive canceled append even though its count does not commit.
Starting with `[64]`, interrupted append that wrote `1` leaves a length of 1; a later
push of 9 makes the logical view `[64,1]`, while the returned push reference points
to 9 farther in the physical suffix. Whole assignment resets the cursor before
RHS evaluation and literal construction publishes its count before elements.
Clear resets count and cursor without clearing old bytes. Surviving advertised
extents are checked on interruption using sequential walks.

Value-form Var results may write their prefix before an escape. A prefix left
inside raw elements can form an overlong encoding after later growth. Selected
dispatch arms and ordinary Value fallbacks with nonempty transitive `needs`
are therefore refused for raw/Grow destinations until that landing path is
qualified. Effect-free dispatch retains its natural narrow-width checks;
ordinary ER producers with fixed/scalar escapes remain admitted. Actual varint
Grow nonlocal targets remain refused across inline and emitted paths.

Named Grow returns conservatively check later owner observations and calls even
when returning the same candidate. This includes Grow-to-Var NRVO: later clear,
assignment or captured mutation can change the encoded image already handed
back. Simple named results, copies, parameters, ordinary/FV/dispatch results
and fixed-width Var conversions otherwise reuse their existing contracts.

Qualification covers selfappend, whole-slice/copy append, once-only zero fills,
references, source/receiver evaluation, live loops/rebinding, recursive append,
clear/assignment, and fixed-target cancellation. Byte checks cover raw cursor
sizes and nonminimal encoded append. Resource probes preserve a neighbor canary,
test complete-width exhaustion and repeat recursive/canceled append 10,000 times.
