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
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/update_dialog.dart';
import 'services/article_repository.dart';
import 'services/update_service.dart';
import 'state/learning_preferences.dart';
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
      title: '墨书',
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
    if (index < 0 || index >= 5) return;
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

  // 5 tabs: 单词 (today/learning) | 阅读 (AI articles, BYOK) |
  // 图表 (stats) | 词书 (library search + catalog) | 设置 (preferences).
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
    const SettingsScreen(key: PageStorageKey('tab-settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: false,
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

/// 5-tab bottom navigation styled to read as a system Tab Bar:
/// full-width, standard height, no floating glass pill, no clamped
/// text scaling (so Dynamic Type can reach ~200%).
class _PhoneBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _PhoneBottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: onTap,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.style_outlined),
          selectedIcon: Icon(Icons.style),
          label: '单词',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: '阅读',
        ),
        NavigationDestination(
          icon: Icon(Icons.insert_chart_outlined),
          selectedIcon: Icon(Icons.insert_chart),
          label: '图表',
        ),
        NavigationDestination(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: '词书',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
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

  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    if (await UpdateService.hasUpdate(info)) {
      final current = await UpdateService.currentVersion();
      if (!mounted) return;
      UpdateDialog.show(context, info: info, currentVersion: current);
    }
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
    final mode = ref.watch(learningPreferencesProvider).learningMode;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SafeArea(
      child: Column(
        children: [
          if (!ReviewRepository.isReady) ...[
            const _PersistenceWarning(),
            const SizedBox(height: AppSpacing.x2),
          ],
            Expanded(
              child: Stack(
                // Full-size constraints so shrink-wrapping phase views
                // (loading spinner, swipe pager, empty state) stay
                // centered instead of hugging the leading edge.
                fit: StackFit.expand,
                children: [
                  clearingLearningData
                      ? const _LearningDataClearView()
                      // Crossfade session phases (loading → asking →
                      // wrongDetail → finished) so the learning loop
                      // never hard-cuts. Reduced-motion skips the fade.
                      : AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : AppMotion.medium,
                          switchInCurve: AppMotion.easeOut,
                          switchOutCurve: AppMotion.easeOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: switch (session.phase) {
                            SessionPhase.loading => const Center(
                              key: ValueKey('loading'),
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                            SessionPhase.asking =>
                              mode == LearningMode.swipe
                                  ? SwipeView(
                                      key: const ValueKey('swipe'),
                                      session: session,
                                    )
                                  : AskingView(
                                      key: const ValueKey('asking'),
                                      session: session,
                                    ),
                            SessionPhase.wrongDetail => WrongDetailView(
                              key: const ValueKey('wrong'),
                              session: session,
                            ),
                            SessionPhase.finished => _NoLearningContent(
                              key: const ValueKey('finished'),
                              onGoReading: _goReading,
                              onGoLibrary: _goLibrary,
                            ),
                          },
                        ),
                  if (!clearingLearningData &&
                      (session.phase == SessionPhase.asking ||
                          session.phase == SessionPhase.wrongDetail))
                    Positioned(
                      top: AppSpacing.x2,
                      right: AppSpacing.x3,
                      child: ModeToggleButton(current: mode),
                    ),
                ],
              ),
            ),
          ],
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
    super.key,
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
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('去阅读'),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: EditorialPrimaryButton(
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
