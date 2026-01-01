/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:navigation_bar_m3e/navigation_bar_m3e.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sautifyv2/blocs/audio_player_cubit.dart';
import 'package:sautifyv2/blocs/device_library/device_library_cubit.dart';
import 'package:sautifyv2/blocs/download/download_cubit.dart';
import 'package:sautifyv2/blocs/home/home_cubit.dart';
import 'package:sautifyv2/blocs/library/library_cubit.dart';
import 'package:sautifyv2/blocs/player/player_cubit.dart';
import 'package:sautifyv2/blocs/search/search_bloc.dart';
import 'package:sautifyv2/blocs/settings/settings_cubit.dart';
import 'package:sautifyv2/blocs/settings/settings_state.dart';
import 'package:sautifyv2/blocs/theme/theme_cubit.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/db/continue_listening_store.dart';
import 'package:sautifyv2/db/metadata_overrides_store.dart';
// flutter_localizations are included via AppLocalizations.localizationsDelegates
import 'package:sautifyv2/l10n/app_localizations.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/dio_client.dart';
import 'package:sautifyv2/services/widget_service.dart';
import 'package:sautifyv2/widgets/mini_player.dart';

import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'services/image_cache_service.dart';
import 'utils/app_config.dart';
import 'utils/http_overrides.dart';
import 'utils/restart_widget.dart';

Future<void> _requestNotificationPermissionIfNeeded() async {
  final status = await Permission.notification.status;
  final storage = await Permission.storage.status;
  if (storage.isDenied || storage.isRestricted) {
    await Permission.storage.request();
  }
  if (status.isDenied || status.isRestricted) {
    await Permission.notification.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DioClient
  await DioClient.init();

  HttpOverrides.global = MyHttpOverrides();

  // Workaround: Suppress noisy debug-only MouseTracker assertion during warm-up frames/hot reload
  // See: https://github.com/flutter/flutter/issues (various reports around mouse_tracker.dart !_debugDuringDeviceUpdate)
  _installMouseTrackerAssertWorkaround();

  // Init Hive early for local storage
  if (!AppConfig.isTest) {
    await Hive.initFlutter();
  }

  // Open app-wide local stores
  await MetadataOverridesStore.ensureReady();
  await ContinueListeningStore.ensureReady();

  // Configure and register memory pressure handling for images
  final imgCacheSvc = ImageCacheService();
  imgCacheSvc.configure(maxBytes: 20 * 1024 * 1024); // ~20MB cap
  imgCacheSvc.registerMemoryPressureListener();

  // Also cap Flutter's built-in ImageCache to limit decoded frames in memory
  PaintingBinding.instance.imageCache
    ..maximumSize = 100 // max number of images+
    ..maximumSizeBytes = 30 * 1024 * 1024; // ~30MB decoded bytes

  // Request runtime permission for notifications on Android 13+
  if (!AppConfig.isTest) {
    await _requestNotificationPermissionIfNeeded();
  }

  // Initialize background audio notifications/controls
  if (!AppConfig.isTest) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.sautify.playback',
      androidNotificationChannelName: 'Sautify Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      preloadArtwork: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    );
  }

  // Load settings to decide audio backend before creating any AudioPlayer
  final settingsCubit = SettingsCubit();
  await settingsCubit.init();

  // Initialize the AudioPlayerService singleton
  final audioService = AudioPlayerService();
  await audioService.initialize();

  // Initialize Widget Service
  if (!AppConfig.isTest) {
    WidgetService().init();
  }

  runApp(RestartWidget(child: MainApp(settingsCubit: settingsCubit)));
}

// Filters a specific, known-to-be-benign debug assertion spam from MouseTracker
// that can occur around warm-up frames/hot reload. This does not affect release
// builds and only filters the exact assertion, letting all other errors through.
void _installMouseTrackerAssertWorkaround() {
  if (kReleaseMode) return; // Only in debug/profile

  final prev = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    final isMouseTrackerSpam = text.contains('mouse_tracker.dart') &&
        text.contains("'!_debugDuringDeviceUpdate': is not true");
    if (isMouseTrackerSpam) {
      // Log once per occurrence at a low priority instead of throwing
      debugPrint(
        'Suppressed MouseTracker debug assertion during warm-up frame: ${details.exception}',
      );
      return;
    }
    prev?.call(details);
  };
}

class MainApp extends StatefulWidget {
  final SettingsCubit settingsCubit;
  const MainApp({super.key, required this.settingsCubit});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _tab = 0;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void _safeToast({
    required String title,
    String? description,
    Color? backgroundColor,
    Color? textColor,
  }) {
    if (!mounted) return;

    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor ?? Colors.white,
              ),
            ),
            if (description != null)
              Text(
                description,
                style: TextStyle(color: textColor ?? Colors.white),
              ),
          ],
        ),
        backgroundColor: backgroundColor ?? Colors.black87,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkConnectivityOnLaunch();
    _watchConnectivity();
  }

  Future<void> _checkConnectivityOnLaunch() async {
    // Small delay to ensure context is ready
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final results = await Connectivity().checkConnectivity();
      final isOffline =
          results.isEmpty || results.every((c) => c == ConnectivityResult.none);
      if (isOffline && mounted) {
        _safeToast(
          title: 'You are offline',
          description: 'Some features may not work without internet',
          backgroundColor: Colors.orange,
        );
      }
    } on MissingPluginException catch (_) {
      // Happens after a hot restart when a new plugin was added.
      // Avoid crashing; plugin will be available after a full restart.
      debugPrint('connectivity_plus not registered yet (hot restart).');
    } catch (e, st) {
      debugPrint('Connectivity check failed: $e\n$st');
    }
  }

  void _watchConnectivity() {
    try {
      _connSub = Connectivity().onConnectivityChanged.listen((
        List<ConnectivityResult> results,
      ) {
        if (!mounted) return;
        final offline = results.isEmpty ||
            results.every((c) => c == ConnectivityResult.none);
        if (offline) {
          _safeToast(
            title: 'No internet connection',
            description: 'You are offline',
            backgroundColor: Colors.redAccent,
          );
        }
      });
    } on MissingPluginException catch (_) {
      debugPrint('connectivity_plus stream not available (hot restart).');
    } catch (e, st) {
      debugPrint('Connectivity subscription failed: $e\n$st');
    }
  }

  Locale? _toLocale(String? code) {
    if (code == null || code.isEmpty) return null;
    final parts = code.split('-');
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts[1]);
  }

  TextTheme _buildAppTextTheme(BuildContext context, String fontKey) {
    final base = ThemeData(brightness: Brightness.dark)
        .textTheme
        .apply(bodyColor: txtcolor, displayColor: txtcolor);

    switch (fontKey) {
      case 'system':
        return base;
      case 'inter':
        return GoogleFonts.interTextTheme(base);
      case 'roboto':
        return GoogleFonts.robotoTextTheme(base);
      case 'dm_sans':
        return GoogleFonts.dmSansTextTheme(base);
      case 'manrope':
        return GoogleFonts.manropeTextTheme(base);
      case 'noto_sans':
        return GoogleFonts.notoSansTextTheme(base);
      case 'poppins':
      default:
        return GoogleFonts.poppinsTextTheme(base);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const LibraryScreen(),
      const DownloadsScreen(),
      const SettingsScreen(),
    ];

    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: widget.settingsCubit),
        BlocProvider<LibraryCubit>(
          create: (_) => LibraryCubit()..init(),
        ),
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<AudioPlayerCubit>(
          create: (_) => AudioPlayerCubit(AudioPlayerService()),
        ),
        BlocProvider<DeviceLibraryCubit>(
          create: (_) => DeviceLibraryCubit()..init(),
        ),
        BlocProvider<SearchBloc>(create: (_) => SearchBloc()),
        BlocProvider<HomeCubit>(create: (_) => HomeCubit()),
        BlocProvider<DownloadCubit>(
          create: (_) => DownloadCubit(widget.settingsCubit)..init(),
        ),
        BlocProvider<PlayerCubit>(
          create: (context) => PlayerCubit(context.read<ThemeCubit>()),
        ),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settings) {
          // Logic to determine if we should use dynamic theme
          Color? seedColor;
          if (settings.dynamicThemeEnabled) {
            // Only watch ThemeCubit if enabled
            final themeState = context.watch<ThemeCubit>().state;
            if (themeState.primaryColors.isNotEmpty) {
              seedColor = themeState.primaryColors[0];
            }
          }

          final bool useDynamic =
              settings.dynamicThemeEnabled && seedColor != null;

          final ThemeData theme;
          final appTextTheme = _buildAppTextTheme(context, settings.appFont);
          if (useDynamic) {
            theme = ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: Brightness.dark,
                primary: seedColor,
              ),
              textTheme: appTextTheme,
              snackBarTheme: SnackBarThemeData(
                backgroundColor: seedColor,
                elevation: 8.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                behavior: SnackBarBehavior.floating,
                contentTextStyle: TextStyle(
                  color: txtcolor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                },
              ),
            );
          } else {
            // Existing static theme
            theme = ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: appbarcolor,
                brightness: Brightness.dark,
                surface: bgcolor,
              ),
              scaffoldBackgroundColor: bgcolor,
              appBarTheme: AppBarTheme(
                backgroundColor: bgcolor,
                elevation: 0,
                iconTheme: IconThemeData(color: iconcolor),
              ),
              textTheme: appTextTheme,
              snackBarTheme: SnackBarThemeData(
                backgroundColor: appbarcolor,
                elevation: 8.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                behavior: SnackBarBehavior.floating,
                contentTextStyle: TextStyle(
                  color: txtcolor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                },
              ),
            );
          }

          return MaterialApp(
            scaffoldMessengerKey: _scaffoldMessengerKey,
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
            theme: theme,
            locale: _toLocale(settings.localeCode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (innerCtx) {
                final l10n = AppLocalizations.of(innerCtx);

                // Adapt colors based on mode
                final scaffoldBg = useDynamic ? null : bgcolor;
                final navIndicatorColor = useDynamic
                    ? Theme.of(innerCtx).colorScheme.secondaryContainer
                    : appbarcolor.withAlpha(100);
                final navBgColor = useDynamic
                    ? Theme.of(innerCtx).colorScheme.surface
                    : bgcolor;

                return Scaffold(
                  backgroundColor: scaffoldBg,
                  bottomNavigationBar: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Global Mini Player always shown above the bottom nav bar
                      const MiniPlayer(),
                      // Disable ripple/highlight specifically for the bottom nav bar
                      Theme(
                        data: Theme.of(innerCtx).copyWith(
                          splashFactory: NoSplash.splashFactory,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                        ),
                        child: NavigationBarM3E(
                          padding: EdgeInsets.all(8.0),
                          labelBehavior: NavBarM3ELabelBehavior.alwaysShow,
                          indicatorStyle: NavBarM3EIndicatorStyle.pill,
                          size: NavBarM3ESize.small,
                          shapeFamily: NavBarM3EShapeFamily.square,
                          indicatorColor: navIndicatorColor,
                          backgroundColor: navBgColor,
                          selectedIndex: _tab,
                          onDestinationSelected: (i) =>
                              setState(() => _tab = i),

                          /*
                            type: BottomNavigationBarType.fixed,
                            currentIndex: _tab,
                            onTap: (i) => setState(() => _tab = i),
                            backgroundColor: cardcolor.withAlpha(200),
                            selectedItemColor: appbarcolor.withValues(
                              alpha: 50,
                            ),
                            unselectedItemColor: iconcolor.withValues(
                              alpha: 100,
                            ),
                            selectedLabelStyle: TextStyle(
                              color: appbarcolor,
                              fontWeight: FontWeight.bold,
                            ),
                            unselectedLabelStyle: TextStyle(
                              color: iconcolor.withValues(alpha: 100),
                            ),*/
                          destinations: [
                            NavigationDestinationM3E(
                              icon: Icon(Icons.home_rounded, color: iconcolor),
                              selectedIcon: Icon(
                                Icons.home,
                                color: useDynamic
                                    ? Theme.of(innerCtx).colorScheme.primary
                                    : appbarcolor,
                              ),
                              label: l10n.homeTitle,
                            ),
                            NavigationDestinationM3E(
                              icon: Icon(
                                Icons.library_music_rounded,
                                color: iconcolor,
                              ),
                              selectedIcon: Icon(
                                Icons.library_music,
                                color: useDynamic
                                    ? Theme.of(innerCtx).colorScheme.primary
                                    : appbarcolor,
                              ),
                              label: l10n.libraryTitle,
                            ),
                            NavigationDestinationM3E(
                              icon: Icon(
                                Icons.download_rounded,
                                color: iconcolor,
                              ),
                              selectedIcon: Icon(
                                Icons.download,
                                color: useDynamic
                                    ? Theme.of(innerCtx).colorScheme.primary
                                    : appbarcolor,
                              ),
                              label: l10n.downloadsTitle,
                            ),
                            NavigationDestinationM3E(
                              icon: Icon(
                                Icons.settings_rounded,
                                color: iconcolor,
                              ),
                              selectedIcon: Icon(
                                Icons.settings,
                                color: useDynamic
                                    ? Theme.of(innerCtx).colorScheme.primary
                                    : appbarcolor,
                              ),
                              label: l10n.settingsTitle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  body: IndexedStack(index: _tab, children: pages),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
