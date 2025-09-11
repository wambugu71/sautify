import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/services/audio_player_service.dart';
import 'package:sautifyv2/services/homeservice.dart';
import 'package:sautifyv2/widgets/mini_player.dart';

import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import 'providers/library_provider.dart';
import 'screens/settings_screen.dart';
import 'services/image_cache_service.dart';
import 'services/settings_service.dart';

Future<void> _requestNotificationPermissionIfNeeded() async {
  final status = await Permission.notification.status;
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

  @override
  void initState() {
    super.initState();
    HomeScreenService homeScreenService = HomeScreenService();
    homeScreenService.initialize();
    homeScreenService.getHomeSections();
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
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sautify',
        theme: ThemeData(primaryColorDark: bgcolor),
        home: Scaffold(
          backgroundColor: bgcolor,
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Global Mini Player always shown above the bottom nav bar
              const MiniPlayer(),
              BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _tab,
                onTap: (i) => setState(() => _tab = i),
                backgroundColor: cardcolor,
                selectedItemColor: appbarcolor.withValues(alpha: 50),
                unselectedItemColor: iconcolor.withValues(alpha: 100),
                selectedLabelStyle: TextStyle(
                  color: appbarcolor,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: TextStyle(
                  color: iconcolor.withValues(alpha: 100),
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.library_music_outlined),
                    activeIcon: Icon(Icons.library_music),
                    label: 'Library',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    activeIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            ],
          ),
          body: IndexedStack(index: _tab, children: pages),
        ),
      ),
    );
  }
}
