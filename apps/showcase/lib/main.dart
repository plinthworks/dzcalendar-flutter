import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';

// For screenshots made again exactly (all optional):
//   --dart-define=TODAY=2026-11-11 (the clock frozen at 10:20 that day)
//   --dart-define=LOCALE=ar  --dart-define=DARK=true  --dart-define=ZONE=Asia/Tokyo
//   --dart-define=VIEW=dayGridMonth  --dart-define=SHOT=tap:Piscine (see shots.dart)
//   --dart-define=HIJRI=beside (or main)
const _today = String.fromEnvironment('TODAY');
const _locale = String.fromEnvironment('LOCALE', defaultValue: 'fr');
const _zone = String.fromEnvironment('ZONE', defaultValue: 'Africa/Algiers');
const _dark = bool.fromEnvironment('DARK');
const _view = String.fromEnvironment('VIEW');
const _shot = String.fromEnvironment('SHOT');
const _hijri = String.fromEnvironment('HIJRI');

void main() => runApp(
  ShowcaseApp(
    today: PlainDate.tryParse(_today),
    view: _view.isEmpty ? null : _view,
    shot: _shot,
    settings: Settings(
      locale: Locale(_locale),
      zone: isValidZone(_zone) ? _zone : 'Africa/Algiers',
      mode: _dark ? ThemeMode.dark : ThemeMode.system,
      hijri: HijriMode.values.where((m) => m.name == _hijri).firstOrNull ?? HijriMode.off,
    ),
  ),
);
