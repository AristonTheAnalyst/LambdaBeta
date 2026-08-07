/// Case-insensitive first-free-name helper.
///
/// Returns [base] (trimmed) if no name in [existing] matches it (casing
/// ignored). Otherwise returns the smallest-free numbered variant:
/// `uniqueName('New Program', {'New Program'})` → `'New Program 2'`.
/// If a later variant exists without an earlier one (e.g. only "Base 3"),
/// the free slot is still taken — smallest-free, matching Finder/Explorer
/// and the historical bump loops exactly.
///
/// [numbered] overrides the suffix format for variants ≥ 2. Copy call sites
/// pass `(n) => '${source.name} (Copy $n)'` so a duplicate is "X (Copy 2)",
/// never "X (Copy) 2".
///
/// Uniqueness here is a client-side data-entry convenience only, enforced
/// against the local mirror — names are deliberately NOT unique at the
/// database level, so synced duplicates are possible and are accepted as
/// cosmetic (records are keyed by UUID, never by name).
String uniqueName(
  String base,
  Set<String> existing, {
  String Function(int n)? numbered,
}) {
  final trimmedBase = base.trim();
  final fmt = numbered ?? (int n) => '$trimmedBase $n';
  final lower = existing.map((e) => e.trim().toLowerCase()).toSet();
  if (!lower.contains(trimmedBase.toLowerCase())) return trimmedBase;
  for (var n = 2;; n++) {
    final c = fmt(n);
    if (!lower.contains(c.trim().toLowerCase())) return c;
  }
}
