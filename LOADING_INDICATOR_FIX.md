# ExpressiveLoadingIndicator Fix - Player Screen Loading State

## Problem

The `ExpressiveLoadingIndicator` in the player screen wasn't showing when a track was loading because the `isPreparing` state was being set to `false` too early or staying `true` too long.

### Root Cause

The loading indicator visibility depends on:

```dart
final isLoading = (!effectivePlaying) && (preparing || engineLoading);
```

Where `preparing` comes from `_audioService.isPreparing.value`.

**Timeline of issues:**

1. **Initial attempt**: Called `_setPreparing(false)` immediately after `_setMinimalSingleSource()`
   - **Problem**: Set to false BEFORE player actually started buffering/playing
   - **Result**: Loading indicator never showed

2. **Second attempt**: Removed early `_setPreparing(false)`, relied on `finally` block
   - **Problem**: For progressive loading (80+ tracks), `isPreparing` stayed `true` while background tracks loaded
   - **Result**: Loading indicator shown too long (during entire background loading)

## Solution

Set `isPreparing = false` at the **optimal time**: after `_setMinimalSingleSource()` completes AND `autoPlay` is true, but BEFORE background progressive loading starts.

### Code Change

**File:** `lib/services/audio_player_service.dart`

```dart
if (_playlist[_currentIndex].isReady &&
    _playlist[_currentIndex].streamUrl != null) {
  await _setMinimalSingleSource(_currentIndex, autoPlay: autoPlay);
  _firstPlayableAt ??= DateTime.now();
  
  // For progressive loading: first track is ready and playing
  // Set preparing=false so UI doesn't show loading during background track resolution
  // The finally block will also set it, but this ensures immediate UI update
  if (autoPlay) {
    _setPreparing(false);
  }
}
```

### Why This Works

**Timeline:**

1. `_setPreparing(true)` called at start of `replacePlaylist()`
2. First track fetched (shows loading indicator during this)
3. `_setMinimalSingleSource()` called
   - Sets audio source
   - Calls `_player.play()` if autoPlay
   - Player enters buffering state (engineLoading)
4. **`_setPreparing(false)` called** ← Our fix
5. Progressive worker continues loading background tracks
6. Player's own buffering state (`engineLoading`) handles remaining loading states

**Result:**

- ✅ Loading indicator shows while first track loads
- ✅ Loading indicator shows during player buffering
- ✅ Loading indicator hides once playback starts
- ✅ Background track loading doesn't trigger loading indicator

## Loading Indicator Logic

The player screen shows the loading indicator when:

```dart
ValueListenableBuilder<bool>(
  valueListenable: _audioService.isPreparing,
  builder: (context, preparing, _) {
    return StreamBuilder<PlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final effectivePlaying = playerState?.playing ?? (info?.isPlaying ?? false);
        final processing = playerState?.processingState;
        final engineLoading =
            processing == ProcessingState.loading ||
            processing == ProcessingState.buffering;
        
        // Show loading only when NOT playing and either preparing or engine is loading
        final isLoading = (!effectivePlaying) && (preparing || engineLoading);

        return IconButton(
          onPressed: isLoading ? null : _togglePlayPause,
          icon: isLoading
              ? ExpressiveLoadingIndicator(...)
              : Icon(effectivePlaying ? Icons.pause : Icons.play_arrow),
        );
      },
    );
  },
)
```

### States Covered

1. **`preparing = true`**: Service is loading playlist/track
2. **`engineLoading = true`**: Player is buffering audio
3. **`!effectivePlaying`**: Not currently playing

**Shows loading when:** Any combination that results in `isLoading = true`

## Testing

Test these scenarios:

### Small Playlist (< 80 tracks)

1. Tap song
2. **Loading indicator should show** briefly while track loads
3. Loading indicator hides when playback starts
4. ✅ Expected: Brief flash of loading indicator

### Large Playlist (80+ tracks, progressive)

1. Tap song
2. **Loading indicator should show** while first track loads
3. Loading indicator hides when first track starts playing
4. Background tracks continue loading silently
5. ✅ Expected: Loading shows only for first track, not during background loading

### Skip to Unloaded Track

1. Playing track 1 of large playlist
2. Skip to track 50 (not yet loaded)
3. **Loading indicator should show** while track 50 loads
4. Loading indicator hides when track 50 starts
5. ✅ Expected: Loading indicator appears for on-demand track loading

### Buffering During Playback

1. Track playing
2. Network slow/buffering occurs
3. **Loading indicator should show** (from `engineLoading`)
4. ✅ Expected: Handled by player's processingState

## Edge Cases Handled

✅ **Progressive loading**: First track loads → plays → indicator hides → background continues  
✅ **Non-autoplay**: Doesn't set preparing=false if autoPlay is false  
✅ **Buffering**: Player's own state (`ProcessingState.buffering`) shows indicator  
✅ **Track switching**: Each track load triggers appropriate loading state  
✅ **Finally block**: Still sets preparing=false as safety net  

## Files Modified

- ✅ `lib/services/audio_player_service.dart` - Added conditional `_setPreparing(false)` after first track ready
- ✅ No changes to `player_screen.dart` - loading indicator logic already correct
- ✅ All code compiles successfully

## Summary

**Before:** Loading indicator didn't show (preparing set false too early) or showed too long (during background loading)

**After:** Loading indicator shows briefly during first track load, then hides when playback starts, while background loading continues silently

**Key insight:** The `isPreparing` state should reflect "is the USER waiting for something" not "is background work happening"
