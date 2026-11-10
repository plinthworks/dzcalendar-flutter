import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home.dart';
import 'strings.dart';

/// What the person sets for the whole app.
class Settings extends ChangeNotifier {
  Settings({this.locale = const Locale('fr'), this.zone = 'Africa/Algiers', this.mode = ThemeMode.system});

  Locale locale;
  ZoneId zone;
  ThemeMode mode;

  static const zones = ['Africa/Algiers', 'Europe/Paris', 'America/Montreal', 'Asia/Tokyo'];
  static const locales = [Locale('fr'), Locale('en'), Locale('ar')];

  void update({Locale? locale, ZoneId? zone, ThemeMode? mode}) {
    this.locale = locale ?? this.locale;
    this.zone = zone ?? this.zone;
    this.mode = mode ?? this.mode;
    notifyListeners();
  }
}

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key, this.settings, this.today, this.view, this.shot});

  /// For tests and screenshots: given settings, a frozen day, a view, a gesture.
  final Settings? settings;
  final PlainDate? today;
  final String? view;
  final String? shot;

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  late final Settings _settings = widget.settings ?? Settings();

  @override
  void dispose() {
    if (widget.settings == null) _settings.dispose();
    super.dispose();
  }

  static ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C66), brightness: b);
    return ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1, thickness: 1),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => S.of(context).appTitle,
      locale: _settings.locale,
      supportedLocales: Settings.locales,
      localizationsDelegates: const [
        DzCalendarLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _settings.mode,
      home: HomePage(settings: _settings, today: widget.today, view: widget.view, shot: widget.shot),
    ),
  );
}
