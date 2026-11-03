/// One rename of an exercise, variation or workout (2026-10-29).
///
/// Written server-side by an `AFTER UPDATE` trigger on the dim's name column,
/// so it records every rename regardless of which client (or which coach's
/// account) made it. The owner reads their history and can restore a previous
/// name — a restore is just another rename, and it records itself.
class NameChange {
  const NameChange({
    required this.id,
    required this.userId,
    required this.entityType,
    required this.entityId,
    this.oldName,
    this.newName,
    this.changedByUserId,
    required this.changedAt,
  });

  final String id;

  /// Whose library the row belongs to — the history is the owner's.
  final String userId;

  /// `exercise` | `variation` | `workout`.
  final String entityType;
  final String entityId;
  final String? oldName;
  final String? newName;

  /// Who typed the rename: the owner, or a coach acting on their behalf.
  final String? changedByUserId;
  final DateTime changedAt;

  /// Whether [changedByUserId] is someone other than the owner.
  bool get byCoach =>
      changedByUserId != null && changedByUserId != userId;

  factory NameChange.fromMap(Map<String, dynamic> map) => NameChange(
    id: map['name_change_id'] as String,
    userId: map['user_id'] as String,
    entityType: map['entity_type'] as String,
    entityId: map['entity_id'] as String,
    oldName: map['old_name'] as String?,
    newName: map['new_name'] as String?,
    changedByUserId: map['changed_by_user_id'] as String?,
    changedAt: DateTime.parse(map['changed_at'] as String).toLocal(),
  );
}
