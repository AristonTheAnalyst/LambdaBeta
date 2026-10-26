import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/athlete.dart';

/// The roster's model (2026-10-26): the name it draws and the consent date
/// it reads.
void main() {
  group('Athlete', () {
    test('draws the athlete\'s full name, trimmed', () {
      const athlete = Athlete(
        userId: 'a1',
        firstName: '  Jamie ',
        lastName: ' Rivera ',
      );
      expect(athlete.displayName, 'Jamie Rivera');
    });

    test('draws one name when the other is missing or blank', () {
      expect(
        const Athlete(userId: 'a1', firstName: 'Jamie').displayName,
        'Jamie',
      );
      expect(
        const Athlete(userId: 'a1', lastName: 'Rivera').displayName,
        'Rivera',
      );
      expect(
        const Athlete(userId: 'a1', firstName: '  ', lastName: '').displayName,
        'Athlete',
      );
    });

    test('reads the watch row: ids, names and the two dates', () {
      final athlete = Athlete.fromMap({
        'athlete_user_id': 'a1',
        'user_name': 'Jamie',
        'user_lastname': 'Rivera',
        'created_date': '2026-10-01T09:00:00.000Z',
        'accepted_date': '2026-10-02T10:30:00.000Z',
      });
      expect(athlete.userId, 'a1');
      expect(athlete.displayName, 'Jamie Rivera');
      expect(athlete.createdDate, DateTime.utc(2026, 10, 1, 9));
      expect(athlete.acceptedDate, DateTime.utc(2026, 10, 2, 10, 30));
    });

    test('an unaccepted invitation has no acceptance date', () {
      final athlete = Athlete.fromMap({
        'athlete_user_id': 'a1',
        'user_name': null,
        'user_lastname': null,
        'created_date': '2026-10-01T09:00:00.000Z',
      });
      expect(athlete.acceptedDate, isNull);
      expect(athlete.displayName, 'Athlete');
    });

    test('round-trips through the map', () {
      final athlete = Athlete(
        userId: 'a1',
        firstName: 'Jamie',
        lastName: 'Rivera',
        createdDate: DateTime.utc(2026, 10, 1, 9),
        acceptedDate: DateTime.utc(2026, 10, 2, 10, 30),
      );
      final round = Athlete.fromMap(athlete.toMap());
      expect(round.userId, athlete.userId);
      expect(round.displayName, athlete.displayName);
      expect(round.createdDate, athlete.createdDate);
      expect(round.acceptedDate, athlete.acceptedDate);
    });
  });
}
