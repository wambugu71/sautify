/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class LocalArtworkImage extends StatefulWidget {
  final int localId;
  final ArtworkType type;
  final BoxFit fit;
  final Widget? placeholder;

  const LocalArtworkImage({
    super.key,
    required this.localId,
    this.type = ArtworkType.AUDIO,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<LocalArtworkImage> createState() => _LocalArtworkImageState();
}

class _LocalArtworkImageState extends State<LocalArtworkImage> {
  static final OnAudioQuery _query = OnAudioQuery();

  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _query.queryArtwork(widget.localId, widget.type);
  }

  @override
  void didUpdateWidget(covariant LocalArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localId != widget.localId || oldWidget.type != widget.type) {
      _future = _query.queryArtwork(widget.localId, widget.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            gaplessPlayback: true,
          );
        }
        return widget.placeholder ?? const SizedBox.shrink();
      },
    );
  }
}

