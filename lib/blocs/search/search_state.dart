/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';
import 'package:sautifyv2/models/album_search_result.dart';
import 'package:sautifyv2/models/streaming_model.dart';

enum SearchStatus { initial, loading, success, failure }

class SearchState extends Equatable {
  final SearchStatus status;
  final String query;
  final List<StreamingData> results;
  final List<String> suggestions;
  final List<AlbumSearchResult> albumResults;
  final List<String> recentSearches;
  final String? error;
  final bool isInitialized;

  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.results = const [],
    this.suggestions = const [],
    this.albumResults = const [],
    this.recentSearches = const [],
    this.error,
    this.isInitialized = false,
  });

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<StreamingData>? results,
    List<String>? suggestions,
    List<AlbumSearchResult>? albumResults,
    List<String>? recentSearches,
    String? error,
    bool? isInitialized,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      suggestions: suggestions ?? this.suggestions,
      albumResults: albumResults ?? this.albumResults,
      recentSearches: recentSearches ?? this.recentSearches,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  @override
  List<Object?> get props => [
        status,
        query,
        results,
        suggestions,
        albumResults,
        recentSearches,
        error,
        isInitialized,
      ];
}

