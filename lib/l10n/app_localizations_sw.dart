// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swahili (`sw`).
class AppLocalizationsSw extends AppLocalizations {
  AppLocalizationsSw([String locale = 'sw']) : super(locale);

  @override
  String get appTitle => 'Sautify';

  @override
  String get homeTitle => 'Nyumbani';

  @override
  String get libraryTitle => 'Maktaba';

  @override
  String get settingsTitle => 'Mipangilio';

  @override
  String get searchHint => 'Tafuta nyimbo, wasanii, albamu';

  @override
  String get nowPlaying => 'Inachezwa sasa';

  @override
  String songsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# nyimbo',
      one: '# wimbo',
    );
    return '$_temp0';
  }

  @override
  String get downloaded => 'Imepakuliwa';

  @override
  String get offline => 'Nje ya mtandao';

  @override
  String get error => 'Hitilafu';

  @override
  String get retry => 'Jaribu tena';
}
