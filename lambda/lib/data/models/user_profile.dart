class UserProfile {
  final String userId;
  final String? userName;
  final String? userLastname;
  final DateTime? userDateOfBirth;
  final String? userGender;
  final double? userHeightCm;
  final double? userWeightKg;
  final bool onboarded;
  final DateTime? userDateCreated;

  const UserProfile({
    required this.userId,
    this.userName,
    this.userLastname,
    this.userDateOfBirth,
    this.userGender,
    this.userHeightCm,
    this.userWeightKg,
    required this.onboarded,
    this.userDateCreated,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] as String,
      userName: json['user_name'] as String?,
      userLastname: json['user_lastname'] as String?,
      userDateOfBirth: json['user_date_of_birth'] != null
          ? DateTime.tryParse(json['user_date_of_birth'] as String)
          : null,
      userGender: json['user_gender'] as String?,
      userHeightCm: _toDouble(json['user_height_cm']),
      userWeightKg: _toDouble(json['user_weight_kg']),
      onboarded: _toBool(json['onboarded']),
      userDateCreated: json['user_date_created'] != null
          ? DateTime.tryParse(json['user_date_created'] as String)
          : null,
    );
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  UserProfile copyWith({
    String? userName,
    String? userLastname,
    DateTime? userDateOfBirth,
    String? userGender,
    double? userHeightCm,
    double? userWeightKg,
    bool? onboarded,
    bool clearDob = false,
    bool clearGender = false,
  }) =>
      UserProfile(
        userId: userId,
        userName: userName ?? this.userName,
        userLastname: userLastname ?? this.userLastname,
        userDateOfBirth: clearDob ? null : (userDateOfBirth ?? this.userDateOfBirth),
        userGender: clearGender ? null : (userGender ?? this.userGender),
        userHeightCm: userHeightCm ?? this.userHeightCm,
        userWeightKg: userWeightKg ?? this.userWeightKg,
        onboarded: onboarded ?? this.onboarded,
        userDateCreated: userDateCreated,
      );

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'user_name': userName,
      'user_lastname': userLastname,
      'user_date_of_birth': userDateOfBirth?.toIso8601String().split('T').first,
      'user_gender': userGender,
      'user_height_cm': userHeightCm,
      'user_weight_kg': userWeightKg,
      'onboarded': onboarded,
    };
  }
}
