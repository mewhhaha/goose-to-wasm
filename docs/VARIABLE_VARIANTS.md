# Standalone variable-size variant payloads

Standalone `E.Variant` values with a fixed prefix and one final variable or
runtime-limited array use the same owned record walker as structs. Final fields
may nest through other non-frame records to one terminal array. Each value has
one stable data region and a separate control object containing its prefixes and
ultimate tail header; ordinary fixed-copy paths still reject its descriptor.

Eligibility and layout inspect this variant's fields independently of its
siblings. A supported variable payload can therefore coexist with a growable
variant in the same enum. Nominal identity includes the enum instantiation,
variant and enclosing enum mode. Equal byte layouts never authorize a copy or
named binding between distinct nominal variants.

Construction visits fields in declaration order. Copies own independent tails
and preserve runtime capacity; fixed reference fields retain their referents.
Ordinary/inline/recursive calls, by-value parameters, mixed results and control
destinations use the owner ABI. Named returns alias the complete receiving record,
so later prefix/tail mutations remain visible in earlier variable results.
Prefix references address stable control storage and obey frontend lifetimes.

The frontend keeps whole nonresizable variants frozen; supported fixed fields
and runtime-limited tails may mutate. Resizable standalone variants, nonfinal or
multiple variable fields, variable elements, packed images and rendering remain
separate slices. Supported nonresizable payloads may also be embedded in `E..` through active-
variant image construction, direct result routing and tag-aware cleanup; see
[the enum contract](VARIABLE_ENUMS.md).
