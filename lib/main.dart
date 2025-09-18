/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
// flutter_localizations are included via AppLocalizations.localizationsDelegates
import 'package:sautifyv2/l10n/app_localizations.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/homeservice.dart';
import 'package:sautifyv2/widgets/mini_player.dart';
import 'package:toastification/toastification.dart';

import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
// Legacy lightweight i18n helper is still used in other screens; not needed here
// import 'l10n/strings.dart';
import 'providers/library_provider.dart';
import 'screens/settings_screen.dart';
import 'services/image_cache_service.dart';
import 'services/settings_service.dart';

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

  // Init Hive early for local storage
  await Hive.initFlutter();

  // Configure and register memory pressure handling for images
  final imgCacheSvc = ImageCacheService();
  imgCacheSvc.configure(maxBytes: 20 * 1024 * 1024); // ~20MB cap
  imgCacheSvc.registerMemoryPressureListener();

  // Also cap Flutter's built-in ImageCache to limit decoded frames in memory
  PaintingBinding.instance.imageCache
    ..maximumSize =
        100 // max number of images
    ..maximumSizeBytes = 30 * 1024 * 1024; // ~30MB decoded bytes

  // Request runtime permission for notifications on Android 13+
  await _requestNotificationPermissionIfNeeded();

  // Initialize background audio notifications/controls
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.sautify.playback',
    androidNotificationChannelName: 'Sautify Playback',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
    preloadArtwork: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
  );

  // Initialize the AudioPlayerService singleton
  final audioService = AudioPlayerService();
  await audioService.initialize();

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _tab = 0;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    HomeScreenService homeScreenService = HomeScreenService();
    homeScreenService.initialize();
    homeScreenService.getHomeSections();
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
        toastification.show(
          context: context,
          title: const Text('You are offline'),
          description: const Text(
            'Some features may not work without internet',
          ),
          type: ToastificationType.warning,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 4),
          alignment: Alignment.topCenter,
          primaryColor: Colors.orange,
          backgroundColor: Colors.black87,
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
        final offline =
            results.isEmpty ||
            results.every((c) => c == ConnectivityResult.none);
        if (offline) {
          toastification.show(
            context: context,
            title: const Text('No internet connection'),
            description: const Text('You are offline'),
            type: ToastificationType.error,
            style: ToastificationStyle.fillColored,
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
            primaryColor: Colors.redAccent,
            backgroundColor: Colors.black87,
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const LibraryScreen(),
      const SettingsScreen(),
    ];

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>(
          create: (_) => LibraryProvider()..init(),
        ),
        ChangeNotifierProvider<SettingsService>(
          create: (_) => SettingsService()..init(),
        ),
      ],
      child: ToastificationWrapper(
        child: Consumer<SettingsService>(
          builder: (context, settings, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
              theme: ThemeData(primaryColorDark: bgcolor),
              locale: _toLocale(settings.localeCode),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (innerCtx) {
                  final l10n = AppLocalizations.of(innerCtx);
                  return Scaffold(
                    backgroundColor: bgcolor,
                    bottomNavigationBar: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Global Mini Player always shown above the bottom nav bar
                        const MiniPlayer(),
                        // Disable ripple/highlight specifically for the bottom nav bar
                        Theme(
                          data: Theme.of(context).copyWith(
                            splashFactory: NoSplash.splashFactory,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                          ),
                          child: BottomNavigationBar(
                            type: BottomNavigationBarType.fixed,
                            currentIndex: _tab,
                            onTap: (i) => setState(() => _tab = i),
                            backgroundColor: cardcolor,
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
                            ),
                            items: [
                              BottomNavigationBarItem(
                                icon: const Icon(Icons.home_rounded),
                                activeIcon: const Icon(Icons.home),
                                label: l10n.homeTitle,
                              ),
                              BottomNavigationBarItem(
                                icon: const Icon(Icons.library_music_rounded),
                                activeIcon: const Icon(Icons.library_music),
                                label: l10n.libraryTitle,
                              ),
                              BottomNavigationBarItem(
                                icon: const Icon(Icons.settings_rounded),
                                activeIcon: const Icon(Icons.settings),
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
      ),
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
