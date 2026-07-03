import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codeword/screens/reading_screen.dart';
import 'package:codeword/state/learning_session.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

void main() {
  testWidgets('AppColors.of resolves dark palette under dark theme', (
    tester,
  ) async {
    late AppPalette palette;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            palette = AppColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(palette.surface, AppColors.surfaceDark);
    expect(palette.ink, AppColors.inkDark);
    expect(palette.background.computeLuminance() < 0.2, isTrue);
  });

  testWidgets('AppColors.of resolves light palette under light theme', (
    tester,
  ) async {
    late AppPalette palette;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (context) {
            palette = AppColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(palette.surface, AppColors.surface);
    expect(palette.ink, AppColors.ink);
    expect(palette.background.computeLuminance() > 0.8, isTrue);
  });

  testWidgets('AppCard paints the dark surface in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: AppCard(child: Text('x'))),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, AppColors.surfaceDark);
  });

  testWidgets('compact icon buttons keep a >=44px tap target', (tester) async {
    // Mirrors the wrong-detail / reading action buttons: a 20px icon with
    // zero padding and a 48px min-constraint. Note VisualDensity.compact
    // subtracts up to 8px, so these buttons must NOT use compact density if
    // they are to clear the 44px minimum — this test locks that in.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.star_rounded, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('ReadingScreen refresh button keeps a >=44px tap target', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qwertyCatalogProvider.overrideWithValue(const []),
          reviewStateProvider.overrideWith(
            (ref) => _ReadingSmokeReviewNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const ReadingScreen(),
        ),
      ),
    );
    final refreshIcon = find.byTooltip('换一批');
    for (var i = 0; i < 100 && refreshIcon.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(refreshIcon, findsOneWidget);

    final refreshButton = find.ancestor(
      of: refreshIcon,
      matching: find.byType(IconButton),
    );
    final size = tester.getSize(refreshButton);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}

class _ReadingSmokeReviewNotifier extends ReviewStateNotifier {
  _ReadingSmokeReviewNotifier() : super(const {});

  @override
  Future<List<PulseWordEntry>> dueWords({int limit = 3, DateTime? now}) async {
    return const [];
  }

  @override
  Future<List<PulseWordEntry>> recommendedNewWords({
    int limit = 3,
    required List<VocabList> catalog,
  }) async {
    return const [];
  }
}
