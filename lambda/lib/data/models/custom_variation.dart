class CustomVariation {
  const CustomVariation({
    required this.variationId,
    required this.userId,
    required this.name,
    required this.isActive,
  });

  final String variationId;
  final String userId;
  final String name;
  final bool isActive;

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

  Map<String, dynamic> toMap() => {
        'custom_variation_id': variationId,
        'user_id': userId,
        'variation_name': name,
        'is_active': isActive,
      };
}
