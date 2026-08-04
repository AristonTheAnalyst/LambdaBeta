class CustomVariation {
  const CustomVariation({
    required this.variationId,
    required this.userId,
    required this.name,
    required this.isActive,
    this.lastUsed,
  });

  final String variationId;
  final String userId;
  final String name;
  final bool isActive;

  /// Most recent workout date this variation appeared in, if any — used to
  /// order variation lists/pickers by "most recently used".
  final DateTime? lastUsed;

  factory CustomVariation.fromMap(Map<String, dynamic> map) => CustomVariation(
        variationId: map['custom_variation_id'] as String,
        userId: map['user_id'] as String,
        name: map['variation_name'] as String,
        isActive: _toBool(map['is_active']),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return true;
  }

  /// Comparator: most recently used first (nulls last, then name).
  static int byRecency(CustomVariation a, CustomVariation b) {
    final da = a.lastUsed;
    final db = b.lastUsed;
    if (da != null && db != null) return db.compareTo(da);
    if (da != null) return -1;
    if (db != null) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  CustomVariation copyWith({DateTime? lastUsed}) => CustomVariation(
        variationId: variationId,
        userId: userId,
        name: name,
        isActive: isActive,
        lastUsed: lastUsed ?? this.lastUsed,
      );

  Map<String, dynamic> toMap() => {
        'custom_variation_id': variationId,
        'user_id': userId,
        'variation_name': name,
        'is_active': isActive,
      };
}
