// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Amharic (`am`).
class AppLocalizationsAm extends AppLocalizations {
  AppLocalizationsAm([String locale = 'am']) : super(locale);

  @override
  String get appTitle => 'Sautify';

  @override
  String get homeTitle => 'መነሻ';

  @override
  String get libraryTitle => 'ቤተ-መጽሐፍት';

  @override
  String get settingsTitle => 'ቅንብሮች';

  @override
  String get searchHint => 'ዘፈኖችን ፣ አርቲስቶችን ፣ አልበሞችን ይፈልጉ ።';

  @override
  String get nowPlaying => 'አሁን መጫወት';

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
  String get downloaded => 'ይዘው ወደ ውስጥ ይገኛሉ';

  @override
  String get offline => 'ውስጥ';

  @override
  String get error => 'ስህተት';

  @override
  String get retry => 'ይሞክሩ';
}
