import 'dart:developer' as developer;
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
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'state/learning_session.dart';
import 'state/llm_config.dart';

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
    await ReviewRepository.instance.recordOpen(DateTime.now());
  } catch (_) {
    // Missing ReviewRepository is fine — we logged the failure above.
  }
  // Read the bundled local LLM API key (from assets/local/llm_key.txt,
  // gitignored). Used as a fallback when secure storage has no key —
  // works in debug and release builds without Keychain entitlements.
  final fallbackKey = await _readLocalLlmKey();
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
      overrides: [
        qwertyCatalogProvider.overrideWithValue(catalog),
        if (fallbackKey != null)
          llmFallbackKeyProvider.overrideWithValue(fallbackKey),
      ],
      child: const CodewordApp(),
    ),
  );
}

/// Read the API key from the bundled asset `assets/local/llm_key.txt`
/// (gitignored). Returns null if the file is missing or empty.
Future<String?> _readLocalLlmKey() async {
  try {
    final key = (await rootBundle.loadString(
      'assets/local/llm_key.txt',
    )).trim();
    return key.isEmpty ? null : key;
  } catch (_) {
    return null;
  }
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _goToTab(int index) {
    if (index < 0 || index >= _pages.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  // 5 tabs: 单词 (today/learning) | 阅读 (AI articles, BYOK) |
  // 发现 (library search + catalog) | 图表 (stats) | 设置.
  // 复习 is intentionally removed — due-for-review words are folded
  // into the learning flow itself.
  //
  // Each tab gets a unique PageStorageKey so its scroll position and
  // transient state is preserved across IndexedStack switches.
  static const _pages = <Widget>[
    TodayPage(key: PageStorageKey('tab-today')),
    ReadingScreen(key: PageStorageKey('tab-reading')),
    DiscoveryScreen(key: PageStorageKey('tab-discovery')),
    StatsScreen(key: PageStorageKey('tab-stats')),
    SettingsScreen(key: PageStorageKey('tab-settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _PhoneBottomNav(
        index: _index,
        // Delegate to _goToTab so the haptic feedback path is
        // centralised — two tactile clicks per tap feels like a bug.
        onTap: _goToTab,
      ),
    );
  }
}

/// 5-tab bottom navigation with iOS-style frosted glass effect.
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
                  selectedIcon:
                      Icon(Icons.menu_book, color: AppColors.primary),
                  label: '阅读',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon:
                      Icon(Icons.explore, color: AppColors.primary),
                  label: '发现',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insert_chart_outlined),
                  selectedIcon:
                      Icon(Icons.insert_chart, color: AppColors.primary),
                  label: '图表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon:
                      Icon(Icons.settings, color: AppColors.primary),
                  label: '设置',
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
/// when we add a 6th tab and want to gate it before content lands.
/// (Currently unused — 5 tabs all have real content.)
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  void _maybeStart() {
    final session = ref.read(learningSessionProvider);
    if (session.phase == SessionPhase.loading &&
        session.questions.isEmpty) {
      final vocabId = ref.read(selectedVocabProvider);
      ref.read(learningSessionProvider.notifier).start(vocabId: vocabId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    ref.watch(reviewStateProvider);
    final catalog = ref.watch(qwertyCatalogProvider);
    final stats =
        ref.read(reviewStateProvider.notifier).stats(catalog: catalog);
    final vocabId = ref.watch(selectedVocabProvider);
    final vocabName =
        ref.watch(vocabMetaProvider)[vocabId]?.name ?? vocabId;

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
          _SessionStatusBar(
            streak: stats.streakDays,
            current: session.currentIndex,
            total: session.initialQuestionCount,
            vocabName: vocabName,
            phase: session.phase,
          ),
          Expanded(
            child: switch (session.phase) {
              SessionPhase.loading => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary),
                ),
              SessionPhase.asking => AskingView(session: session),
              SessionPhase.wrongDetail =>
                WrongDetailView(session: session),
              SessionPhase.finished => _CompletionDashboard(
                  stats: stats,
                  vocabId: vocabId,
                  onRestart: () {
                    HapticFeedback.lightImpact();
                    ref
                        .read(learningSessionProvider.notifier)
                        .start(vocabId: vocabId);
                  },
                  onGoDiscovery: () {
                    HapticFeedback.selectionClick();
                    context
                        .findAncestorStateOfType<_HomeShellState>()
                        ?._goToTab(2);
                  },
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _SessionStatusBar extends StatelessWidget {
  final int streak;
  final int current;
  final int total;
  final String vocabName;
  final SessionPhase phase;

  const _SessionStatusBar({
    required this.streak,
    required this.current,
    required this.total,
    required this.vocabName,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    if (phase == SessionPhase.finished ||
        phase == SessionPhase.loading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x6,
        vertical: AppSpacing.x2,
      ),
      child: Row(
        children: [
          if (streak > 0) ...[
            const Text('🔥', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 3),
            Text(
              '$streak',
              style: AppTheme.mutedCaption(
                size: 13,
                context: context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ] else
            const SizedBox(width: 20),
          Expanded(
            child: Center(
              child: Text(
                total > 0
                    ? '${(current + 1).clamp(1, total)} / $total'
                    : '',
                style: AppTheme.mutedCaption(
                  size: 13,
                  context: context,
                ).copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Flexible(
            child: Text(
              vocabName,
              style: AppTheme.mutedCaption(size: 12, context: context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
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
  final VoidCallback onRestart;
  final VoidCallback onGoDiscovery;

  const _CompletionDashboard({
    required this.stats,
    required this.vocabId,
    required this.onRestart,
    required this.onGoDiscovery,
  });

  @override
  Widget build(BuildContext context) {
    final vocab = vocabProgressFor(stats, vocabId);
    final allDone =
        vocab == null || (vocab.due == 0 && vocab.unseenWords == 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.x8),
          const Text('🎉', style: TextStyle(fontSize: 48)),
          const SizedBox(height: AppSpacing.x3),
          Text(
            allDone ? '这本词书学完啦' : '今日完成',
            style: AppTheme.screenHeader(context: context)
                .copyWith(fontSize: 28),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '连续 ${stats.streakDays} 天',
            style: AppTheme.mutedCaption(size: 14, context: context),
          ),
          const SizedBox(height: AppSpacing.x6),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: '今日新词',
                  value: '${stats.newToday}',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _StatTile(
                  label: '复习',
                  value: '${stats.reviewsToday}',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _StatTile(
                  label: '用时',
                  value: '${stats.studyMinutesToday}分',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
          if (!allDone)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRestart,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(
                  '再来一轮',
                  style: AppTheme.cardTitle(context: context)
                      .copyWith(color: AppColors.onPrimary),
                ),
              ),
            ),
          if (allDone)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onGoDiscovery,
                child: const Text('去发现页选新词书'),
              ),
            ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onGoDiscovery,
              child: Text(
                '选择其他词书',
                style: AppTheme.rowTitle(context: context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
        ],
      ),
    );
  }
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
          Text(
            label,
            style: AppTheme.mutedCaption(size: 12, context: context),
          ),
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
