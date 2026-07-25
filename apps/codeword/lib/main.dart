import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_content/lib_content.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import 'screens/discovery_screen.dart';
import 'screens/learning_session_screen.dart';
import 'screens/reading_screen.dart';
import 'screens/stats_screen.dart';
import 'services/article_repository.dart';
import 'state/learning_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise persistence. The storage backend will quarantine any
  // corrupt JSON files (rename to *.corrupted) and return null for
  // those stores; init() itself can still throw on unrecoverable
  // errors from the underlying filesystem (e.g. no documents dir
  // available). Catch that so we never crash the user with a red
  // screen on launch — we simply run against an in-memory repo and
  // log loudly.
  try {
    await ReviewRepository.init();
  } catch (e, st) {
    developer.log(
      'ReviewRepository.init() failed; starting without persisted state: $e',
      name: 'main',
      error: e,
      stackTrace: st,
    );
    try {
      // Second attempt: the failure may have been during schema
      // enforcement with the first write succeeding (header written)
      // and a subsequent wipe partial; re-running init with a now
      // up-to-date schema header may succeed.
      await ReviewRepository.init();
    } catch (e2, st2) {
      developer.log(
        'Second ReviewRepository.init() attempt also failed: $e2',
        name: 'main',
        error: e2,
        stackTrace: st2,
      );
    }
  }
  try {
    final repository = ReviewRepository.instance;
    if (repository.pendingLearningDataClear) {
      await ArticleRepository.instance.clear();
      await repository.completeLearningDataClear();
    }
  } catch (e, st) {
    developer.log(
      'Pending learning-data clear could not be completed: $e',
      name: 'main',
      error: e,
      stackTrace: st,
    );
  }
  try {
    await ReviewRepository.instance.recordOpen(DateTime.now());
  } catch (_) {
    // Missing ReviewRepository is fine — we logged the failure above.
  }
  // Pre-load the qwerty catalog so all consumers (me screen, learning
  // session, stats) can read vocabMetaProvider synchronously. If the
  // manifest asset is missing or corrupt, fall back to an empty list
  // rather than crashing the app.
  List<VocabList> catalog = const [];
  try {
    catalog = await loadQwertyCatalog();
  } catch (e, st) {
    developer.log(
      'Failed to load qwerty catalog: $e\n$st',
      name: 'main',
      error: e,
      stackTrace: st,
    );
  }
  runApp(
    ProviderScope(
      overrides: [qwertyCatalogProvider.overrideWithValue(catalog)],
      child: const CodewordApp(),
    ),
  );
}

class CodewordApp extends StatelessWidget {
  const CodewordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeWord · 码词',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Default to the system's brightness choice — the user can
      // override in the OS settings. Both themes ship a full
      // Material-3 ColorScheme so we never get a half-themed app.
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // A soft fade-in for the newly-selected tab. The IndexedStack stays a
  // single persistent widget (so every tab's State — ReadingScreen's loaded
  // articles, generation flags, scroll offsets — survives the switch); we
  // only fade the body back in on change so tabs feel like they cross over
  // rather than hard-cut. Reduced-motion collapses this to an instant show.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    value: 1,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    if (index < 0 || index >= 4) return;
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
  }

  // 4 tabs: 单词 (today/learning) | 阅读 (AI articles, BYOK) |
  // 图表 (stats) | 词书 (library search + catalog).
  // Settings is a secondary page opened from the 词书 tab.
  // 复习 is intentionally removed — due-for-review words are folded
  // into the learning flow itself.
  //
  // Each tab gets a unique PageStorageKey so its scroll position and
  // transient state is preserved across IndexedStack switches.
  List<Widget> get _pages => [
    const TodayPage(key: PageStorageKey('tab-today')),
    ReadingScreen(
      key: const PageStorageKey('tab-reading'),
      isActive: _index == 1,
      onGoWords: () => _goToTab(0),
    ),
    StatsScreen(
      key: const PageStorageKey('tab-stats'),
      isActive: _index == 2,
      onGoWords: () => _goToTab(0),
      onGoLibrary: () => _goToTab(3),
    ),
    DiscoveryScreen(
      key: const PageStorageKey('tab-library'),
      onGoWords: () => _goToTab(0),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.of(context).background,
      body: DecoratedBox(
        decoration: AppMaterials.canvasDecoration(context),
        // A single, persistent IndexedStack keeps every tab's state alive;
        // FadeTransition only re-fades the visible layer on tab change, so
        // the switch reads as a gentle crossover, not a hard cut.
        child: FadeTransition(
          key: const ValueKey('tab-fade'),
          opacity: CurvedAnimation(parent: _fade, curve: AppMotion.easeOut),
          child: IndexedStack(index: _index, children: _pages),
        ),
      ),
      bottomNavigationBar: _PhoneBottomNav(index: _index, onTap: _goToTab),
    );
  }
}

/// 4-tab bottom navigation with iOS-style frosted glass effect.
class _PhoneBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _PhoneBottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: AppGlassSurface(
        borderRadius: BorderRadius.circular(30),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: 4),
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            maxScaleFactor: 1.3,
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: onTap,
              backgroundColor: Colors.transparent,
              // iOS tint-only selection: no filled pill behind the active
              // destination — the bronze icon + label carry the selected
              // state, which reads cleaner over the liquid-glass bar.
              indicatorColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              height: 60,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.style_outlined),
                  selectedIcon: Icon(Icons.style, color: AppColors.primary),
                  label: '单词',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book, color: AppColors.primary),
                  label: '阅读',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insert_chart_outlined),
                  selectedIcon: Icon(
                    Icons.insert_chart,
                    color: AppColors.primary,
                  ),
                  label: '图表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(
                    Icons.library_books,
                    color: AppColors.primary,
                  ),
                  label: '词书',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder for tabs that aren't built yet. Kept for future use
/// when we add a 5th tab and want to gate it before content lands.
/// (Currently unused — all 4 tabs have real content.)
// ignore: unused_element
class _ComingSoonPage extends StatelessWidget {
  final String title;
  final IconData icon;
  const _ComingSoonPage({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: SafeArea(
        child: Center(
          child: AppCard(
            child: SizedBox(
              width: 240,
              height: 180,
              child: Center(
                child: Icon(
                  icon,
                  size: 56,
                  color: AppColors.of(context).inkSubtle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  Future<void> _maybeStart() async {
    if (_starting) return;
    if (ref.read(learningDataClearInProgressProvider)) return;
    _starting = true;
    try {
      if (ref.read(learningDataClearInProgressProvider)) return;
      final session = ref.read(learningSessionProvider);
      if (session.phase != SessionPhase.loading ||
          session.questions.isNotEmpty) {
        return;
      }
      final vocabId = ref.read(selectedVocabProvider);
      await ref.read(learningSessionProvider.notifier).start(vocabId: vocabId);
    } finally {
      _starting = false;
    }
  }

  void _goReading() {
    HapticFeedback.selectionClick();
    context.findAncestorStateOfType<_HomeShellState>()?._goToTab(1);
  }

  void _goLibrary() {
    HapticFeedback.selectionClick();
    context.findAncestorStateOfType<_HomeShellState>()?._goToTab(3);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    final clearingLearningData = ref.watch(learningDataClearInProgressProvider);

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1.3,
      child: SafeArea(
        child: Column(
          children: [
            if (!ReviewRepository.isReady) ...[
              const _PersistenceWarning(),
              const SizedBox(height: AppSpacing.x2),
            ],
            Expanded(
              child: clearingLearningData
                  ? const _LearningDataClearView()
                  : switch (session.phase) {
                      SessionPhase.loading => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                      SessionPhase.asking => AskingView(session: session),
                      SessionPhase.wrongDetail => WrongDetailView(
                        session: session,
                      ),
                      SessionPhase.finished => _NoLearningContent(
                        onGoReading: _goReading,
                        onGoLibrary: _goLibrary,
                      ),
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningDataClearView extends StatelessWidget {
  const _LearningDataClearView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.x3),
          Text(
            '正在清理本地学习数据…',
            style: AppTheme.mutedCaption(size: 13, context: context),
          ),
        ],
      ),
    );
  }
}

class _NoLearningContent extends StatelessWidget {
  final VoidCallback onGoReading;
  final VoidCallback onGoLibrary;

  const _NoLearningContent({
    required this.onGoReading,
    required this.onGoLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 38,
            color: AppColors.of(context).inkSubtle,
          ),
          const SizedBox(height: AppSpacing.x4),
          Text(
            '当前没有待学单词',
            style: AppTheme.cardTitle(context: context).copyWith(fontSize: 20),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '可以去阅读巩固，或选择其他词书',
            textAlign: TextAlign.center,
            style: AppTheme.mutedCaption(size: 14, context: context),
          ),
          const SizedBox(height: AppSpacing.x6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGoReading,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('去阅读'),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onGoLibrary,
                  icon: const Icon(Icons.library_books_outlined, size: 18),
                  label: const Text('选择词书'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x8),
        ],
      ),
    );
  }
}

class _PersistenceWarning extends StatelessWidget {
  const _PersistenceWarning();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(
              '学习进度无法保存到本地。请重启应用；若问题持续，检查磁盘空间与权限。',
              style: AppTheme.mutedCaption(
                size: 13,
              ).copyWith(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}
