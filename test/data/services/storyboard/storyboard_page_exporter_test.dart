import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_page_background.dart';
import 'package:nai_launcher/data/models/storyboard/storyboard_panel.dart';
import 'package:nai_launcher/data/services/storyboard/storyboard_page_exporter.dart';

void main() {
  test('整页导出产出真实 PNG（无图面板留空、背景色铺底）', () async {
    final page = StoryboardPage(
      id: 'page-1',
      name: '',
      width: 256,
      height: 256,
      background: const StoryboardPageBackground(
        kind: StoryboardBackgroundKind.color,
        colorArgb: 0xFF112233,
      ),
      panels: [
        StoryboardPanel(
          id: 'p1',
          order: 1,
          x: 16,
          y: 16,
          width: 100,
          height: 100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        StoryboardPanel(
          id: 'p2',
          order: 2,
          x: 140,
          y: 16,
          width: 100,
          height: 100,
          points: const [
            Offset(0, 0),
            Offset(1, 0),
            Offset(1, 1),
            Offset(0, 1),
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    var progressCalls = 0;
    final bytes = await StoryboardPageExporter.renderPage(
      page: page,
      galleryRoot: null,
      onPanelDone: (completed, total) => progressCalls++,
    );
    expect(progressCalls, 2);
    expect(bytes, isNotEmpty);
    // PNG 魔数：89 50 4E 47
    expect(bytes.sublist(0, 4), orderedEquals(<int>[0x89, 0x50, 0x4E, 0x47]));
  });

  test('单分镜导出按外接矩形出图', () async {
    final page = StoryboardPage(
      id: 'page-1',
      name: '',
      width: 512,
      height: 512,
      panels: [
        StoryboardPanel(
          id: 'p1',
          order: 1,
          x: 32,
          y: 32,
          width: 200,
          height: 120,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final bytes = await StoryboardPageExporter.renderPanel(
      page: page,
      panel: page.panels.single,
      galleryRoot: null,
    );
    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 4), orderedEquals(<int>[0x89, 0x50, 0x4E, 0x47]));
  });
}
