/*
Copyright (c) 2026 Wambugu Kinyua
All Rights Reserved.
See LICENSE for terms. Written permission is required for any copying, modification, or use.
*/

import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchStarted extends SearchEvent {}

class SearchQueryChanged extends SearchEvent {
  final String query;
  const SearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchSubmitted extends SearchEvent {
  final String query;
  const SearchSubmitted(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchRecentLoaded extends SearchEvent {}

class SearchRecentAdded extends SearchEvent {
  final String query;
  const SearchRecentAdded(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchRecentRemoved extends SearchEvent {
  final String query;
  const SearchRecentRemoved(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchRecentCleared extends SearchEvent {}

class SearchSuggestionsRequested extends SearchEvent {
  final String query;
  const SearchSuggestionsRequested(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchCleared extends SearchEvent {}

