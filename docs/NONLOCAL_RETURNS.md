# Nonlocal return effects

Out-of-line `return ... from` and captured callback returns support targets whose
result types have fixed size, including scalars, references/slices, fixed
aggregates and mixed/multiple fixed results. Existing frontend lifetime checks
still apply. Owned target results produce a staging/landing diagnostic.

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

Owned targets are the next extension. The native emitter constructs an escape
value behind abandoned result data and lands it at the target catch. Writing
directly into the old receiving header can change values read by later return
expressions. Mixed owned results also expose optimizer-dependent ordering that
must be qualified explicitly; ordinary caller-result channels alone do not solve
this lifetime and alias contract.
