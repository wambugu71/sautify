/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:flutter/material.dart';

// DISABLED: Progress overlay removed per user request
// Songs now stream in background and play immediately
// Original imports kept for reference:
// import 'package:sautifyv2/models/loading_progress_model.dart';
// import 'package:sautifyv2/services/audio_player_service.dart';

class PlaylistLoadingProgress extends StatefulWidget {
  const PlaylistLoadingProgress({super.key});

  @override
  State<PlaylistLoadingProgress> createState() =>
      _PlaylistLoadingProgressState();
}

class _PlaylistLoadingProgressState extends State<PlaylistLoadingProgress> {
  @override
  Widget build(BuildContext context) {
    // DISABLED: User requested to remove the overlay - songs stream in background
    // Progress tracking still happens internally for telemetry
    return const SizedBox.shrink();

    /* Original implementation kept for reference:
    return ValueListenableBuilder<LoadingProgress?>(
      valueListenable: context.watch<AudioPlayerService>().loadingProgress,
      builder: (context, progress, _) {
        // Hide if no progress or if we've marked to hide after complete
        if (progress == null || _hideAfterComplete) {
          return const SizedBox.shrink();
        }

        // Auto-hide after 1.5 seconds when complete
        if (progress.isComplete && !_hideAfterComplete) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              setState(() {
                _hideAfterComplete = true;
              });
            }
          });
        }

        // Reset hide flag when new loading starts
        if (!progress.isComplete && _hideAfterComplete) {
          _hideAfterComplete = false;
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Circular progress indicator
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress.percentage,
                      strokeWidth: 6,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation(Colors.blue),
                    ),
                    Text(
                      progress.percentageDisplay,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Status text
              Text(
                _getStatusText(progress),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Track count stats
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildStatChip(
                    Icons.check_circle,
                    Colors.green,
                    '${progress.loadedTracks} loaded',
                  ),
                  if (progress.failedTracks > 0)
                    _buildStatChip(
                      Icons.error,
                      Colors.red,
                      '${progress.failedTracks} failed',
                    ),
                  if (progress.remainingTracks > 0)
                    _buildStatChip(
                      Icons.hourglass_empty,
                      Colors.orange,
                      '${progress.remainingTracks} pending',
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    */
  }

  /* Kept for reference - methods from original implementation
  Widget _buildStatChip(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(LoadingProgress progress) {
    switch (progress.phase) {
      case LoadingPhase.initializing:
        return 'Preparing playlist...';
      case LoadingPhase.loading:
        return 'Loading ${progress.totalTracks} tracks...';
      case LoadingPhase.complete:
        return 'Ready to play!';
      case LoadingPhase.error:
        return 'Failed to load some tracks';
    }
  }
  */
}

