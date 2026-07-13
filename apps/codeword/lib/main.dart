import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui';

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
import 'state/app_settings.dart';
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
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void _goToTab(int index) {
    if (index < 0 || index >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
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
    final sessionPhase = ref.watch(
      learningSessionProvider.select((session) => session.phase),
    );
    final immersiveLearning =
        _index == 0 &&
        (sessionPhase == SessionPhase.asking ||
            sessionPhase == SessionPhase.wrongDetail);
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: immersiveLearning
          ? null
          : _PhoneBottomNav(
              index: _index,
              // Delegate to _goToTab so the haptic feedback path is
              // centralised — two tactile clicks per tap feels like a bug.
              onTap: _goToTab,
            ),
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
    final palette = AppColors.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.7),
            border: Border(
              top: BorderSide(
                color: palette.divider.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: onTap,
              backgroundColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              height: 56,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
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
      await ref.read(appSettingsProvider.notifier).ready;
      if (!mounted) return;
      if (ref.read(learningDataClearInProgressProvider)) return;
      final session = ref.read(learningSessionProvider);
      if (session.phase != SessionPhase.loading ||
          session.questions.isNotEmpty) {
        return;
      }
      final vocabId = ref.read(selectedVocabProvider);
      final settings = ref.read(appSettingsProvider);
      await ref
          .read(learningSessionProvider.notifier)
          .start(
            vocabId: vocabId,
            dailyNewWordLimit: settings.dailyNewWords,
            maxSessionSize: settings.dailyNewWords + 20,
          );
    } finally {
      _starting = false;
    }
  }

  void _goLibrary() {
    HapticFeedback.selectionClick();
    context.findAncestorStateOfType<_HomeShellState>()?._goToTab(3);
  }

  void _goReading() {
    HapticFeedback.selectionClick();
    context.findAncestorStateOfType<_HomeShellState>()?._goToTab(1);
  }

  Future<void> _showPauseSheet() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x6,
            AppSpacing.x4,
            AppSpacing.x6,
            AppSpacing.x6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('暂停背词', style: AppTheme.cardTitle(context: context)),
              const SizedBox(height: AppSpacing.x2),
              Text(
                '当前进度会保留，继续后回到这道题。',
                style: AppTheme.mutedCaption(context: context),
              ),
              const SizedBox(height: AppSpacing.x4),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('继续背词'),
              ),
              const SizedBox(height: AppSpacing.x2),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(learningSessionProvider.notifier).finishNow();
                },
                child: const Text('结束本轮'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    ref.watch(reviewStateProvider);
    final catalog = ref.watch(qwertyCatalogProvider);
    final stats = ref
        .read(reviewStateProvider.notifier)
        .stats(catalog: catalog);
    final vocabId = ref.watch(selectedVocabProvider);
    final vocabName = ref.watch(vocabMetaProvider)[vocabId]?.name ?? vocabId;
    final mixedReview = session.questions.any(
      (question) =>
          question.source == SessionQuestionSource.due &&
          question.word.domain != vocabId,
    );
    final appSettings = ref.watch(appSettingsProvider);
    final clearingLearningData = ref.watch(learningDataClearInProgressProvider);

    ref.listen(learningSessionProvider, (prev, next) {
      if (next.phase == SessionPhase.loading && next.questions.isEmpty) {
        Future.microtask(_maybeStart);
      }
    });

    return SafeArea(
      child: Column(
        children: [
          if (!ReviewRepository.isReady) ...[
            const _PersistenceWarning(),
            const SizedBox(height: AppSpacing.x2),
          ],
          if (!clearingLearningData)
            _SessionStatusBar(
              current: session.currentIndex,
              total: session.initialQuestionCount,
              vocabName: mixedReview ? '今日复习' : vocabName,
              phase: session.phase,
              onPause: _showPauseSheet,
              onLibrary: _goLibrary,
            ),
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
                    SessionPhase.finished => _CompletionDashboard(
                      stats: stats,
                      vocabId: vocabId,
                      endedEarly: session.endedEarly,
                      dailyNewWordLimit: appSettings.dailyNewWords,
                      newWordCount: session.newWordCount,
                      reviewWordCount: session.reviewWordCount,
                      duration: session.startedAt == null
                          ? null
                          : DateTime.now().difference(session.startedAt!),
                      hasSessionSummary: session.initialQuestionCount > 0,
                      onRestart: () async {
                        HapticFeedback.lightImpact();
                        await ref.read(appSettingsProvider.notifier).ready;
                        if (!mounted) return;
                        final settings = ref.read(appSettingsProvider);
                        await ref
                            .read(learningSessionProvider.notifier)
                            .start(
                              vocabId: vocabId,
                              dailyNewWordLimit: settings.dailyNewWords,
                              maxSessionSize: settings.dailyNewWords + 20,
                            );
                      },
                      onLearnMore: () async {
                        HapticFeedback.lightImpact();
                        await ref.read(appSettingsProvider.notifier).ready;
                        if (!mounted) return;
                        await ref
                            .read(learningSessionProvider.notifier)
                            .start(
                              vocabId: vocabId,
                              dailyNewWordLimit: stats.newToday + 10,
                              maxSessionSize: 10,
                            );
                      },
                      onGoReading: _goReading,
                      onGoDiscovery: _goLibrary,
                    ),
                  },
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

class _SessionStatusBar extends StatelessWidget {
  final int current;
  final int total;
  final String vocabName;
  final SessionPhase phase;
  final VoidCallback onPause;
  final VoidCallback onLibrary;

  const _SessionStatusBar({
    required this.current,
    required this.total,
    required this.vocabName,
    required this.phase,
    required this.onPause,
    required this.onLibrary,
  });

  @override
  Widget build(BuildContext context) {
    if (phase == SessionPhase.finished || phase == SessionPhase.loading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x6,
        vertical: AppSpacing.x2,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 36,
            child: IconButton(
              tooltip: '暂停',
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.of(context).inkMuted,
                size: 22,
              ),
              onPressed: onPause,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                total > 0 ? '${(current + 1).clamp(1, total)} / $total' : '',
                style: AppTheme.mutedCaption(
                  size: 13,
                  context: context,
                ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onLibrary,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.of(context).inkMuted,
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(
              Icons.library_books_outlined,
              color: AppColors.of(context).inkMuted,
              size: 18,
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                vocabName,
                style: AppTheme.mutedCaption(size: 12, context: context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionDashboard extends StatelessWidget {
  final ReviewStats stats;
  final String vocabId;
  final bool endedEarly;
  final int dailyNewWordLimit;
  final int newWordCount;
  final int reviewWordCount;
  final Duration? duration;
  final bool hasSessionSummary;
  final VoidCallback onRestart;
  final VoidCallback onLearnMore;
  final VoidCallback onGoReading;
  final VoidCallback onGoDiscovery;

  const _CompletionDashboard({
    required this.stats,
    required this.vocabId,
    required this.endedEarly,
    required this.dailyNewWordLimit,
    required this.newWordCount,
    required this.reviewWordCount,
    required this.duration,
    required this.hasSessionSummary,
    required this.onRestart,
    required this.onLearnMore,
    required this.onGoReading,
    required this.onGoDiscovery,
  });

  @override
  Widget build(BuildContext context) {
    final vocab = vocabProgressFor(stats, vocabId);
    final allDone = vocab == null || (vocab.due == 0 && vocab.unseenWords == 0);
    final dailyGoalDone =
        !allDone && vocab.due == 0 && stats.newToday >= dailyNewWordLimit;
    final shownNewWords = hasSessionSummary ? newWordCount : stats.newToday;
    final shownReviews = hasSessionSummary
        ? reviewWordCount
        : max(0, stats.reviewsToday - stats.newToday);
    final durationLabel = hasSessionSummary
        ? formatSessionDuration(duration)
        : stats.studyMinutesToday > 0
        ? '${stats.studyMinutesToday}分'
        : stats.reviewsToday > 0
        ? '<1分'
        : '—';
    final summaryScope = hasSessionSummary ? '本轮' : '今日';
    final primaryAction = allDone
        ? onGoDiscovery
        : dailyGoalDone && !endedEarly
        ? onLearnMore
        : onRestart;
    final primaryLabel = allDone
        ? '选择下一本词书'
        : endedEarly
        ? '继续背词'
        : dailyGoalDone
        ? '再学 10 个'
        : '继续下一组';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.x8),
          if (!endedEarly) ...[
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
          ],
          Text(
            endedEarly
                ? '本轮已结束'
                : (allDone ? '本书新词已学完' : (dailyGoalDone ? '今日目标完成' : '本轮完成')),
            style: AppTheme.screenHeader(
              context: context,
            ).copyWith(fontSize: 28),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            endedEarly ? '已保留本轮学习记录' : '连续 ${stats.streakDays} 天 · 随时可以继续',
            style: AppTheme.mutedCaption(size: 14, context: context),
          ),
          const SizedBox(height: AppSpacing.x6),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: '$summaryScope新学',
                  value: '$shownNewWords',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _StatTile(
                  label: '$summaryScope复习',
                  value: '$shownReviews',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _StatTile(
                  label: '用时',
                  value: durationLabel,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: primaryAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: Icon(
                allDone
                    ? Icons.library_books_outlined
                    : Icons.play_arrow_rounded,
              ),
              label: Text(primaryLabel),
            ),
          ),
          if (!endedEarly && (shownNewWords + shownReviews) > 0) ...[
            const SizedBox(height: AppSpacing.x3),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onGoReading,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('去阅读巩固'),
              ),
            ),
          ],
          if (!allDone) ...[
            const SizedBox(height: AppSpacing.x2),
            TextButton.icon(
              onPressed: onGoDiscovery,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('切换词书'),
            ),
          ],
          const SizedBox(height: AppSpacing.x4),
        ],
      ),
    );
  }
}

@visibleForTesting
String formatSessionDuration(Duration? duration) {
  if (duration == null) return '—';
  final seconds = max(1, duration.inSeconds);
  if (seconds < 60) return '$seconds秒';
  return '${seconds ~/ 60}分';
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.wordDisplay(
              size: 22,
              color: color,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.mutedCaption(size: 12, context: context)),
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
