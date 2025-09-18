// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sautify';

  @override
  String get homeTitle => 'Home';

  @override
  String get libraryTitle => 'Library';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get searchHint => 'Search songs, artists, albums';

  @override
  String get nowPlaying => 'Now Playing';

  @override
  String songsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# songs',
      one: '# song',
    );
    return '$_temp0';
  }

  @override
  String get downloaded => 'Downloaded';

  @override
  String get offline => 'Offline';

  @override
  String get error => 'Error';

  @override
  String get retry => 'Retry';
}
