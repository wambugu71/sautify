# Playback Fix - Songs Not Playing Issue

## Problem Identified

When tapping on a song in the playlist overlay screen, songs weren't playing. The issue was a **race condition and duplicate loading problem**:

### Root Causes

1. **Fire-and-forget loading in background**: `playlist_overlay_screen.dart` was calling `_audio.loadPlaylist()` inside a `Future.microtask()` (async, fire-and-forget), then immediately navigating to `PlayerScreen`

2. **PlayerScreen didn't receive playlist data**: The Navigator.push didn't pass the playlist to PlayerScreen constructor, only individual track info

3. **Duplicate load attempts**: PlayerScreen's initState checked `widget.playlist != null` but since it was never passed, it tried to load a single track. However, `_audioService.playlist.isEmpty` was false because the background microtask already started loading, so **nothing got loaded**

4. **Result**: User sees "Preparing playlist at 0%" stuck indefinitely, no playback starts

## Solution Implemented

### 1. Fixed playlist_overlay_screen.dart (Lines 630-735)

**Before:**

```dart
Future.microtask(() async {
  await _audio.stop();
  await _audio.loadPlaylist(...);
});

// Immediately navigate without waiting
Navigator.push(
  PlayerScreen(
    title: track.title,
    artist: track.artist,
    // NO playlist passed!
  ),
);
```

**After:**

```dart
// Start loading synchronously (await stop, then trigger load)
await _audio.stop();
_audio.loadPlaylist(
  playlist,
  initialIndex: trackNumber - 1,
  autoPlay: true,
  sourceType: 'PLAYLIST',
  sourceName: widget.playlistContent.name,
);

// Navigate with complete playlist info
Navigator.push(
  PlayerScreen(
    title: track.title,
    artist: track.artist,
    playlist: playlist,              // ✅ Pass playlist
    initialIndex: trackNumber - 1,   // ✅ Pass index
    sourceType: 'PLAYLIST',          // ✅ Pass context
    sourceName: widget.playlistContent.name,
  ),
);
```

### 2. Fixed player_screen.dart initState (Lines 94-111)

**Before:**

```dart
if (widget.playlist != null && widget.playlist!.isNotEmpty) {
  Future.microtask(_loadPlaylist);  // Always load again
} else if (widget.videoId != null && _audioService.playlist.isEmpty) {
  Future.microtask(_loadSingleTrack);
}
```

**After:**

```dart
// Check if service is already loading/has content
final bool serviceHasContent = _audioService.playlist.isNotEmpty;
final bool serviceIsPreparing = _audioService.isPreparing.value;

if (widget.playlist != null && widget.playlist!.isNotEmpty) {
  // Only load if service isn't already preparing
  if (!serviceIsPreparing && !serviceHasContent) {
    Future.microtask(_loadPlaylist);
  }
} else if (widget.videoId != null && !serviceHasContent && !serviceIsPreparing) {
  Future.microtask(_loadSingleTrack);
}
```

### 3. Also Fixed Offline Playback Path

Applied same fix to offline track playback (when playing downloaded songs).

## How It Works Now

1. **User taps song** in playlist
2. **Immediately call** `_audio.loadPlaylist()` with full playlist context
3. **Pass playlist data** to PlayerScreen constructor
4. **PlayerScreen checks** if audio service is already preparing
5. **If yes**: UI shows progress, playback continues
6. **If no**: Load the playlist (fallback safety)
7. **Progress indicator** shows loading state correctly
8. **Music plays** when first track is ready

## Benefits

✅ **No duplicate loads**: Prevents loading the same playlist twice
✅ **Proper progress tracking**: UI shows actual loading progress
✅ **Immediate playback**: Songs start playing as soon as ready
✅ **Context preservation**: PlayerScreen has full playlist context
✅ **Race condition fixed**: No more stuck "Preparing playlist at 0%"

## Files Modified

1. `lib/screens/playlist_overlay_screen.dart`
   - Removed `Future.microtask()` wrapper
   - Added playlist data to Navigator.push
   - Fixed offline playback path

2. `lib/screens/player_screen.dart`
   - Added checks for `isPreparing` and `playlist.isNotEmpty`
   - Prevents duplicate playlist loading
   - Smart detection of already-loading content
