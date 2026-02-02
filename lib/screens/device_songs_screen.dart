/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sautifyv2/blocs/device_library/device_library_cubit.dart';
import 'package:sautifyv2/blocs/device_library/device_library_state.dart';
import 'package:sautifyv2/screens/player_screen.dart';

class DeviceSongsScreen extends StatelessWidget {
  const DeviceSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceLibraryCubit, DeviceLibraryState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!state.hasPermission) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Permission needed to read device audio',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      context.read<DeviceLibraryCubit>().requestPermission(),
                  child: const Text('Grant permission'),
                ),
              ],
            ),
          );
        }

        if (state.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.read<DeviceLibraryCubit>().refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (state.tracks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.library_music_outlined, size: 64),
                const SizedBox(height: 12),
                Text(
                  'No audio found on this device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.read<DeviceLibraryCubit>().refresh(),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('On device'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<DeviceLibraryCubit>().refresh(),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: state.tracks.length,
            itemBuilder: (context, index) {
              final t = state.tracks[index];
              return ListTile(
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                enabled: t.isAvailable && t.streamUrl != null,
                onTap: (t.isAvailable && t.streamUrl != null)
                    ? () {
                        final playlist = state.tracks
                            .where((x) => x.isAvailable && x.streamUrl != null)
                            .toList(growable: false);

                        final initialIndex =
                            playlist.indexWhere((x) => x.videoId == t.videoId);

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => PlayerScreen(
                              title: t.title,
                              artist: t.artist,
                              imageUrl: t.thumbnailUrl,
                              playlist: playlist,
                              initialIndex: initialIndex < 0 ? 0 : initialIndex,
                              sourceType: 'OFFLINE',
                              sourceName: 'On device',
                            ),
                          ),
                        );
                      }
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

