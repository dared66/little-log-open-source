import 'dart:convert';

// Synthetic fixture matching the previously verified Nara JSON export.
String naraExportFixture() => jsonEncode({
  'profile': {
    'name': 'Robin',
    'birthDate': '2026-01-01',
    'gender': 'FEMALE',
    'nightBeginEnd': '19:00,07:00',
  },
  'tracks': {
    'd': {
      'type': 'DIAPER',
      'beginDt': 1768000000000,
      'childKey': 'child',
      'createUserKey': 'a',
      'diaperTypePee': true,
      'diaperTypePoop': true,
      'diaperTypeDry': false,
      'diaperPoopColor': 'BLACK GREEN',
      'diaperPoopTexture': 'MUSH RUN',
    },
    'n': {
      'type': 'FEED',
      'feedType': 'BREAST',
      'beginDt': 1768000010000,
      'childKey': 'child',
      'createUserKey': 'b',
      'breastLeftDuration': 600123,
      'breastRightDuration': 300000,
    },
    'b': {
      'type': 'FEED',
      'feedType': 'BOTTLE',
      'beginDt': 1768000020000,
      'childKey': 'child',
      'createUserKey': 'a',
      'bottleVolumeNum': 25,
      'bottleVolumeExp': 1,
      'bottleVolumeUnit': 'FLOZ',
      'bottleTypeBreastMilk': true,
      'bottleTypeFormula': false,
    },
  },
});
