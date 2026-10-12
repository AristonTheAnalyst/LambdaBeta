import 'package:flutter/material.dart';
import 'date_picker_sheet.dart';

/// Opens the date-of-birth picker: the app's calendar, bounded to the past.
///
/// Thin by design — the calendar and the sheet live in [showDatePickerSheet],
/// which every date field in the app now goes through. What stays here is the
/// one thing that is actually about birth dates: the range. A birth date cannot
/// be in the future, and 1900 is as far back as the data is worth trusting.
Future<DateTime?> showDateOfBirthPicker(
  BuildContext context, {
  required DateTime? initial,
}) {
  final now = DateTime.now();
  return showDatePickerSheet(
    context,
    initial: initial,
    firstDate: DateTime(1900, 1, 1),
    lastDate: DateTime(now.year, now.month, now.day),
    title: 'DATE OF BIRTH',
  );
}
