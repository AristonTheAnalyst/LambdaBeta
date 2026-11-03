import 'package:flutter/widgets.dart';

/// The identity a coach-mode surface acts as (2026-10-28).
///
/// Two people are always in play: the signed-in [authUserId] (the coach) and
/// the [ownerUserId] whose data is on screen (the athlete). Rows carry the
/// owner's `user_id`; writes carry the coach as `created_by_user_id`. The
/// athlete's own screens never see this object — it lives only inside the
/// coach-mode subtree, which is why it is an [InheritedWidget] and not a
/// process-wide notifier: the main tab shell stays mounted underneath and must
/// keep resolving the real signed-in user.
class ActingIdentity {
  const ActingIdentity({
    required this.authUserId,
    required this.ownerUserId,
    required this.createdByUserId,
    required this.ownerName,
    this.canDelete = false,
  });

  /// The signed-in account — the coach acting.
  final String authUserId;

  /// The athlete whose data is on screen. Passed as `userId:` to every
  /// repository and viewmodel.
  final String ownerUserId;

  /// Who put a row down: the coach. Rows written here get this value in
  /// `created_by_user_id`.
  final String createdByUserId;

  /// The athlete's display name, for the banner and copy.
  final String ownerName;

  /// Coach mode never deletes (2026-10-28) — the hard rail of the feature.
  final bool canDelete;

  /// Whether this identity acts for someone else (always true in coach mode).
  bool get isActingForOther => ownerUserId != authUserId;
}

/// Makes the [ActingIdentity] available to the coach-mode subtree.
///
/// Mounted by the coach-mode shell around its tabs, and repeated around any
/// pushed coach page that reads it. Outside coach mode [maybeOf] is null.
class CoachModeScope extends InheritedWidget {
  const CoachModeScope({
    super.key,
    required this.identity,
    required super.child,
  });

  final ActingIdentity identity;

  static ActingIdentity? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoachModeScope>()?.identity;

  @override
  bool updateShouldNotify(CoachModeScope oldWidget) =>
      oldWidget.identity != identity;
}
