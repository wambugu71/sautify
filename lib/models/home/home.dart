import 'package:sautifyv2/models/home/contents.dart';

class Section {
  final String title;
  final List<Contents> contents;

  Section({required this.title, required this.contents});

  factory Section.fromYTMusicSection(dynamic section) {
    List<Contents> contentsList = [];

    if (section.contents != null) {
      contentsList = (section.contents as List)
          .map((content) => Contents.fromYTMusicContent(content))
          .toList();
    }

    return Section(
      title: section.title ?? 'Unknown Section',
      contents: contentsList,
    );
  }

  @override
  String toString() {
    return 'Section(title: $title, contents: ${contents.length} items)';
  }
}

class HomeData {
  final List<Section> sections;

  HomeData({required this.sections});

  factory HomeData.fromYTMusicSections(List<dynamic> ytSections) {
    List<Section> sectionsList = ytSections
        .map((section) => Section.fromYTMusicSection(section))
        .toList();

    return HomeData(sections: sectionsList);
  }
}
