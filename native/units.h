/* Translation units of one generated program. Compiled as it is, the file is
   a single unit holding the runtime and the whole program, every definition
   static. The same file also builds as several units that link together:

   - G_RUNTIME_UNIT: only the runtime body, in runtime.h's GS_RUNTIME_OBJECT
     configuration (external linkage, thread support), plus runtime_unit.h.
     It depends on the compiler that emitted the file, never on the program;
     the text before the #else line commented "program units" compiles it
     alone.
   - G_UNITS=n with G_UNIT=k below n: program unit k, linked with the runtime
     unit. Program functions, g_initialize and main are dealt out in
     G_SLICES contiguous slices of roughly equal emitted bytes; unit k
     compiles those of slices s with s*n/G_SLICES == k (G_IN_UNIT). Unit 0
     defines the program's mutable state (G_SHARED), which the other units
     declare. With n > 1, a program function named from another unit has
     hidden external linkage (G_FN); the rest stay static (G_LOCAL), as
     everything does with n == 1. A small function named from other units is
     instead compiled, static, in every unit from the first to the last that
     names it (G_IN_SPAN), so callers there can inline it. Per-type helpers
     and other stateless static code are compiled in every unit using them.

   Guards and links name a function's slice and the first and last slices it
   is named from. */
#define G_SLICES 840
#ifdef G_RUNTIME_UNIT
#define GS_RUNTIME_OBJECT 1
#define GS_SEPARATE_RUNTIME 1
#define GS_NEED_THREADS 1
#elif defined(G_UNITS)
#if !defined(G_UNIT) || G_UNITS < 1 || G_UNIT < 0 || G_UNIT >= G_UNITS
#error "G_UNITS needs a G_UNIT from 0 below it"
#endif
#define GS_SEPARATE_RUNTIME 1
#endif
#if defined(G_UNITS) && G_UNITS > 1
#define G_SPLIT 1
#define G_UNIT_OF(slice) ((slice)*G_UNITS/G_SLICES)
#define G_IN_UNIT(slice,first,last) (G_UNIT_OF(slice)==G_UNIT)
#define G_IN_SPAN(slice,first,last) (G_UNIT_OF(first)<=G_UNIT && G_UNIT<=G_UNIT_OF(last))
#define G_LOCAL(slice,first,last) (G_UNIT_OF(first)==G_UNIT_OF(slice) && G_UNIT_OF(last)==G_UNIT_OF(slice))
#define G_FN __attribute__((visibility("hidden")))
#if G_UNIT == 0
#define G_SHARED __attribute__((visibility("hidden")))
#define G_INIT(value) =value
#else
#define G_SHARED extern __attribute__((visibility("hidden")))
#define G_INIT(value)
#endif
#else
#define G_SPLIT 0
#define G_IN_UNIT(slice,first,last) 1
#define G_IN_SPAN(slice,first,last) 1
#define G_LOCAL(slice,first,last) 1
#define G_FN static
#define G_SHARED static
#define G_INIT(value) =value
#endif
