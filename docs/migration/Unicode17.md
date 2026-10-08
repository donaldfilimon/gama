# Text and Unicode migration

The Zig text layer uses Unicode 17.0.0 extended grapheme clusters (UAX #29 revision 47). It includes Indic conjunct rule GB9c with all Unicode 17 Linker properties. Terminal width remains Gama's separately authored baseline policy; it does not become Unicode East Asian Width or an operating-system `wcwidth` call.

Compared with the pinned Swift baseline, segmentation changes in eight official GraphemeBreakTest vectors, rows **759–766**. These cover Myanmar, Balinese and Khmer conjuncts using linkers U+1039, U+1B44 and U+17D2. The new grouping can change cursor steps, deletion spans and hard wrapping for applications relying on the older splits. Unicode 17 grouping is intentional. Recorded baseline and Unicode boundaries are retained in [the first-party difference data](../../tests/unicode/data/swift-grapheme-differences.json); the original Swift parity fixtures are unchanged.

Control-key `isLetter` follows the first scalar's Alphabetic property. Lowercasing concatenates unconditional scalar mappings, including U+0130 → U+0069 U+0307, without contextual final sigma or locale tailoring. Generated tables use the pinned Swift Apple UCD inputs for control classification and casing, preserving the captured macOS baseline; grapheme properties use the official common Unicode 17 data. The input URL/version/hash ledger is [provenance.json](../../tests/unicode/data/provenance.json).

All UTF-8 text entrypoints reject malformed input with `InvalidUtf8` before returning clusters or allocating output. There is no replacement decoding or normalization. `Graphemes.init` validates the complete borrowed slice; the input must remain immutable and alive until iteration ends. Use initialization instead of manually constructing the iterator.

Editing uses signed grapheme offsets. Selection endpoints clamp independently before each operation; left/right move relative to the head and preserve a noncollapsed selection at a boundary. Inserting one cluster may join neighbouring clusters, while the returned cursor preserves the baseline arithmetic offset until the next operation clamps it. `acceptsCharacter` implements the editor's C0/DEL filter separately from pure insertion.

`Edit` and `Wrapped` own their returned allocations and must be deinitialized once with the allocator supplied to the operation. Input slices are borrowed, never mutated. On allocation failure there is no returned partial edit or wrapped result; callers retain their original value and cursor. Scalar property/mapping APIs expect validated Unicode scalars; foreign scalar translation must reject surrogates and out-of-range values before calling them.

Geometry and selection integers are explicit signed 64-bit values on every target, retaining the captured 64-bit baseline even on freestanding 32-bit targets. Stable `NodeID.child` uses the exact wrapping 64-bit baseline mix and accepts signed indices; explicit element identity replaces inherited identity.

`zig build unicode-check` checks input hashes and byte-exact table regeneration using the std-only offline generator. `zig build test` runs the text and generator suites in debug, safe and fast modes. Runtime oracle captures are historical qualification data; they do not imply runtime execution on a foreign platform.
