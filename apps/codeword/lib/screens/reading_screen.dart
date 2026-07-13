import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../models/saved_article.dart';
import '../services/article_repository.dart';
import '../services/tts_service.dart';
import '../state/learning_session.dart';
import '../state/llm_config.dart';
import 'ai_settings_screen.dart';

/// Reading tab — AI-generated short article from today's words, with
/// tap-to-define, comprehension quiz, and article history.
class ReadingScreen extends ConsumerStatefulWidget {
  final bool isActive;

  const ReadingScreen({super.key, this.isActive = true});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  List<PulseWordEntry> _pool = const [];
  bool _loading = true;
  bool _generating = false;
  String? _article;
  String? _error;
  List<SavedArticle> _history = const [];
  int _requestGeneration = 0;
  int _loadedRepositoryRevision = -1;
  bool _contentInitialized = false;

  @override
  void initState() {
    super.initState();
    _loading = false;
    ref.listenManual<bool>(llmConfiguredProvider, (previous, configured) {
      if (configured) {
        if (widget.isActive) _initializeContent();
      } else if (mounted) {
        _requestGeneration++;
        _contentInitialized = false;
        setState(() {
          _loading = false;
          _generating = false;
          _pool = const [];
          _history = const [];
          _article = null;
          _error = null;
        });
      }
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(covariant ReadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive &&
        widget.isActive &&
        ref.read(llmConfiguredProvider)) {
      if (_contentInitialized &&
          _loadedRepositoryRevision != ArticleRepository.instance.revision) {
        _resetAfterRepositoryClear();
      } else {
        _initializeContent();
      }
    }
  }

  void _initializeContent() {
    if (_contentInitialized) return;
    _contentInitialized = true;
    _loadPool();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await ArticleRepository.instance.load();
      if (!mounted) return;
      setState(() {
        _history = h;
        _loadedRepositoryRevision = ArticleRepository.instance.revision;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '读取历史文章失败，请稍后重试');
    }
  }

  Future<void> _loadPool({bool replaceArticle = false}) async {
    if (replaceArticle) _requestGeneration++;
    setState(() {
      _loading = true;
      if (replaceArticle) {
        _generating = false;
        _article = null;
      }
    });
    try {
      final notifier = ref.read(reviewStateProvider.notifier);
      final reviewed = await notifier.reviewedTodayWords(limit: 10);
      final due = reviewed.isEmpty
          ? await notifier.dueWords(limit: 5)
          : const <PulseWordEntry>[];
      final fresh = reviewed.isEmpty
          ? await notifier.recommendedNewWords(
              limit: 5,
              catalog: ref.read(qwertyCatalogProvider),
            )
          : const <PulseWordEntry>[];
      final seen = <String>{};
      final combined = <PulseWordEntry>[];
      for (final e in [...reviewed, ...due, ...fresh]) {
        if (seen.add('${e.vocabId}:${e.word}')) combined.add(e);
      }
      if (!mounted) return;
      setState(() {
        if (_article == null || replaceArticle) {
          _pool = combined;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载词表失败: $e';
      });
    }
  }

  Future<SavedArticle?> _generate({List<PulseWordEntry>? poolOverride}) async {
    if (_generating) return null;
    final cfg = ref.read(llmConfigProvider);
    if (!cfg.isConfigured) {
      if (!mounted) return null;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
      return null;
    }
    final sourcePool = poolOverride ?? _pool;
    if (sourcePool.isEmpty) {
      if (mounted) {
        setState(() => _error = '没有可用的词。先去学几轮。');
      }
      return null;
    }
    final generation = ++_requestGeneration;
    final repositoryRevision = ArticleRepository.instance.revision;
    final pool = List<PulseWordEntry>.unmodifiable(sourcePool);
    setState(() {
      _pool = pool;
      _generating = true;
      _error = null;
    });
    HapticFeedback.lightImpact();
    try {
      final vocabName =
          ref.read(vocabMetaProvider)[pool.first.vocabId]?.name ??
          pool.first.vocabId;
      final words = pool.map((e) => e.word).toList();
      final system = const LlmMessage(
        role: 'system',
        content:
            'You write engaging reading material for a vocabulary app. '
            'Return ONLY a valid JSON object with string fields title, '
            'article, translation, and a questions array. The article must '
            'naturally use every target word. translation is a faithful '
            'Chinese translation. questions contains 3 Chinese multiple-choice '
            'questions; each item has q, 4 string options, and a zero-based '
            'integer correct index.',
      );
      final user = LlmMessage(
        role: 'user',
        content:
            'Theme: $vocabName.\n'
            'Target words (use each at least once, naturally): '
            '${words.join(", ")}.\n'
            'Constraints: 180-260 words. Two or three short paragraphs. '
            'Write for an intermediate English learner. Make it sound like '
            'a real article someone would want to read, not a forced word '
            'list exercise. The questions must test article comprehension. '
            'Return JSON only.',
      );
      final resp = await ref
          .read(llmClientProvider)
          .chat(
            LlmChatRequest(
              model: cfg.model,
              temperature: 0.7,
              maxTokens: 1500,
              messages: [system, user],
            ),
          );
      if (!mounted || generation != _requestGeneration) return null;
      final generated = parseGeneratedReadingPayload(resp.content);
      final articleText = generated.article;
      if (articleText.isEmpty) {
        setState(() {
          _generating = false;
          _error = 'AI 没有返回有效文章，请重试';
        });
        return null;
      }
      setState(() {
        _article = articleText;
        _generating = false;
      });
      HapticFeedback.mediumImpact();

      // Save to history.
      final vocabId = pool.first.vocabId;
      final saved = SavedArticle(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        title: generated.title,
        articleText: articleText,
        translationText: generated.translation,
        level: _readingLevel(pool),
        vocabId: vocabId,
        vocabName: vocabName,
        wordPool: pool
            .map(
              (e) => {
                'word': e.word,
                'translation': e.translation,
                'phonetic': e.phonetic,
                'level': e.level,
              },
            )
            .toList(),
        questions: generated.questions
            .map(
              (question) => <String, dynamic>{
                'q': question.question,
                'options': question.options,
                'correct': question.correctIndex,
              },
            )
            .toList(),
      );
      final savedSuccessfully = await ArticleRepository.instance.save(
        saved,
        expectedRevision: repositoryRevision,
      );
      if (!savedSuccessfully || !mounted || generation != _requestGeneration) {
        return null;
      }
      await _loadHistory();
      return saved;
    } on LlmException catch (e) {
      if (!mounted || generation != _requestGeneration) return null;
      setState(() {
        _generating = false;
        _error = e.statusCode == 401
            ? '鉴权失败 (401) · 检查 API Key'
            : e.statusCode == 404
            ? '路径错误 (404) · 检查 Base URL'
            : 'AI 调用失败 (${e.statusCode ?? '-'}): ${e.message}';
      });
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return null;
      setState(() {
        _generating = false;
        _error = '网络错误: $e';
      });
    }
    return null;
  }

  void _resetAfterRepositoryClear() {
    if (!mounted) return;
    setState(() {
      _history = const [];
      _loadedRepositoryRevision = ArticleRepository.instance.revision;
    });
    _loadPool(replaceArticle: true);
  }

  Future<void> _openComposer() async {
    if (_loading || _generating) return;
    if (_pool.isEmpty) {
      setState(() => _error = '没有可用的词。先去学几轮再回来。');
      return;
    }
    final selected = await Navigator.of(context).push<List<PulseWordEntry>>(
      MaterialPageRoute(builder: (_) => _ReadingComposerPage(pool: _pool)),
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    final article = await _generate(poolOverride: selected);
    if (!mounted || article == null) return;
    _openArticle(article);
  }

  void _openArticle(SavedArticle article) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.expand();
    final isConfigured = ref.watch(llmConfiguredProvider);
    ref.listen<int>(articleRepositoryRevisionProvider, (previous, next) {
      if (isConfigured && previous != null && previous != next) {
        _resetAfterRepositoryClear();
      }
    });
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).background,
        gradient: dark
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8FBF1), Color(0xFFF3FAF4)],
              ),
      ),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('reading-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x5,
                AppSpacing.x3,
                AppSpacing.x5,
                AppSpacing.x8,
              ),
              sliver: SliverList.list(
                children: [
                  const _ReadingHeader(),
                  const SizedBox(height: AppSpacing.x4),
                  if (!isConfigured)
                    _ByokSetupCard(
                      onConfigure: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AiSettingsScreen(),
                        ),
                      ),
                    )
                  else ...[
                    _ReadingHero(
                      pool: _pool,
                      loading: _loading,
                      generating: _generating,
                      onGenerate: _openComposer,
                      onRefresh: () => _loadPool(replaceArticle: true),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.x3),
                      _ErrorCard(message: _error!),
                    ],
                    const SizedBox(height: AppSpacing.x5),
                    _ReadingHistoryList(
                      articles: _history,
                      onTap: _openArticle,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ByokSetupCard extends StatelessWidget {
  final VoidCallback onConfigure;

  const _ByokSetupCard({required this.onConfigure});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.key_rounded, color: AppColors.primary, size: 28),
          const SizedBox(height: AppSpacing.x4),
          Text('连接你自己的 AI', style: AppTheme.cardTitle(context: context)),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'API Key 只保存在此设备。生成时，目标词和文章请求会发送给你选择的模型服务商，相关费用由服务商收取。',
            style: AppTheme.mutedCaption(
              size: 13,
              context: context,
            ).copyWith(height: 1.6),
          ),
          const SizedBox(height: AppSpacing.x5),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onConfigure,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('配置 AI 阅读'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quiz model ──────────────────────────────────────────────────────

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  const QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
  });
}

class GeneratedReadingPayload {
  final String title;
  final String article;
  final String translation;
  final List<QuizQuestion> questions;

  const GeneratedReadingPayload({
    required this.title,
    required this.article,
    required this.translation,
    required this.questions,
  });
}

@visibleForTesting
GeneratedReadingPayload parseGeneratedReadingPayload(String raw) {
  try {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) {
        final article = (decoded['article'] as String? ?? '').trim();
        if (article.isNotEmpty) {
          return GeneratedReadingPayload(
            title: (decoded['title'] as String? ?? '').trim(),
            article: article,
            translation: (decoded['translation'] as String? ?? '').trim(),
            questions: parseQuizQuestions(decoded['questions']),
          );
        }
      }
    }
  } catch (_) {
    // Some OpenAI-compatible providers ignore the JSON-only instruction.
  }
  final article = raw.trim();
  return GeneratedReadingPayload(
    title: _fallbackArticleTitle(article),
    article: article,
    translation: '',
    questions: const [],
  );
}

@visibleForTesting
List<QuizQuestion> parseQuizQuestions(Object? raw) {
  if (raw is! List) return const [];
  try {
    return raw
        .map((entry) {
          if (entry is! Map) return null;
          final question = entry['q'];
          final options = entry['options'];
          final correct = entry['correct'];
          if (question is! String ||
              options is! List ||
              options.length != 4 ||
              options.any((option) => option is! String) ||
              correct is! num ||
              correct.toInt() < 0 ||
              correct.toInt() >= options.length) {
            return null;
          }
          return QuizQuestion(
            question: question,
            options: options.cast<String>(),
            correctIndex: correct.toInt(),
          );
        })
        .whereType<QuizQuestion>()
        .take(3)
        .toList();
  } catch (_) {
    return const [];
  }
}

String _readingLevel(List<PulseWordEntry> pool) {
  for (final word in pool) {
    final level = word.level.trim().toUpperCase();
    if (RegExp(r'^[ABC][12]$').hasMatch(level)) return level;
  }
  return 'B1';
}

String _fallbackArticleTitle(String article) {
  final firstLine = article
      .split(RegExp(r'[\n.!?]'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => 'Today in Code');
  final words = firstLine.split(RegExp(r'\s+'));
  final title = words.take(7).join(' ');
  return title.length > 52 ? '${title.substring(0, 51)}…' : title;
}

String _articleTitle(SavedArticle article) => article.title.trim().isEmpty
    ? _fallbackArticleTitle(article.articleText)
    : article.title.trim();

int _wordCount(String text) =>
    RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?").allMatches(text).length;

class _ReadingHeader extends StatelessWidget {
  const _ReadingHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Center(
        child: Text(
          '阅读',
          style: AppTheme.cardTitle(context: context).copyWith(fontSize: 22),
        ),
      ),
    );
  }
}

class _ReadingHero extends StatelessWidget {
  final List<PulseWordEntry> pool;
  final bool loading;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onRefresh;

  const _ReadingHero({
    required this.pool,
    required this.loading,
    required this.generating,
    required this.onGenerate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final words = pool.take(5).map((entry) => entry.word).toList();
    return Container(
      height: 238,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13D5B3), Color(0xFF078DE8)],
        ),
        boxShadow: AppShadows.md,
      ),
      child: Stack(
        children: [
          for (var i = 0; i < words.length; i++)
            Positioned(
              left: [190.0, 252.0, 215.0, 285.0, 165.0][i],
              top: [28.0, 62.0, 102.0, 132.0, 150.0][i],
              child: Text(
                words[i],
                style: AppTheme.wordDisplay(
                  size: i == 0 ? 17 : 14,
                  color: Colors.white.withValues(alpha: i == 0 ? 0.62 : 0.3),
                  weight: FontWeight.w700,
                ).copyWith(fontFamily: null),
              ),
            ),
          Positioned(
            right: AppSpacing.x2,
            top: AppSpacing.x2,
            child: IconButton(
              tooltip: '换一批目标词',
              onPressed: loading || generating ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: AppSpacing.x1_5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                        SizedBox(width: AppSpacing.x1_5),
                        Text(
                          'AI 今日阅读',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                const SizedBox(
                  width: 230,
                  child: Text(
                    '用今天学过的词，\n读一篇真正看得懂的文章',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  loading
                      ? '正在整理今日词汇…'
                      : pool.isEmpty
                      ? '先完成一轮背词，再回来阅读'
                      : '优先选择答错和待巩固单词',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: loading || generating || pool.isEmpty
                        ? null
                        : onGenerate,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.ink,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                    ),
                    child: generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Text('选择 ${pool.length} 个词生成'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingHistoryList extends StatelessWidget {
  final List<SavedArticle> articles;
  final ValueChanged<SavedArticle> onTap;
  const _ReadingHistoryList({required this.articles, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读记录', style: AppTheme.cardTitle(context: context)),
        const SizedBox(height: AppSpacing.x3),
        if (articles.isEmpty)
          const EmptyHint(
            icon: Icons.auto_stories_outlined,
            message: '生成第一篇文章，让今天的单词在语境里再出现一次。',
          )
        else
          for (var i = 0; i < articles.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.x3),
            _ReadingHistoryCard(article: articles[i], onTap: onTap),
          ],
      ],
    );
  }
}

class _ReadingHistoryCard extends StatelessWidget {
  final SavedArticle article;
  final ValueChanged<SavedArticle> onTap;

  const _ReadingHistoryCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = article.articleText.replaceAll('\n', ' ').trim();
    final words = article.wordPool.take(4).toList();
    final level = article.level.isEmpty ? 'B1' : article.level;
    return AppCard(
      onTap: () => onTap(article),
      semanticLabel: '阅读 ${_articleTitle(article)}',
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _articleTitle(article),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.cardTitle(context: context).copyWith(fontSize: 19),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.mutedCaption(
              size: 13,
              context: context,
            ).copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.x3),
          Wrap(
            spacing: AppSpacing.x1_5,
            runSpacing: AppSpacing.x1_5,
            children: [
              for (final word in words)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: AppSpacing.x1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3A6),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    word['word'] ?? '',
                    style: AppTheme.wordDisplay(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.ink,
                    ).copyWith(fontFamily: null),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          Divider(color: AppColors.of(context).divider, height: 1),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              Text(
                '${article.createdAt.month}/${article.createdAt.day} · ${_wordCount(article.articleText)} 词',
                style: AppTheme.mutedCaption(size: 11, context: context),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x3,
                  vertical: AppSpacing.x1,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF57A16),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  level,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadingComposerPage extends StatefulWidget {
  final List<PulseWordEntry> pool;

  const _ReadingComposerPage({required this.pool});

  @override
  State<_ReadingComposerPage> createState() => _ReadingComposerPageState();
}

class _ReadingComposerPageState extends State<_ReadingComposerPage> {
  late final Set<String> _selected = widget.pool
      .map((word) => word.word)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final selectedWords = widget.pool
        .where((entry) => _selected.contains(entry.word))
        .toList();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('生成阅读'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '选词说明',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => const SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.x5),
                  child: Text(
                    'CodeWord 会优先选择你今天答错、刚学过和即将遗忘的词。你可以取消不想放进文章的词，至少保留 1 个。',
                    style: TextStyle(fontSize: 15, height: 1.6),
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF079FE8), Color(0xFF0E8FEA), Color(0xFF14D8C2)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x5,
              AppSpacing.x8,
              AppSpacing.x5,
              AppSpacing.x5,
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 4,
                  child: Stack(
                    children: [
                      for (var i = 0; i < widget.pool.length; i++)
                        Positioned(
                          left: 12 + (i * 79 % 290).toDouble(),
                          top: 8 + (i * 53 % 220).toDouble(),
                          child: Text(
                            widget.pool[i].word,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: _selected.contains(widget.pool[i].word)
                                    ? 0.72
                                    : 0.24,
                              ),
                              fontSize: 14 + (i % 3) * 3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Text(
                  '选择要在文章中复现的词',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  '已选 ${selectedWords.length} / ${widget.pool.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.x2,
                  runSpacing: AppSpacing.x2,
                  children: [
                    for (final word in widget.pool)
                      FilterChip(
                        label: Text(word.word),
                        selected: _selected.contains(word.word),
                        onSelected: (selected) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (selected) {
                              _selected.add(word.word);
                            } else {
                              _selected.remove(word.word);
                            }
                          });
                        },
                        showCheckmark: false,
                        selectedColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                        labelStyle: TextStyle(
                          color: _selected.contains(word.word)
                              ? AppColors.ink
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: AppSpacing.x2),
                    Flexible(
                      child: Text(
                        '已优先选中今天答错和待巩固的词',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.84),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.x3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: selectedWords.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(selectedWords),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text('用这 ${selectedWords.length} 个词生成文章'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ArticleDetailScreen extends StatefulWidget {
  final SavedArticle article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  bool _showTranslation = false;
  late final List<int?> _answers = List<int?>.filled(
    widget.article.questions?.length ?? 0,
    null,
  );

  List<PulseWordEntry> get _pool => widget.article.wordPool
      .map(
        (word) => PulseWordEntry(
          word: word['word'] ?? '',
          translation: word['translation'] ?? '',
          phonetic: word['phonetic'] ?? '',
          level: word['level'] ?? '',
          vocabId: widget.article.vocabId,
        ),
      )
      .toList();

  List<QuizQuestion> get _questions =>
      parseQuizQuestions(widget.article.questions);

  void _showWordList() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5,
            0,
            AppSpacing.x5,
            AppSpacing.x5,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本篇生词', style: AppTheme.cardTitle(context: context)),
                const SizedBox(height: AppSpacing.x3),
                Expanded(
                  child: ListView.builder(
                    itemCount: _pool.length,
                    itemBuilder: (context, index) {
                      final word = _pool[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          word.word,
                          style: AppTheme.wordDisplay(
                            size: 19,
                            weight: FontWeight.w700,
                            context: context,
                          ),
                        ),
                        subtitle: Text(
                          word.translation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '播放发音',
                          onPressed: () =>
                              TtsService.instance.speak(text: word.word),
                          icon: const Icon(Icons.volume_up_outlined),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final translationAvailable = widget.article.translationText.isNotEmpty;
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? palette.background
          : const Color(0xFFF7FAEA),
      appBar: AppBar(
        title: const Text('阅读'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x5,
              AppSpacing.x4,
              AppSpacing.x5,
              AppSpacing.x10,
            ),
            sliver: SliverList.list(
              children: [
                Text(
                  _articleTitle(widget.article),
                  style: AppTheme.screenHeader(
                    context: context,
                  ).copyWith(fontFamily: null, fontSize: 30, height: 1.15),
                ),
                const SizedBox(height: AppSpacing.x4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x3,
                        vertical: AppSpacing.x1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF57A16),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        widget.article.level.isEmpty
                            ? 'B1'
                            : widget.article.level,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Text(
                      'AI 阅读 · ${_wordCount(widget.article.articleText)} 词',
                      style: AppTheme.mutedCaption(size: 14, context: context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x6),
                _ArticleCard(article: widget.article.articleText, pool: _pool),
                if (_showTranslation) ...[
                  const SizedBox(height: AppSpacing.x5),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      translationAvailable
                          ? widget.article.translationText
                          : '这篇历史文章没有保存译文。重新生成文章后可使用逐篇译文。',
                      key: ValueKey(translationAvailable),
                      style: AppTheme.mutedCaption(
                        size: 15,
                        context: context,
                      ).copyWith(height: 1.8),
                    ),
                  ),
                ],
                if (_questions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x6),
                  _ComprehensionQuiz(
                    questions: _questions,
                    answers: _answers,
                    onAnswer: (questionIndex, optionIndex) {
                      HapticFeedback.selectionClick();
                      setState(() => _answers[questionIndex] = optionIndex);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x2,
          AppSpacing.x5,
          AppSpacing.x2,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x2),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: palette.divider),
            boxShadow: AppShadows.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: _ReaderAction(
                  icon: Icons.volume_up_outlined,
                  label: '朗读',
                  color: const Color(0xFF69B73F),
                  onTap: () => TtsService.instance.speak(
                    text: widget.article.articleText,
                  ),
                ),
              ),
              Expanded(
                child: _ReaderAction(
                  icon: Icons.article_outlined,
                  label: '生词表',
                  color: const Color(0xFFF06D27),
                  onTap: _showWordList,
                ),
              ),
              Expanded(
                child: _ReaderAction(
                  icon: _showTranslation
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  label: '翻译',
                  color: const Color(0xFF4E82DE),
                  onTap: () =>
                      setState(() => _showTranslation = !_showTranslation),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ReaderAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: AppSpacing.x1),
            Text(
              label,
              style: AppTheme.mutedCaption(
                size: 12,
                context: context,
              ).copyWith(color: AppColors.of(context).ink),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error card ──────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.danger.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(
              message,
              style: AppTheme.rowTitle().copyWith(
                fontSize: 13,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Comprehension quiz ──────────────────────────────────────────────

class _ComprehensionQuiz extends StatelessWidget {
  final List<QuizQuestion> questions;
  final List<int?> answers;
  final void Function(int questionIndex, int optionIndex) onAnswer;
  const _ComprehensionQuiz({
    required this.questions,
    required this.answers,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final answered = answers.where((a) => a != null).length;
    final correct = answers.asMap().entries.where((e) {
      final qi = e.key;
      final oi = e.value;
      return oi != null && oi == questions[qi].correctIndex;
    }).length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.quiz_outlined,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.x1_5),
              Text('阅读理解', style: AppTheme.cardTitle(context: context)),
              const Spacer(),
              if (answered == questions.length)
                Text(
                  '$correct / ${questions.length}',
                  style: AppTheme.mutedCaption(size: 13, context: context)
                      .copyWith(
                        fontWeight: FontWeight.w700,
                        color: correct == questions.length
                            ? AppColors.primary
                            : AppColors.warning,
                      ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          for (var i = 0; i < questions.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.x4),
            _QuizQuestionWidget(
              question: questions[i],
              selected: answers[i],
              onSelect: (oi) => onAnswer(i, oi),
              index: i,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizQuestionWidget extends StatelessWidget {
  final QuizQuestion question;
  final int? selected;
  final ValueChanged<int> onSelect;
  final int index;
  const _QuizQuestionWidget({
    required this.question,
    required this.selected,
    required this.onSelect,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${index + 1}. ${question.question}',
          style: AppTheme.rowTitle(context: context).copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppSpacing.x2),
        for (var j = 0; j < question.options.length; j++) ...[
          if (j > 0) const SizedBox(height: AppSpacing.x1_5),
          _QuizOption(
            text: question.options[j],
            isCorrect: j == question.correctIndex,
            isSelected: selected == j,
            showResult: selected != null,
            onTap: selected == null ? () => onSelect(j) : null,
          ),
        ],
      ],
    );
  }
}

class _QuizOption extends StatelessWidget {
  final String text;
  final bool isCorrect;
  final bool isSelected;
  final bool showResult;
  final VoidCallback? onTap;
  const _QuizOption({
    required this.text,
    required this.isCorrect,
    required this.isSelected,
    required this.showResult,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    Color bg = palette.surface;
    Color border = palette.inkSubtle.withValues(alpha: 0.2);
    Color textColor = palette.ink;
    IconData? icon;
    Color? iconColor;

    if (showResult) {
      if (isSelected && isCorrect) {
        bg = AppColors.primarySoft;
        border = AppColors.primary;
        textColor = AppColors.primaryDark;
        icon = Icons.check_circle_rounded;
        iconColor = AppColors.primary;
      } else if (isSelected && !isCorrect) {
        bg = AppColors.danger.withValues(alpha: 0.08);
        border = AppColors.danger;
        textColor = AppColors.danger;
        icon = Icons.cancel_rounded;
        iconColor = AppColors.danger;
      } else if (isCorrect) {
        bg = AppColors.primarySoft.withValues(alpha: 0.3);
        border = AppColors.primary.withValues(alpha: 0.4);
        textColor = AppColors.primaryDark;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: AppTheme.mutedCaption(
                  size: 13,
                  color: textColor,
                  context: context,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: AppSpacing.x2),
              Icon(icon, color: iconColor, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Article body with tappable target words ─────────────────────────

class _ArticleCard extends StatelessWidget {
  final String article;
  final List<PulseWordEntry> pool;

  const _ArticleCard({required this.article, required this.pool});

  void _onWordTap(BuildContext context, PulseWordEntry entry) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WordDefinitionSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = <String, PulseWordEntry>{
      for (final entry in pool) entry.word.toLowerCase(): entry,
    };
    final targets = entries.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final baseStyle = AppTheme.wordDisplay(
      size: 18,
      color: AppColors.of(context).ink,
      context: context,
    ).copyWith(fontFamily: null, height: 1.85, fontWeight: FontWeight.w400);

    if (targets.isEmpty) return Text(article, style: baseStyle);
    final matcher = RegExp(
      '\\b(?:${targets.map(RegExp.escape).join('|')})\\b',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matcher.allMatches(article)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: article.substring(cursor, match.start)));
      }
      final text = article.substring(match.start, match.end);
      final entry = entries[text.toLowerCase()];
      if (entry == null) {
        spans.add(TextSpan(text: text));
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _TargetWord(
              text: text,
              style: baseStyle,
              onTap: () => _onWordTap(context, entry),
            ),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < article.length) {
      spans.add(TextSpan(text: article.substring(cursor)));
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

class _TargetWord extends StatelessWidget {
  final String text;
  final TextStyle style;
  final VoidCallback onTap;

  const _TargetWord({
    required this.text,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF4DF35), width: 5),
          ),
        ),
        child: Text(
          text,
          style: style.copyWith(
            color: AppColors.of(context).ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Word definition bottom sheet ────────────────────────────────────

class _WordDefinitionSheet extends StatelessWidget {
  final PulseWordEntry entry;

  const _WordDefinitionSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.lg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5,
            AppSpacing.x4,
            AppSpacing.x5,
            AppSpacing.x5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.of(
                      context,
                    ).inkSubtle.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.word,
                    style: AppTheme.wordDisplay(
                      size: 28,
                      weight: FontWeight.w700,
                      context: context,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  IconButton(
                    tooltip: '播放发音',
                    icon: const Icon(Icons.volume_up_outlined, size: 22),
                    color: AppColors.of(context).inkMuted,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      TtsService.instance.speak(text: entry.word);
                    },
                  ),
                ],
              ),
              if (entry.phonetic.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x1_5),
                Text(
                  entry.phonetic,
                  style: AppTheme.phonetic(fontSize: 15, context: context),
                ),
              ],
              if (entry.translation.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x3),
                Text(
                  entry.translation,
                  style: AppTheme.cardTitle(
                    context: context,
                  ).copyWith(fontSize: 17, height: 1.5),
                ),
              ],
              if (entry.translation.isEmpty) ...[
                const SizedBox(height: AppSpacing.x4),
                Text(
                  '暂无释义',
                  style: AppTheme.mutedCaption(size: 14, context: context),
                ),
              ],
              const SizedBox(height: AppSpacing.x3),
            ],
          ),
        ),
      ),
    );
  }
}
