/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sautifyv2/blocs/device_library/device_library_cubit.dart';
import 'package:sautifyv2/blocs/device_library/device_library_state.dart';
import 'package:sautifyv2/blocs/download/download_cubit.dart';
import 'package:sautifyv2/blocs/download/download_state.dart';
import 'package:sautifyv2/blocs/settings/settings_cubit.dart';
import 'package:sautifyv2/blocs/settings/settings_state.dart';
import 'package:sautifyv2/db/metadata_overrides_store.dart';
import 'package:sautifyv2/l10n/app_localizations.dart';
import 'package:sautifyv2/models/streaming_model.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/widgets/local_artwork_image.dart';

enum _DownloadsFilter {
  all,
  downloaded,
  device,
}

enum _DownloadsSort {
  defaultOrder,
  title,
  artist,
}

enum _TrackMenuAction {
  editInfo,
  removeOverride,
  deleteDownload,
  copyPath,
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  _DownloadsFilter _filter = _DownloadsFilter.all;
  _DownloadsSort _sort = _DownloadsSort.defaultOrder;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static bool _isHttpUrl(String url) {
    final u = url.trim().toLowerCase();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  static bool _looksLikeFilePath(String urlOrPath) {
    final s = urlOrPath.trim().toLowerCase();
    if (s.startsWith('file://')) return true;
    if (s.startsWith('content://')) return false;
    // Heuristic: absolute-ish paths or Windows drive paths.
    return s.startsWith('/') || RegExp(r'^[a-z]:\\').hasMatch(s);
  }

  static String _stripFileScheme(String s) {
    final trimmed = s.trim();
    if (trimmed.toLowerCase().startsWith('file://')) {
      return trimmed.substring('file://'.length);
    }
    return trimmed;
  }

  Widget _buildArtwork(BuildContext context, StreamingData track) {
    const double size = 50;
    final theme = Theme.of(context);

    final placeholder = Container(
      color: theme.colorScheme.primary.withAlpha(30),
      child: Icon(
        Icons.music_note,
        color: theme.colorScheme.primary,
      ),
    );

    Widget child;
    if (track.isLocal && track.localId != null) {
      child = LocalArtworkImage(
        localId: track.localId!,
        placeholder: placeholder,
        fit: BoxFit.cover,
      );
    } else {
      final thumb = track.thumbnailUrl;
      if (thumb != null && thumb.trim().isNotEmpty) {
        if (_looksLikeFilePath(thumb)) {
          child = Image.file(
            File(_stripFileScheme(thumb)),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder,
          );
        } else if (_isHttpUrl(thumb)) {
          child = CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
        } else {
          child = placeholder;
        }
      } else {
        child = placeholder;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: child,
      ),
    );
  }

  List<StreamingData> _combineOfflineTracks(
    List<StreamingData> downloaded,
    List<StreamingData> onDevice,
  ) {
    final seen = <String>{};
    final out = <StreamingData>[];

    void addAll(Iterable<StreamingData> items) {
      for (final t in items) {
        final key = (t.streamUrl ?? '').isNotEmpty ? t.streamUrl! : t.videoId;
        if (key.isEmpty) continue;
        if (seen.add(key)) out.add(t);
      }
    }

    addAll(downloaded);
    addAll(onDevice);
    return out;
  }

  bool _matchesQuery(StreamingData t, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    return t.title.toLowerCase().contains(needle) ||
        t.artist.toLowerCase().contains(needle);
  }

  int _compareTracks(StreamingData a, StreamingData b) {
    switch (_sort) {
      case _DownloadsSort.title:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case _DownloadsSort.artist:
        return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      case _DownloadsSort.defaultOrder:
        return 0;
    }
  }

  Future<void> _editTrackInfo(BuildContext context, StreamingData track) async {
    final applied = MetadataOverridesStore.maybeApplySync(track);
    final titleController = TextEditingController(text: applied.title);
    final artistController = TextEditingController(text: applied.artist);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: artistController,
                decoration: const InputDecoration(labelText: 'Artist'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true || !mounted) return;
    await MetadataOverridesStore.setOverrideForTrack(
      track,
      title: titleController.text,
      artist: artistController.text,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  Future<void> _removeOverride(
      BuildContext context, StreamingData track) async {
    await MetadataOverridesStore.removeOverrideForTrack(track);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Override removed')),
    );
  }

  Future<void> _copyPath(BuildContext context, StreamingData track) async {
    final path = track.streamUrl;
    if (path == null || path.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Path copied')),
    );
  }

  Future<void> _deleteDownloadedTrack(
    BuildContext context, {
    required String videoId,
    required StreamingData trackForOverrideKey,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete download?'),
          content: const Text('This removes the downloaded file from storage.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    // Best-effort cleanup of override for this track.
    try {
      await MetadataOverridesStore.removeOverrideForTrack(trackForOverrideKey);
    } catch (_) {}

    final deleted = await context.read<DownloadCubit>().deleteDownload(videoId);
    if (!mounted) return;

    // Refresh device library in case the file was indexed there.
    context.read<DeviceLibraryCubit>().refresh();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? 'Deleted' : 'Delete failed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocBuilder<DownloadCubit, DownloadState>(
      builder: (context, downloadState) {
        return BlocBuilder<DeviceLibraryCubit, DeviceLibraryState>(
          builder: (context, deviceState) {
            final combined = _combineOfflineTracks(
              downloadState.downloadedTracks,
              deviceState.tracks,
            );

            final downloadedKeys = downloadState.downloadedTracks
                .map((t) =>
                    (t.streamUrl ?? '').isNotEmpty ? t.streamUrl! : t.videoId)
                .toSet();
            final deviceKeys = deviceState.tracks
                .map((t) =>
                    (t.streamUrl ?? '').isNotEmpty ? t.streamUrl! : t.videoId)
                .toSet();

            bool isDownloaded(StreamingData t) {
              final key =
                  (t.streamUrl ?? '').isNotEmpty ? t.streamUrl! : t.videoId;
              return downloadedKeys.contains(key);
            }

            bool isOnDevice(StreamingData t) {
              final key =
                  (t.streamUrl ?? '').isNotEmpty ? t.streamUrl! : t.videoId;
              return deviceKeys.contains(key);
            }

            final filtered = combined.where((t) {
              if (!_matchesQuery(t, _query)) return false;
              switch (_filter) {
                case _DownloadsFilter.all:
                  return true;
                case _DownloadsFilter.downloaded:
                  return isDownloaded(t);
                case _DownloadsFilter.device:
                  return isOnDevice(t) && !isDownloaded(t);
              }
            }).toList(growable: false);

            final visible = List<StreamingData>.from(filtered);
            if (_sort != _DownloadsSort.defaultOrder) {
              visible.sort(_compareTracks);
            }

            final isLoading =
                (downloadState.isLoading || deviceState.isLoading) &&
                    combined.isEmpty;

            final showDownloadsPermissionGate =
                !downloadState.hasPermission && deviceState.tracks.isEmpty;

            if (isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (showDownloadsPermissionGate) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.permissionDenied,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context
                          .read<DownloadCubit>()
                          .checkPermissionAndLoad(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(l10n.grantPermission),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => context
                          .read<DeviceLibraryCubit>()
                          .requestPermission(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Grant device audio permission'),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                elevation: 0,
                title: Text(
                  l10n.downloadsTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  PopupMenuButton<_DownloadsFilter>(
                    icon: const Icon(Icons.filter_list),
                    tooltip: 'Filter',
                    initialValue: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _DownloadsFilter.all,
                        child: Text('All'),
                      ),
                      PopupMenuItem(
                        value: _DownloadsFilter.downloaded,
                        child: Text('Downloaded'),
                      ),
                      PopupMenuItem(
                        value: _DownloadsFilter.device,
                        child: Text('On device'),
                      ),
                    ],
                  ),
                  PopupMenuButton<_DownloadsSort>(
                    icon: const Icon(Icons.sort),
                    tooltip: 'Sort',
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _DownloadsSort.defaultOrder,
                        child: Text('Default'),
                      ),
                      PopupMenuItem(
                        value: _DownloadsSort.title,
                        child: Text('Title'),
                      ),
                      PopupMenuItem(
                        value: _DownloadsSort.artist,
                        child: Text('Artist'),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => _pickFolder(context),
                    tooltip: 'Change Download Folder',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      context.read<DownloadCubit>().loadSongs();
                      context.read<DeviceLibraryCubit>().refresh();
                    },
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              body: combined.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_off_rounded,
                            size: 64,
                            color: Theme.of(context)
                                .iconTheme
                                .color
                                ?.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noSongsFound,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color
                                          ?.withOpacity(0.7),
                                    ),
                          ),
                          const SizedBox(height: 8),
                          BlocBuilder<SettingsCubit, SettingsState>(
                            builder: (context, settings) {
                              return Text(
                                'Path: ${settings.downloadPath}',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _pickFolder(context),
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('Select Folder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText: 'Search songs',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.clear),
                                      tooltip: 'Clear',
                                    ),
                              border: const OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? Center(
                                  child: Text(
                                    'No results',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color
                                              ?.withOpacity(0.7),
                                        ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: visible.length,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  itemBuilder: (context, index) {
                                    final rawTrack = visible[index];
                                    final track =
                                        MetadataOverridesStore.maybeApplySync(
                                      rawTrack,
                                    );
                                    final canPlay = track.isAvailable &&
                                        track.streamUrl != null;

                                    final key =
                                        (rawTrack.streamUrl ?? '').isNotEmpty
                                            ? rawTrack.streamUrl!
                                            : rawTrack.videoId;
                                    final downloadedVideoId =
                                        isDownloaded(rawTrack)
                                            ? downloadState.downloadedTracks
                                                .firstWhere(
                                                (t) {
                                                  final k = (t.streamUrl ?? '')
                                                          .isNotEmpty
                                                      ? t.streamUrl!
                                                      : t.videoId;
                                                  return k == key;
                                                },
                                                orElse: () => rawTrack,
                                              ).videoId
                                            : null;
                                    final canDelete = downloadedVideoId != null;

                                    return ListTile(
                                      leading: _buildArtwork(context, track),
                                      title: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing:
                                          PopupMenuButton<_TrackMenuAction>(
                                        icon: const Icon(Icons.more_vert),
                                        tooltip: 'More',
                                        onSelected: (action) async {
                                          switch (action) {
                                            case _TrackMenuAction.editInfo:
                                              await _editTrackInfo(
                                                context,
                                                rawTrack,
                                              );
                                              break;
                                            case _TrackMenuAction
                                                  .removeOverride:
                                              await _removeOverride(
                                                context,
                                                rawTrack,
                                              );
                                              break;
                                            case _TrackMenuAction
                                                  .deleteDownload:
                                              if (downloadedVideoId == null) {
                                                return;
                                              }
                                              await _deleteDownloadedTrack(
                                                context,
                                                videoId: downloadedVideoId,
                                                trackForOverrideKey: rawTrack,
                                              );
                                              break;
                                            case _TrackMenuAction.copyPath:
                                              await _copyPath(
                                                context,
                                                rawTrack,
                                              );
                                              break;
                                          }
                                        },
                                        itemBuilder: (context) {
                                          return <PopupMenuEntry<
                                              _TrackMenuAction>>[
                                            const PopupMenuItem(
                                              value: _TrackMenuAction.editInfo,
                                              child: ListTile(
                                                leading: Icon(Icons.edit),
                                                title: Text('Edit info'),
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: _TrackMenuAction
                                                  .removeOverride,
                                              child: ListTile(
                                                leading: Icon(Icons.undo),
                                                title: Text('Remove override'),
                                              ),
                                            ),
                                            if (canDelete)
                                              const PopupMenuItem(
                                                value: _TrackMenuAction
                                                    .deleteDownload,
                                                child: ListTile(
                                                  leading: Icon(Icons.delete),
                                                  title:
                                                      Text('Delete download'),
                                                ),
                                              ),
                                            const PopupMenuItem(
                                              value: _TrackMenuAction.copyPath,
                                              child: ListTile(
                                                leading: Icon(Icons.copy),
                                                title: Text('Copy path'),
                                              ),
                                            ),
                                          ];
                                        },
                                      ),
                                      enabled: canPlay,
                                      onTap: canPlay
                                          ? () {
                                              final playlist = visible
                                                  .where((t) =>
                                                      t.isAvailable &&
                                                      t.streamUrl != null)
                                                  .map(
                                                (t) {
                                                  final applied =
                                                      MetadataOverridesStore
                                                          .maybeApplySync(t);
                                                  return applied.copyWith(
                                                    isAvailable: true,
                                                    isLocal: true,
                                                  );
                                                },
                                              ).toList(growable: false);

                                              final initialIndex =
                                                  playlist.indexWhere(
                                                (t) =>
                                                    t.videoId == track.videoId,
                                              );

                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      PlayerScreen(
                                                    title: track.title,
                                                    artist: track.artist,
                                                    imageUrl:
                                                        track.thumbnailUrl,
                                                    playlist: playlist,
                                                    initialIndex:
                                                        initialIndex < 0
                                                            ? 0
                                                            : initialIndex,
                                                    sourceType: 'OFFLINE',
                                                    sourceName: 'Offline',
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null && context.mounted) {
        context.read<SettingsCubit>().setDownloadPath(selectedDirectory);
        context.read<DownloadCubit>().loadSongs();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error picking folder')),
        );
      }
    }
  }
}

