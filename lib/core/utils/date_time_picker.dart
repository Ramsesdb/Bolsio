import 'package:flutter/material.dart';

final DateTime kDefaultFirstSelectableDate = DateTime(1700);
final DateTime kDefaultLastSelectableDate = DateTime(2199);

Future<DateTime?> openDateTimePicker(
  BuildContext context, {
  required bool showTimePickerAfterDate,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  DatePickerMode initialDatePickerMode = DatePickerMode.day,
  TimePickerEntryMode initialTimeEntryMode = TimePickerEntryMode.dial,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendar,
}) async {
  firstDate ??= kDefaultFirstSelectableDate;
  lastDate ??= kDefaultLastSelectableDate;

  if (initialDate != null) {
    if (initialDate.isBefore(firstDate)) {
      initialDate = firstDate;
    } else if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }
  }

  DateTime? pickedDate = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    initialDatePickerMode: initialDatePickerMode,
    initialEntryMode: initialEntryMode,
    lastDate: lastDate,
  );

  if (pickedDate == null || !showTimePickerAfterDate) return pickedDate;

  // Use initialDate when available; otherwise fall back to the date
  // the user just picked (or midnight) to avoid a null dereference
  // when the caller didn't provide an initialDate
  // (e.g. the "Rastrear desde" field).
  final timeSource = initialDate ?? pickedDate;
  final timePicked = await showTimePicker(
    context: context,
    initialEntryMode: initialTimeEntryMode,
    initialTime: TimeOfDay(
      hour: timeSource.hour,
      minute: timeSource.minute,
    ),
  );

  if (timePicked == null) return null;

  return pickedDate.copyWith(
    hour: timePicked.hour,
    minute: timePicked.minute,
  );
}
