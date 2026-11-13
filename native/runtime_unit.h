/* Follows the runtime body in the runtime unit (units.h's G_RUNTIME_UNIT):
   what storage.h and pools.h in a program unit read of the body's private
   region registry and span freelists. */
GS_API size_t g_runtime_region_usable(void) { return gs_regions[gs_nregions-1].usable; }
GS_API long g_runtime_region_count(void) { return gs_nregions; }
GS_API int64_t g_runtime_span_depth(void) { return GS_SPAN_DEPTH; }
