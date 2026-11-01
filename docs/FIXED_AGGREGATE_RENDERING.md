# Closed fixed aggregate rendering

`print` renders fixed structs, standalone variants, fixed enums and arrays or
slices whose elements recursively contain only fixed scalar/aggregate values.
These closed values contain no references or slices. Nominal struct names use
the pinned type dump, variants use positional payload literals, fieldless
variants use `Enum.Case`, and explicit pads produce no fields. One- and two-byte
enum tags select only their active payload.

Top-level byte sequences retain raw byte output. Nested byte arrays quote their
contents and escape exactly quote, backslash, newline, carriage return and tab.
Other bytes, including invalid UTF-8 and NUL, pass through unchanged. Contiguous
unescaped spans use one host write rather than one allocation per byte.

Arguments keep the existing eager capture contract: closed fixed values copy
their complete storage; slices and region arrays copy the captured element run.
Later argument writes cannot change an earlier argument's text. This matches
native rendering before later argument evaluation when no user formatter is
involved; nested prints still finish before the outer line is emitted. Scratch
snapshots release on statement cleanup and acquire no data region.

The scalar host ABI and image layout remain unchanged. Numeric fields reuse
the qualified scalar formatting paths. Aggregates containing references/slices,
variable records/enums, optional references and user formatters retain explicit
gates until recursive snapshots and formatter effects are qualified.

Native oracles cover generics, empty values, packed/padded records, nested
arrays, compact and two-byte enum tags, floats, parameters/FVs and mutation
ordering. A binary-output comparison checks arbitrary byte values directly
against native C on both engines. Resource checks repeat 2 KiB snapshots 10,000
times and preserve a neighboring region canary.
