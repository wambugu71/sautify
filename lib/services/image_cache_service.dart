/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  // Simple LRU cache bounded by total bytes
  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  final LinkedHashMap<String, int> _lru =
      LinkedHashMap<String, int>(); // key -> size
  int _totalBytes = 0;

  // Default cap ~20 MB. Tune in Settings if needed.
  int _maxCacheBytes = 20 * 1024 * 1024;

  // Track ongoing image loads to dedupe requests
  final Map<String, Future<Uint8List?>> _loadingImages = {};

  // Memory pressure observer (registered once)
  bool _memoryObserverRegistered = false;

  /// Optionally customize max cache bytes (call early e.g., at app start)
  void configure({int? maxBytes}) {
    if (maxBytes != null && maxBytes > 1024 * 1024) {
      _maxCacheBytes = maxBytes;
      _evictIfNeeded();
    }
  }

  /// Register a listener to trim cache on OS memory pressure
  void registerMemoryPressureListener() {
    if (_memoryObserverRegistered) return;
    _memoryObserverRegistered = true;

    WidgetsBinding.instance.addObserver(
      _MemoryPressureObserver(
        onPressure: () {
          // Trim cache aggressively on memory pressure
          pruneCache(toBytes: (_maxCacheBytes / 3).floor());
        },
      ),
    );
  }

  /// Get cached image or load it if not cached
  Future<Uint8List?> getCachedImage(String url) async {
    // Return cached image if available and bump LRU
    final cached = _cache[url];
    if (cached != null) {
      _touch(url);
      return cached;
    }

    // Return ongoing loading future if already loading
    final inflight = _loadingImages[url];
    if (inflight != null) return await inflight;

    // Start loading the image
    final loadingFuture = _loadImage(url);
    _loadingImages[url] = loadingFuture;

    try {
      final imageData = await loadingFuture;
      if (imageData != null) {
        _put(url, imageData);
      }
      return imageData;
    } finally {
      _loadingImages.remove(url);
    }
  }

  Future<Uint8List?> _loadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('Error loading image: $e');
    }
    return null;
  }

  /// Preload an image into cache
  Future<void> preloadImage(String url) async {
    await getCachedImage(url);
  }

  /// Clear cache completely
  void clearCache() {
    _cache.clear();
    _lru.clear();
    _totalBytes = 0;
    _loadingImages.clear();
  }

  /// Trim cache down to at most [toBytes]
  void pruneCache({required int toBytes}) {
    final target = toBytes.clamp(0, _maxCacheBytes);
    while (_totalBytes > target && _lru.isNotEmpty) {
      final oldestKey = _lru.keys.first;
      _remove(oldestKey);
    }
  }

  /// Check if image is cached
  bool isImageCached(String url) => _cache.containsKey(url);

  // --- LRU helpers ---
  void _put(String key, Uint8List bytes) {
    // If replacing, remove old first
    if (_cache.containsKey(key)) {
      _remove(key);
    }

    _cache[key] = bytes;
    _lru[key] = bytes.lengthInBytes;
    _totalBytes += bytes.lengthInBytes;
    _evictIfNeeded();
  }

  void _touch(String key) {
    final size = _lru.remove(key);
    if (size != null) {
      _lru[key] = size; // move to end (most recently used)
    }
  }

  void _remove(String key) {
    final data = _cache.remove(key);
    final size = _lru.remove(key);
    if (data != null) {
      _totalBytes -= data.lengthInBytes;
    } else if (size != null) {
      _totalBytes -= size;
    }
  }

  void _evictIfNeeded() {
    while (_totalBytes > _maxCacheBytes && _lru.isNotEmpty) {
      final oldestKey = _lru.keys.first;
      _remove(oldestKey);
    }
  }
}

class _MemoryPressureObserver with WidgetsBindingObserver {
  final VoidCallback onPressure;
  _MemoryPressureObserver({required this.onPressure});
  @override
  void didHaveMemoryPressure() {
    onPressure();
  }
}

/// Widget that displays cached images
class CachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const CachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<CachedNetworkImage> createState() => _CachedNetworkImageState();
}

class _CachedNetworkImageState extends State<CachedNetworkImage> {
  final ImageCacheService _cacheService = ImageCacheService();
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final imageData = await _cacheService.getCachedImage(widget.imageUrl);
      if (mounted) {
        setState(() {
          _imageData = imageData;
          _isLoading = false;
          _hasError = imageData == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isLoading) {
      child =
          widget.placeholder ??
          Container(
            color: Colors.grey[300],
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    } else if (_hasError || _imageData == null) {
      child =
          widget.errorWidget ??
          Container(
            color: Colors.grey[300],
            child: const Icon(Icons.music_note, color: Colors.grey),
          );
    } else {
      // Use cacheWidth/height to reduce decoded image size in cache
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final int? cacheWidth = widget.width != null
          ? (widget.width! * devicePixelRatio).round()
          : null;
      final int? cacheHeight = widget.height != null
          ? (widget.height! * devicePixelRatio).round()
          : null;

      child = Image.memory(
        _imageData!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
      );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }

    return SizedBox(width: widget.width, height: widget.height, child: child);
  }
}
