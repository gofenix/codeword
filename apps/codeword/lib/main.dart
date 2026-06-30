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
    developer.log('Failed to load qwerty catalog: $e\n$st',
        name: 'main', error: e, stackTrace: st);
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
    final key = (await rootBundle.loadString('assets/local/llm_key.txt')).trim();
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
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: _PhoneBottomNav(
        index: _index,
        // Delegate to _goToTab so the haptic feedback path is
        // centralised — two tactile clicks per tap feels like a bug.
        onTap: _goToTab,
      ),
    );
  }
}

/// 5-tab bottom navigation. Sits inside the phone bezel.
class _PhoneBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _PhoneBottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: onTap,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore, color: AppColors.primary),
          label: '发现',
        ),
        NavigationDestination(
          icon: Icon(Icons.insert_chart_outlined),
          selectedIcon: Icon(Icons.insert_chart, color: AppColors.primary),
          label: '图表',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings, color: AppColors.primary),
          label: '设置',
        ),
      ],
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: AppCard(
            child: SizedBox(
              width: 240,
              height: 180,
              child: Center(
                child: Icon(icon, size: 56, color: AppColors.inkSubtle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the state (not just .notifier) so this rebuilds when
    // review state changes — e.g. after completing a learning session.
    ref.watch(reviewStateProvider);
    // Watch the catalog (not read) so dynamic catalog changes in the
    // future (reload after download) propagate correctly.
    final catalog = ref.watch(qwertyCatalogProvider);
    final stats = ref.read(reviewStateProvider.notifier).stats(catalog: catalog);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x4,
          AppSpacing.x5,
          AppSpacing.x8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!ReviewRepository.isReady) ...[
              const _PersistenceWarning(),
              const SizedBox(height: AppSpacing.x4),
            ],
            _Greeting(newToday: stats.newToday),
            const SizedBox(height: AppSpacing.x5),
            _TodayTaskCard(stats: stats),
          ],
        ),
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
              style: AppTheme.mutedCaption(size: 13).copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final int newToday;
  const _Greeting({required this.newToday});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hi, 极客',
          style: AppTheme.mutedCaption(size: 14),
        ),
        const SizedBox(height: 2),
        Text(
          newToday == 0 ? '今天还没开始' : '今天学了 $newToday 个新词',
          style: AppTheme.screenHeader().copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

/// The single today-task card: one clear action and the two numbers
/// that matter (due + new). Nothing else competes for attention.
class _TodayTaskCard extends ConsumerWidget {
  final ReviewStats stats;
  const _TodayTaskCard({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vocabId = ref.watch(selectedVocabProvider);
    final vocabName =
        ref.watch(vocabMetaProvider)[vocabId]?.name ?? vocabId;
    final vocab = vocabProgressFor(stats, vocabId);
    final vocabDue = vocab?.due ?? 0;
    final unseenInVocab = vocab?.unseenWords ?? 0;
    final canStart = canStartLearningForVocab(stats, vocabId);
    final allDone = !canStart;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '今日任务',
                style: AppTheme.cardTitle().copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                vocabName,
                style: AppTheme.mutedCaption(size: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            allDone
                ? '这本词书已经学完啦'
                : '待复习 $vocabDue · 剩余新词 $unseenInVocab · 今日已学 ${stats.newToday}',
            style: AppTheme.mutedCaption(size: 14),
          ),
          const SizedBox(height: AppSpacing.x5),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: allDone
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LearningSessionScreen(
                            vocabId: vocabId,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: const Text('开始学习'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
                textStyle: AppTheme.cardTitle().copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                final shell = context.findAncestorStateOfType<_HomeShellState>();
                shell?._goToTab(2); // 发现
              },
              child: Text(
                '选择其他词书',
                style: AppTheme.rowTitle(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
