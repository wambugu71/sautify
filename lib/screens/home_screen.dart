import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sautifyv2/constants/ui_colors.dart';
import 'package:sautifyv2/models/home/contents.dart';
import 'package:sautifyv2/models/home/home.dart';
import 'package:sautifyv2/providers/fetch_home_Section.dart';
import 'package:sautifyv2/screens/player_screen.dart';
import 'package:sautifyv2/screens/playlist_overlay_screen.dart';
import 'package:sautifyv2/screens/search_overlay_screen.dart';
import 'package:sautifyv2/services/image_cache_service.dart';
import 'package:skeletonizer/skeletonizer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => HomeNotifier(),
      child: Scaffold(
        backgroundColor: bgcolor,
        appBar: AppBar(
          title: const Text(
            'S A U T I F Y',
            style: TextStyle(
              fontFamily: 'asimovian',
              fontWeight: FontWeight.bold,
              fontSize: 24,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
          backgroundColor: appbarcolor,
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const SearchOverlayScreen(),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                final homeNotifier = Provider.of<HomeNotifier>(
                  context,
                  listen: false,
                );
                homeNotifier.fetchHomeSections();
              },
            ),
          ],
        ),
        body: Consumer<HomeNotifier>(
          builder: (context, homeNotifier, child) {
            if (homeNotifier.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Error: ${homeNotifier.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => homeNotifier.fetchHomeSections(),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () => homeNotifier.fetchHomeSections(),
              child: Skeletonizer(
                enabled:
                    homeNotifier.isLoading ||
                    !homeNotifier.isInitialized ||
                    homeNotifier.sections.isEmpty,
                effect: ShimmerEffect(
                  baseColor: cardcolor,
                  highlightColor: cardcolor.withAlpha(153), // 60% opacity
                  duration: const Duration(milliseconds: 1000),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: 100,
                  ), // Space for global mini player
                  itemCount: homeNotifier.sections.isEmpty
                      ? 5
                      : homeNotifier.sections
                            .where((section) => section.contents.isNotEmpty)
                            .length,
                  itemBuilder: (context, index) {
                    if (homeNotifier.sections.isEmpty) {
                      return _buildSkeletonSection();
                    }

                    final sectionsWithContent = homeNotifier.sections
                        .where((section) => section.contents.isNotEmpty)
                        .toList();

                    if (index >= sectionsWithContent.length) {
                      return const SizedBox.shrink();
                    }

                    final section = sectionsWithContent[index];
                    return _buildSectionWidget(context, section);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionWidget(BuildContext context, Section section) {
    if (section.contents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: txtcolor,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: section.contents.length,
              itemBuilder: (context, index) {
                final content = section.contents[index];
                return _buildContentCard(context, content);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard(BuildContext context, Contents content) {
    return GestureDetector(
      onTap: () => _handleContentTap(context, content),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        child: Card(
          color: cardcolor,
          elevation: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      color: Colors.grey[300],
                    ),
                    child: content.thumbnailUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: content.thumbnailUrl,
                            fit: BoxFit.cover,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            errorWidget: const Icon(
                              Icons.music_note,
                              size: 40,
                              color: Colors.grey,
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.music_note,
                              size: 40,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: txtcolor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        content.artistName,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          content.type,
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: cardcolor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (context, index) {
                return _buildSkeletonCard();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        color: cardcolor,
        elevation: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    color: cardcolor.withAlpha(179), // 70% opacity
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(179), // 70% opacity
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(128), // 50% opacity
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: 16,
                      width: 50,
                      decoration: BoxDecoration(
                        color: cardcolor.withAlpha(179), // 70% opacity
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleContentTap(BuildContext context, Contents content) {
    // Check if it's a playlist type content
    if (content.type.toLowerCase().contains('playlist') ||
        content.playlistId != null) {
      if (content.playlistId != null && content.playlistId!.isNotEmpty) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => PlaylistOverlayScreen(playlistContent: content),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No playlist ID available'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      // Handle other content types (songs, albums, etc.)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            title: content.name,
            artist: content.artistName,
            imageUrl: content.thumbnailUrl,
            // Note: For proper playback, we need videoId from the content
            // This will be improved when we add videoId to Contents model
          ),
        ),
      );
    }
  }
}
