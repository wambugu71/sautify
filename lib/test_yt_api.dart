/*
Copyright (c) 2025 Wambugu Kinyua
Licensed under the Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
*/

import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  // Create an instance of the YouTube Music API
  final ytmusic = YTMusic();
  // Initialize the API
  await ytmusic.initialize();

  try {
    /*
    // Get home sections using our data models
    List<dynamic> rawSections = await ytmusic.getHomeSections();
    HomeData homeData = HomeData.fromYTMusicSections(rawSections);
    for (var section in homeData.sections) {
      print('---' * 10);
      print('Section Title: ${section.title}');
      print('Content Count: ${section.contents.length}');

      for (var content in section.contents) {
        print('Type: ${content.type}');
        print('Artist: ${content.artistName}');
        print('Song: ${content.name}');
        print('Playlist ID: ${content.playlistId ?? 'N/A'}');
        print('Thumbnail: ${content.thumbnailUrl}');

        print('---');
      }
      print('---' * 10);
    }
  } catch (e) {
    print('Error fetching home sections: $e');
  }
  */
    /*
  final albumResults = await ytmusic.searchSongs('wakadinali');
  for (var song in albumResults) {
    print('${song.name} by ${song.videoId} Duration: ${song.duration}');
    print(song.thumbnails.first.url);
  }
  */
    /*
  //getting search suggestions
  print('Search Suggestions:');
  final suggestions = await ytmusic.getSearchSuggestions('wakadinali');
  for (var suggestion in suggestions) {
    print(suggestion);
  }

  //GETTING  ARTIST  INFO
  final queryalbum = await ytmusic.searchAlbums("Victims  of  madness 2");
  final artist = await ytmusic.getAlbum(queryalbum.first.albumId);
  for (var music in artist.songs) {
    //var musicData = await getDownloadUrl(music.videoId);
    print(
      " ${music.name} artist ${music.artist.name} music ID ${music.videoId}",
    );
    //print("Download URL: $musicData");
  }
  */
    /* var searchResults = await ytmusic.searchSongs('Wakadinali');
    for (var song in searchResults) {
      // ignore: avoid_print

      print('${song.name} by ${song.artist.name} Duration: ${song.duration}');
      print(song.thumbnails.first.url);
      print('Song: videoid: ${song.videoId}');
      print('ALBUM: ${song.album?.name ?? 'N/A'}');
      print('---' * 5);
    }*/
    /*
    var albums = await ytmusic.searchAlbums("VIXTIMS  OF  MADNESS");
    for (var album in albums) {
      // ignore: avoid_print
      print(
        "Album: ${album.name} by ${album.artist?.name ?? 'N/A '} ID: ${album.playlistId}",
      );
      print('Album playlist ID: ${album.playlistId}');
      print(album.thumbnails.first.url);
      print('---' * 5);
    }
    */

    // var search = await ytmusic.getSearchSuggestions('Wakadinali');
    //  for (var suggestion in search) {
    // ignore: avoid_print
    //print('Suggestion: $suggestion');
    //  }

    var synclyrics = await ytmusic.getTimedLyrics('Xj0BjCfMwTw');
    print('Message: ${synclyrics?.sourceMessage}');

    if (synclyrics!.timedLyricsData.isNotEmpty) {
      for (var lyricsdata in synclyrics.timedLyricsData) {
        print(
          "Lyric: ${lyricsdata.lyricLine}, Cue Range: ${lyricsdata.cueRange!.startTimeMilliseconds} - ${lyricsdata.cueRange!.endTimeMilliseconds}",
        );
      }
    }
    print('Done !');
  } catch (e) {
    // ignore: avoid_print
    print('Error: $e');
  }
}
