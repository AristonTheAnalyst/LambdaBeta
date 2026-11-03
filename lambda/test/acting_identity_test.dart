import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/coach/model/acting_identity.dart';

/// Coach mode's identity is a SUBTREE scope (2026-10-28).
///
/// The main tab shell stays mounted under coach mode; a process-wide acting
/// user would silently repoint the coach's own screens. These tests pin the
/// two halves of that contract: inside the scope the athlete is the owner and
/// the coach is the author, and outside it nothing is visible at all.
void main() {
  const identity = ActingIdentity(
    authUserId: 'coach',
    ownerUserId: 'athlete',
    createdByUserId: 'coach',
    ownerName: 'Natasha',
  );

  testWidgets('the scope is visible inside and invisible outside', (
    tester,
  ) async {
    ActingIdentity? inside;
    ActingIdentity? outside;

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Builder(
              builder: (context) {
                outside = CoachModeScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
            CoachModeScope(
              identity: identity,
              child: Builder(
                builder: (context) {
                  inside = CoachModeScope.maybeOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );

    expect(outside, isNull, reason: 'the coach’s own screens stay their own');
    expect(inside?.ownerUserId, 'athlete');
    expect(inside?.authUserId, 'coach');
    expect(inside?.createdByUserId, 'coach');
    expect(inside?.ownerName, 'Natasha');
  });

  test('coach mode can never delete', () {
    expect(identity.canDelete, isFalse);
    expect(identity.isActingForOther, isTrue);
  });
}
