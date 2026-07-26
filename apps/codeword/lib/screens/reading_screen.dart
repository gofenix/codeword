import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
  final VoidCallback? onGoWords;
  final Future<ReadingGenerationResult> Function(List<PulseWordEntry>)?
  generationOverride;

  const ReadingScreen({
    super.key,
    this.isActive = true,
    this.onGoWords,
    @visibleForTesting this.generationOverride,
  });

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  List<PulseWordEntry> _candidates = const [];
  List<PulseWordEntry> _selection = const [];
  bool _loading = true;
  bool _generating = false;
  String? _error;
  List<SavedArticle> _history = const [];
  int _requestGeneration = 0;
  int _poolLoadGeneration = 0;
  int _loadedRepositoryRevision = -1;
  int _rotation = 0;
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
        _poolLoadGeneration++;
        _contentInitialized = false;
        setState(() {
          _loading = false;
          _generating = false;
          _candidates = const [];
          _selection = const [];
          _history = const [];
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

  Future<void> _initializeContent() async {
    if (_contentInitialized) return;
    _contentInitialized = true;
    final poolOk = await _loadPool();
    final historyOk = await _loadHistory();
    if (!poolOk || !historyOk) {
      _contentInitialized = false;
    }
  }

  Future<bool> _loadHistory() async {
    try {
      final h = await ArticleRepository.instance.load();
      if (!mounted) return false;
      setState(() {
        _history = h;
        _loadedRepositoryRevision = ArticleRepository.instance.revision;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _error = '读取历史文章失败，请稍后重试');
      return false;
    }
  }

  Future<bool> _loadPool({bool rotate = false}) async {
    final loadGeneration = ++_poolLoadGeneration;
    final previousSelection = _selection.map(_readingWordKey).toList();
    if (rotate) _rotation++;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(reviewStateProvider.notifier);
      final candidates = await notifier.readingCandidateWords(limit: 24);
      if (!mounted || loadGeneration != _poolLoadGeneration) return false;
      final selection = selectReadingWords(candidates, rotation: _rotation);
      setState(() {
        _candidates = candidates;
        _selection = selection;
        _loading = false;
        _error = null;
      });
      if (rotate &&
          previousSelection.isNotEmpty &&
          listEquals(
            previousSelection,
            selection.map(_readingWordKey).toList(),
          )) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已经是当前最适合复现的词')));
      }
      return true;
    } catch (e) {
      if (!mounted || loadGeneration != _poolLoadGeneration) return false;
      setState(() {
        _loading = false;
        _error = '加载词表失败: $e';
      });
      return false;
    }
  }

  Future<ReadingGenerationResult> _generate(
    List<PulseWordEntry> sourcePool,
  ) async {
    if (_generating) {
      return const ReadingGenerationResult.failure('文章正在生成，请稍候');
    }
    final cfg = ref.read(llmConfigProvider);
    if (!cfg.isConfigured) {
      return const ReadingGenerationResult.failure('请先配置 AI 阅读');
    }
    if (sourcePool.length < 3) {
      return const ReadingGenerationResult.failure('至少选择 3 个已学词');
    }
    final generation = ++_requestGeneration;
    final repositoryRevision = ArticleRepository.instance.revision;
    final pool = List<PulseWordEntry>.unmodifiable(sourcePool);
    setState(() {
      _selection = pool;
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
      if (!mounted || generation != _requestGeneration) {
        return const ReadingGenerationResult.cancelled();
      }
      final generated = parseGeneratedReadingPayload(resp.content);
      final articleText = generated.article;
      if (articleText.isEmpty) {
        setState(() => _generating = false);
        return const ReadingGenerationResult.failure('AI 没有返回有效文章，请重试');
      }
      setState(() => _generating = false);
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
      if (!mounted || generation != _requestGeneration) {
        return const ReadingGenerationResult.cancelled();
      }
      if (!savedSuccessfully) {
        return const ReadingGenerationResult.failure('文章已生成，但保存失败，请重试');
      }
      await _loadHistory();
      return ReadingGenerationResult.success(saved);
    } on LlmException catch (e) {
      if (!mounted || generation != _requestGeneration) {
        return const ReadingGenerationResult.cancelled();
      }
      setState(() => _generating = false);
      return ReadingGenerationResult.failure(
        e.statusCode == 401
            ? '鉴权失败，请检查 API Key'
            : e.statusCode == 404
            ? '模型或服务地址不可用'
            : 'AI 调用失败：${e.message}',
      );
    } catch (e) {
      if (!mounted || generation != _requestGeneration) {
        return const ReadingGenerationResult.cancelled();
      }
      setState(() => _generating = false);
      return const ReadingGenerationResult.failure('网络连接失败，请稍后重试');
    }
  }

  void _resetAfterRepositoryClear() {
    if (!mounted) return;
    setState(() {
      _history = const [];
      _loadedRepositoryRevision = ArticleRepository.instance.revision;
    });
    _rotation = 0;
    _loadPool();
  }

  Future<void> _openComposer() async {
    if (_loading || _generating) return;
    if (_selection.length < 3) {
      widget.onGoWords?.call();
      return;
    }
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.slow,
        reverseTransitionDuration: AppMotion.medium,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _ImmersiveReadingComposer(
              candidates: _candidates,
              initialSelection: _selection,
              onGenerate: widget.generationOverride ?? _generate,
              onCancelGeneration: _cancelActiveGeneration,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.emphasized,
            reverseCurve: AppMotion.emphasizedReverse,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _cancelActiveGeneration() {
    _requestGeneration++;
    if (mounted && _generating) {
      setState(() => _generating = false);
    }
  }

  Future<void> _openArticle(SavedArticle article) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(
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
    return TabPageScaffold(
      title: '阅读',
      scrollKey: const PageStorageKey('reading-scroll'),
      slivers: [
        SliverList.list(
          children: [
            if (!isConfigured)
              _ByokSetupCard(
                onConfigure: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                ),
              )
            else ...[
              _ReadingHero(
                key: const ValueKey('reading-summary'),
                pool: _selection,
                loading: _loading,
                generating: _generating,
                onGenerate: _openComposer,
                onRefresh: () => _loadPool(rotate: true),
                onGoWords: widget.onGoWords,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.x3),
                _ErrorCard(message: _error!),
              ],
              const SizedBox(height: AppSpacing.x5),
              _ReadingHistoryList(articles: _history, onTap: _openArticle),
            ],
          ],
        ),
      ],
    );
  }
}

class _ByokSetupCard extends StatelessWidget {
  final VoidCallback onConfigure;

  const _ByokSetupCard({required this.onConfigure});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('reading-first-content'),
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
            child: EditorialPrimaryButton(
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

class ReadingGenerationResult {
  final SavedArticle? article;
  final String? error;
  final bool wasCancelled;

  const ReadingGenerationResult.success(SavedArticle value)
    : article = value,
      error = null,
      wasCancelled = false;

  const ReadingGenerationResult.failure(String message)
    : article = null,
      error = message,
      wasCancelled = false;

  const ReadingGenerationResult.cancelled()
    : article = null,
      error = null,
      wasCancelled = true;
}

String _readingWordKey(PulseWordEntry entry) =>
    '${entry.vocabId}:${entry.word.toLowerCase()}';

@visibleForTesting
List<PulseWordEntry> selectReadingWords(
  List<PulseWordEntry> candidates, {
  int rotation = 0,
}) {
  if (candidates.isEmpty) return const [];
  final due = candidates.where((entry) => entry.isDue).toList();
  final fillers = candidates.where((entry) => !entry.isDue).toList();
  var targetCount = due.length;
  if (targetCount < 6) targetCount = 6;
  if (targetCount > 10) targetCount = 10;
  if (targetCount > candidates.length) targetCount = candidates.length;
  if (candidates.length <= targetCount) return List.of(candidates);

  final selected = <PulseWordEntry>[...due.take(targetCount)];
  if (selected.length == targetCount || fillers.isEmpty) return selected;

  final start = rotation % fillers.length;
  for (var i = 0; i < fillers.length && selected.length < targetCount; i++) {
    selected.add(fillers[(start + i) % fillers.length]);
  }
  return selected;
}

@visibleForTesting
GeneratedReadingPayload parseGeneratedReadingPayload(String raw) {
  try {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) {
        final article = _boundedText(decoded['article'], 12000);
        if (article.isNotEmpty) {
          return GeneratedReadingPayload(
            title: _boundedText(decoded['title'], 120),
            article: article,
            translation: _boundedText(decoded['translation'], 18000),
            questions: parseQuizQuestions(decoded['questions']),
          );
        }
      }
    }
  } catch (_) {
    // Some OpenAI-compatible providers ignore the JSON-only instruction.
  }
  final article = _boundedText(raw, 12000);
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
              !correct.isFinite ||
              correct != correct.truncateToDouble() ||
              correct.toInt() < 0 ||
              correct.toInt() >= options.length) {
            return null;
          }
          final questionText = _boundedText(question, 500);
          final optionTexts = options
              .cast<String>()
              .map((option) => _boundedText(option, 300))
              .toList();
          final normalizedOptions = optionTexts
              .map((option) => option.toLowerCase())
              .toSet();
          if (questionText.isEmpty ||
              optionTexts.any((option) => option.isEmpty) ||
              normalizedOptions.length != optionTexts.length) {
            return null;
          }
          return QuizQuestion(
            question: questionText,
            options: optionTexts,
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

String _boundedText(Object? value, int maxRunes) {
  if (value is! String) return '';
  final trimmed = value.trim();
  if (trimmed.runes.length <= maxRunes) return trimmed;
  return String.fromCharCodes(trimmed.runes.take(maxRunes));
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

class _ReadingHero extends StatelessWidget {
  final List<PulseWordEntry> pool;
  final bool loading;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onRefresh;
  final VoidCallback? onGoWords;

  const _ReadingHero({
    super.key,
    required this.pool,
    required this.loading,
    required this.generating,
    required this.onGenerate,
    required this.onRefresh,
    required this.onGoWords,
  });

  @override
  Widget build(BuildContext context) {
    final words = pool.take(5).map((entry) => entry.word).toList();
    final remaining = pool.length - words.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: AppCard(
        key: const ValueKey('reading-first-content'),
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日阅读',
                        style: AppTheme.cardTitle(context: context),
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      Text(
                        '把今天的词放进一篇值得读完的文章',
                        style: AppTheme.mutedCaption(
                          size: 12,
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '换一批目标词',
                  onPressed: loading || generating
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          onRefresh();
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: AppColors.of(context).inkMuted,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            Text(
              loading
                  ? '正在整理适合今天复现的词…'
                  : pool.isEmpty
                  ? '先学习至少 3 个词，再把它们放进语境'
                  : pool.length < 3
                  ? '还差 ${3 - pool.length} 个词即可生成今日阅读'
                  : '优先复现到期词和最近学过的词',
              style: AppTheme.mutedCaption(size: 12, context: context),
            ),
            const SizedBox(height: AppSpacing.x3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < words.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.x2),
                    PillTag(
                      label: words[i],
                      color: AppColors.warning,
                      variant: PillVariant.soft,
                    ),
                  ],
                  if (remaining > 0) ...[
                    const SizedBox(width: AppSpacing.x2),
                    PillTag(
                      label: '+$remaining',
                      color: AppColors.of(context).inkMuted,
                      variant: PillVariant.soft,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
            SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 46),
                child: EditorialPrimaryButton(
                  onPressed: loading || generating
                      ? null
                      : pool.length < 3
                      ? onGoWords
                      : onGenerate,
                  icon: AnimatedSwitcher(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : AppMotion.fast,
                    child: generating
                        ? const SizedBox(
                            key: ValueKey('reading-loading'),
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Icon(
                            Icons.auto_stories_outlined,
                            key: ValueKey('reading-ready'),
                            size: 18,
                          ),
                  ),
                  label: Text(
                    generating
                        ? '正在生成'
                        : pool.length < 3
                        ? '继续背词'
                        : '选择目标词并生成',
                  ),
                ),
              ),
            ),
          ],
        ),
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
        Text('READING ARCHIVE', style: AppTheme.sectionLabel(context: context)),
        const SizedBox(height: AppSpacing.x2),
        Text('阅读记录', style: AppTheme.cardTitle(context: context)),
        const SizedBox(height: AppSpacing.x4),
        if (articles.isEmpty)
          const EmptyHint(
            icon: Icons.auto_stories_outlined,
            message: '生成第一篇文章，让今天的单词在语境里再出现一次。',
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < articles.length; i++) ...[
                  _ReadingHistoryCard(article: articles[i], onTap: onTap),
                  if (i != articles.length - 1)
                    const SizedBox(height: AppSpacing.x2),
                ],
              ],
            ),
          ),
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
    return Semantics(
      button: true,
      label: '阅读 ${_articleTitle(article)}',
      child: InkWell(
        onTap: () => onTap(article),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _articleTitle(article),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.editorial(
                  size: 20,
                  context: context,
                  height: 1.35,
                ),
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
                  // Same target-word pill as the hero, so the archive card
                  // and the hero never drift into separate chip systems.
                  for (final word in words)
                    PillTag(
                      label: word['word'] ?? '',
                      color: AppColors.warning,
                      variant: PillVariant.soft,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${article.createdAt.month}/${article.createdAt.day} · ${_wordCount(article.articleText)} 词',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mutedCaption(size: 11, context: context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  _LevelBadge(level),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReadingComposerPhase { selecting, forging, revealed }

class _ImmersiveReadingComposer extends StatefulWidget {
  final List<PulseWordEntry> candidates;
  final List<PulseWordEntry> initialSelection;
  final Future<ReadingGenerationResult> Function(List<PulseWordEntry>)
  onGenerate;
  final VoidCallback onCancelGeneration;

  const _ImmersiveReadingComposer({
    required this.candidates,
    required this.initialSelection,
    required this.onGenerate,
    required this.onCancelGeneration,
  });

  @override
  State<_ImmersiveReadingComposer> createState() =>
      _ImmersiveReadingComposerState();
}

class _ImmersiveReadingComposerState extends State<_ImmersiveReadingComposer> {
  static const _messages = ['正在构思自然语境', '正在让目标词自然出现', '正在准备翻译和理解题'];

  late final Set<String> _selected = widget.initialSelection
      .map(_readingWordKey)
      .toSet();
  _ReadingComposerPhase _phase = _ReadingComposerPhase.selecting;
  String? _error;
  SavedArticle? _article;
  int _messageIndex = 0;
  int _rotation = 0;
  bool _settling = false;
  Timer? _messageTimer;

  List<PulseWordEntry> get _selectedWords => widget.candidates
      .where((entry) => _selected.contains(_readingWordKey(entry)))
      .toList();

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  void _toggle(PulseWordEntry word) {
    if (_phase != _ReadingComposerPhase.selecting) return;
    final key = _readingWordKey(word);
    if (_selected.contains(key)) {
      setState(() => _selected.remove(key));
    } else if (_selected.length >= 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('一篇文章最多选择 10 个词')));
      return;
    } else {
      setState(() => _selected.add(key));
    }
    HapticFeedback.selectionClick();
  }

  void _refreshSelection() {
    if (_phase != _ReadingComposerPhase.selecting) return;
    final previous = Set<String>.of(_selected);
    final next = selectReadingWords(widget.candidates, rotation: ++_rotation);
    final nextKeys = next.map(_readingWordKey).toSet();
    setState(() {
      _selected
        ..clear()
        ..addAll(nextKeys);
      _error = null;
    });
    HapticFeedback.selectionClick();
    if (setEquals(previous, nextKeys)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已经是当前最适合复现的词')));
    }
  }

  void _startMessageRotation() {
    _messageTimer?.cancel();
    _messageTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted || _phase != _ReadingComposerPhase.forging) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
  }

  Future<void> _generate() async {
    final words = _selectedWords;
    if (words.length < 3 || _phase != _ReadingComposerPhase.selecting) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final startedAt = DateTime.now();
    setState(() {
      _phase = _ReadingComposerPhase.forging;
      _error = null;
      _article = null;
      _messageIndex = 0;
      _settling = false;
    });
    _startMessageRotation();
    final result = await widget.onGenerate(words);
    _messageTimer?.cancel();
    if (!mounted) return;
    if (result.wasCancelled) {
      setState(() => _phase = _ReadingComposerPhase.selecting);
      Navigator.of(context).pop();
      return;
    }
    if (result.article case final article?) {
      if (!reduceMotion) {
        final elapsed = DateTime.now().difference(startedAt);
        const minimumForgeTime = Duration(milliseconds: 900);
        if (elapsed < minimumForgeTime) {
          await Future<void>.delayed(minimumForgeTime - elapsed);
          if (!mounted) return;
        }
        setState(() {
          _article = article;
          _settling = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 360));
        if (!mounted) return;
      }
      setState(() {
        _article = article;
        _phase = _ReadingComposerPhase.revealed;
        _settling = false;
      });
      return;
    }
    setState(() {
      _phase = _ReadingComposerPhase.selecting;
      _error = result.error ?? '生成失败，请稍后重试';
    });
  }

  Future<void> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('停止等待？'),
        content: const Text('离开后不会打开本次生成结果，服务商仍可能完成已经发出的请求。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('离开'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    widget.onCancelGeneration();
    setState(() => _phase = _ReadingComposerPhase.selecting);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _close() {
    if (_phase == _ReadingComposerPhase.forging) {
      _confirmCancel();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _startReading() {
    final article = _article;
    if (article == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedWords = _selectedWords;
    final available = widget.candidates
        .where((entry) => !_selected.contains(_readingWordKey(entry)))
        .toList();
    return PopScope<void>(
      canPop: _phase != _ReadingComposerPhase.forging,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _ReadingComposerPhase.forging) {
          _confirmCancel();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        appBar: GlassAppBar(
          title: '生成阅读',
          leading: IconButton(
            tooltip: '关闭',
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, size: 23),
            color: AppColors.primary,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ),
        body: DecoratedBox(
          decoration: AppMaterials.canvasDecoration(context),
          child: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : AppMotion.slow,
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.emphasizedReverse,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: switch (_phase) {
                _ReadingComposerPhase.selecting => _ReadingSelectionView(
                  key: const ValueKey('select-reading-words'),
                  selectedWords: selectedWords,
                  availableWords: available,
                  error: _error,
                  onToggle: _toggle,
                  onRefresh: _refreshSelection,
                ),
                _ReadingComposerPhase.forging => _InkLightForge(
                  key: const ValueKey('forging-reading'),
                  words: selectedWords,
                  message: _messages[_messageIndex],
                  settling: _settling,
                ),
                _ReadingComposerPhase.revealed => _ForgeRevealCard(
                  key: const ValueKey('revealed-reading'),
                  article: _article!,
                  onStartReading: _startReading,
                ),
              },
            ),
          ),
        ),
        bottomNavigationBar: _phase == _ReadingComposerPhase.selecting
            ? GlassBottomBar(
                child: SizedBox(
                  width: double.infinity,
                  child: EditorialPrimaryButton(
                    onPressed: selectedWords.length >= 3 ? _generate : null,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      selectedWords.length >= 3
                          ? '生成阅读 · ${selectedWords.length} 词'
                          : '至少选择 3 个词',
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _ReadingSelectionView extends StatelessWidget {
  final List<PulseWordEntry> selectedWords;
  final List<PulseWordEntry> availableWords;
  final String? error;
  final ValueChanged<PulseWordEntry> onToggle;
  final VoidCallback onRefresh;

  const _ReadingSelectionView({
    super.key,
    required this.selectedWords,
    required this.availableWords,
    required this.error,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5,
            AppSpacing.x5,
            AppSpacing.x5,
            AppSpacing.x8,
          ),
          sliver: SliverList.list(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择目标词',
                          style: AppTheme.screenHeader(context: context),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          '已选 ${selectedWords.length} / 10 · 点按可移除',
                          style: AppTheme.mutedCaption(
                            size: 13,
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: const Text('换一批'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x5),
              _ReadingWordWrap(
                words: selectedWords,
                selected: true,
                onTap: onToggle,
              ),
              if (availableWords.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x8),
                Text('可替换词', style: AppTheme.cardTitle(context: context)),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  '这些词都来自你已经学过的内容',
                  style: AppTheme.mutedCaption(size: 12, context: context),
                ),
                const SizedBox(height: AppSpacing.x3),
                _ReadingWordWrap(
                  words: availableWords,
                  selected: false,
                  onTap: onToggle,
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: AppSpacing.x5),
                _ErrorCard(message: error!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadingWordWrap extends StatelessWidget {
  final List<PulseWordEntry> words;
  final bool selected;
  final ValueChanged<PulseWordEntry> onTap;

  const _ReadingWordWrap({
    required this.words,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.x2,
      runSpacing: AppSpacing.x2,
      children: [
        for (final word in words)
          ActionChip(
            avatar: selected
                ? Icon(
                    word.isDue ? Icons.schedule_rounded : Icons.check_rounded,
                    size: 16,
                    color: AppColors.primary,
                  )
                : const Icon(Icons.add_rounded, size: 16),
            label: Text(word.word, overflow: TextOverflow.ellipsis),
            onPressed: () => onTap(word),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            backgroundColor: selected
                ? AppColors.primaryContainerOf(context)
                : AppColors.of(context).surface,
            side: BorderSide(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.of(context).divider,
            ),
            labelStyle: TextStyle(
              color: AppColors.of(context).ink,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _InkLightForge extends StatefulWidget {
  final List<PulseWordEntry> words;
  final String message;
  final bool settling;

  const _InkLightForge({
    super.key,
    required this.words,
    required this.message,
    required this.settling,
  });

  @override
  State<_InkLightForge> createState() => _InkLightForgeState();
}

class _InkLightForgeState extends State<_InkLightForge>
    with TickerProviderStateMixin {
  late final AnimationController _emberController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _dissolveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _settleController = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  bool _motionConfigured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionConfigured) return;
    _motionConfigured = true;
    if (MediaQuery.of(context).disableAnimations) {
      _dissolveController.value = 1;
    } else {
      _emberController.repeat();
      _dissolveController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _InkLightForge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.settling &&
        widget.settling &&
        !MediaQuery.of(context).disableAnimations) {
      _settleController.forward();
    }
  }

  @override
  void dispose() {
    _emberController.dispose();
    _dissolveController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          if (!reduceMotion)
            IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _EmberFieldPainter(
                    animation: _emberController,
                    settling: _settleController,
                  ),
                ),
              ),
            ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.x5),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth - AppSpacing.x10,
                minHeight: math.max(0, constraints.maxHeight - AppSpacing.x10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 1, end: 0.14).animate(
                      CurvedAnimation(
                        parent: _dissolveController,
                        curve: AppMotion.easeOut,
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.x3,
                      runSpacing: AppSpacing.x2,
                      children: [
                        for (final word in widget.words)
                          Text(
                            word.word,
                            style: AppTheme.editorial(
                              size: 14,
                              color: AppColors.primary,
                              context: context,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x5),
                  _BreathingPaper(
                    breath: _emberController,
                    settling: _settleController,
                    reduceMotion: reduceMotion,
                  ),
                  const SizedBox(height: AppSpacing.x5),
                  AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : AppMotion.fast,
                    child: Text(
                      widget.message,
                      key: ValueKey(widget.message),
                      textAlign: TextAlign.center,
                      style: AppTheme.cardTitle(context: context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '墨光正把这些词写进一篇值得读完的短文',
                    textAlign: TextAlign.center,
                    style: AppTheme.mutedCaption(size: 13, context: context),
                  ),
                  if (reduceMotion) ...[
                    const SizedBox(height: AppSpacing.x5),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathingPaper extends StatelessWidget {
  final Animation<double> breath;
  final Animation<double> settling;
  final bool reduceMotion;

  const _BreathingPaper({
    required this.breath,
    required this.settling,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget paper(double glow, double flash) => Container(
      width: 206,
      height: 244,
      padding: const EdgeInsets.all(AppSpacing.x6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.of(context).surface : null,
        gradient: isDark ? null : AppMaterials.paper,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.26 + glow * 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.14 + glow * 0.18),
            blurRadius: 22 + glow * 18,
            spreadRadius: 1 + glow * 4,
          ),
          if (!isDark) ...AppShadows.paper,
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  gradient: AppMaterials.bronze,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
              const Spacer(),
              for (var i = 0; i < 5; i++) ...[
                Container(
                  height: 1,
                  color: AppColors.primary.withValues(alpha: 0.08 + i * 0.012),
                ),
                if (i < 4) const SizedBox(height: AppSpacing.x4),
              ],
              const Spacer(),
              Icon(
                Icons.auto_stories_outlined,
                size: 24,
                color: AppColors.primary.withValues(alpha: 0.28),
              ),
            ],
          ),
          if (flash > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                color: AppColors.inversePrimary.withValues(alpha: flash * 0.36),
              ),
            ),
        ],
      ),
    );

    if (reduceMotion) return paper(0.45, 0);
    return AnimatedBuilder(
      animation: Listenable.merge([breath, settling]),
      builder: (context, child) {
        final glow = (math.sin(breath.value * math.pi * 2) + 1) / 2;
        final flash = math.sin(settling.value * math.pi);
        return Transform.scale(
          scale: 1 + glow * 0.008,
          child: paper(glow, flash),
        );
      },
    );
  }
}

class _EmberFieldPainter extends CustomPainter {
  final Animation<double> animation;
  final Animation<double> settling;

  _EmberFieldPainter({required this.animation, required this.settling})
    : super(repaint: Listenable.merge([animation, settling]));

  double _randomUnit(int seed) {
    final value = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return (value - value.floor()).abs();
  }

  Offset _startPoint(Size size, int index) {
    final along = 0.08 + _randomUnit(index + 17) * 0.84;
    return switch (index % 4) {
      0 => Offset(size.width * along, -8),
      1 => Offset(size.width + 8, size.height * along),
      2 => Offset(size.width * along, size.height + 8),
      _ => Offset(-8, size.height * along),
    };
  }

  Offset _quadratic(Offset start, Offset control, Offset end, double t) {
    final inverse = 1 - t;
    return Offset(
      inverse * inverse * start.dx +
          2 * inverse * t * control.dx +
          t * t * end.dx,
      inverse * inverse * start.dy +
          2 * inverse * t * control.dy +
          t * t * end.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.43);
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final corePaint = Paint();
    for (var index = 0; index < 28; index++) {
      final staggered = (animation.value + index / 28 * 0.82) % 1;
      final pathProgress = AppMotion.easeInOut.transform(staggered);
      final start = _startPoint(size, index);
      final midpoint = Offset.lerp(start, center, 0.5)!;
      final direction = center - start;
      final length = math.max(direction.distance, 1);
      final perpendicular = Offset(
        -direction.dy / length,
        direction.dx / length,
      );
      final bend =
          (index.isEven ? 1 : -1) * (18 + _randomUnit(index + 81) * 46);
      final control = midpoint + perpendicular * bend;
      final settlingProgress = AppMotion.easeInOut.transform(settling.value);
      final effectiveProgress =
          pathProgress + (1 - pathProgress) * settlingProgress;
      final point = _quadratic(start, control, center, effectiveProgress);
      final pulse = math.sin(staggered * math.pi);
      final opacity = (0.18 + pulse * 0.62) * (1 - settlingProgress * 0.72);
      final radius = 1.2 + _randomUnit(index + 143) * 2.1;
      glowPaint.color = AppColors.inversePrimary.withValues(
        alpha: opacity * 0.52,
      );
      // Ember core: mid-bronze derived from the token pair (no magic hex).
      corePaint.color = Color.lerp(
        AppColors.primary,
        AppColors.inversePrimary,
        0.45,
      )!.withValues(alpha: opacity);
      canvas.drawCircle(point, radius * 3.2, glowPaint);
      canvas.drawCircle(point, radius, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberFieldPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.settling != settling;
}

class _ForgeRevealCard extends StatefulWidget {
  final SavedArticle article;
  final VoidCallback onStartReading;

  const _ForgeRevealCard({
    super.key,
    required this.article,
    required this.onStartReading,
  });

  @override
  State<_ForgeRevealCard> createState() => _ForgeRevealCardState();
}

class _ForgeRevealCardState extends State<_ForgeRevealCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.article.wordPool
        .map((entry) => entry['word'] ?? '')
        .where((word) => word.isNotEmpty)
        .take(10)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x5,
          AppSpacing.x5,
          AppSpacing.x8,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth - AppSpacing.x10,
            minHeight: math.max(
              0,
              constraints.maxHeight - AppSpacing.x5 - AppSpacing.x8,
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final cardProgress = AppMotion.easeOut.transform(
                (_controller.value / 0.58).clamp(0, 1),
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: cardProgress,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - cardProgress)),
                      child: Transform.scale(
                        scale: 0.95 + cardProgress * 0.05,
                        child: AppCard(
                          onTap: widget.onStartReading,
                          semanticLabel:
                              '开始阅读 ${_articleTitle(widget.article)}',
                          padding: const EdgeInsets.all(AppSpacing.x6),
                          shadow: const [
                            ...AppShadows.hero,
                            ...AppShadows.paper,
                          ],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '书 成',
                                      style:
                                          AppTheme.sectionLabel(
                                            context: context,
                                          ).copyWith(
                                            color: AppColors.primary,
                                            letterSpacing: 5,
                                          ),
                                    ),
                                  ),
                                  _LevelBadge(
                                    widget.article.level.isEmpty
                                        ? 'B1'
                                        : widget.article.level,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.x5),
                              _ShimmeringTitle(
                                title: _articleTitle(widget.article),
                                progress: _controller.value,
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              Text(
                                'AI 阅读 · ${_wordCount(widget.article.articleText)} 词',
                                style: AppTheme.mutedCaption(
                                  size: 13,
                                  context: context,
                                ),
                              ),
                              if (words.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.x5),
                                Wrap(
                                  spacing: AppSpacing.x2,
                                  runSpacing: AppSpacing.x2,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < words.length;
                                      index++
                                    )
                                      _StaggeredRevealWord(
                                        word: words[index],
                                        progress: _controller.value,
                                        index: index,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  IgnorePointer(
                    ignoring: _controller.value < 0.58,
                    child: Opacity(
                      opacity: AppMotion.easeOut.transform(
                        ((_controller.value - 0.58) / 0.42).clamp(0, 1),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: EditorialPrimaryButton(
                          onPressed: widget.onStartReading,
                          icon: const Icon(
                            Icons.auto_stories_rounded,
                            size: 19,
                          ),
                          label: const Text('开始阅读'),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ShimmeringTitle extends StatelessWidget {
  final String title;
  final double progress;

  const _ShimmeringTitle({required this.title, required this.progress});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final sweep = -3 + progress * 6;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment(sweep - 1, 0),
        end: Alignment(sweep + 1, 0),
        colors: [
          palette.ink,
          palette.ink,
          AppColors.inversePrimary,
          palette.ink,
          palette.ink,
        ],
        stops: const [0, 0.36, 0.5, 0.64, 1],
      ).createShader(bounds),
      child: Text(
        title,
        style: AppTheme.editorial(size: 28, context: context, height: 1.28),
      ),
    );
  }
}

class _StaggeredRevealWord extends StatelessWidget {
  final String word;
  final double progress;
  final int index;

  const _StaggeredRevealWord({
    required this.word,
    required this.progress,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final start = 0.42 + index * 0.035;
    final reveal = AppMotion.easeOut.transform(
      ((progress - start) / 0.22).clamp(0, 1),
    );
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - reveal)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3,
            vertical: AppSpacing.x1_5,
          ),
          decoration: BoxDecoration(
            gradient: Theme.of(context).brightness == Brightness.light
                ? AppMaterials.paper
                : null,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.primaryContainerOf(context)
                : null,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.24),
            ),
            boxShadow: AppShadows.sm,
          ),
          child: Text(
            word,
            style: AppTheme.editorial(
              size: 13,
              color: AppColors.primary,
              context: context,
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
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            TtsService.instance.speak(text: word.word);
                          },
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
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: '阅读',
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.primary,
        ),
      ),
      body: DecoratedBox(
        decoration: AppMaterials.canvasDecoration(context),
        child: Builder(
          builder: (context) {
            final topInset = MediaQuery.paddingOf(context).top;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.x6,
                    topInset + AppSpacing.x4,
                    AppSpacing.x6,
                    AppSpacing.x10,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        _articleTitle(widget.article),
                        style: AppTheme.screenHeader(context: context).copyWith(
                          fontFamily: null,
                          fontSize: 30,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x4),
                      Wrap(
                        spacing: AppSpacing.x3,
                        runSpacing: AppSpacing.x2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _LevelBadge(
                            widget.article.level.isEmpty
                                ? 'B1'
                                : widget.article.level,
                          ),
                          Text(
                            'AI 阅读 · ${_wordCount(widget.article.articleText)} 词',
                            style: AppTheme.mutedCaption(
                              size: 14,
                              context: context,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x6),
                      _ArticleCard(
                        article: widget.article.articleText,
                        pool: _pool,
                      ),
                      if (_showTranslation) ...[
                        const SizedBox(height: AppSpacing.x5),
                        AnimatedSwitcher(
                          duration: MediaQuery.of(context).disableAnimations
                              ? Duration.zero
                              : AppMotion.medium,
                          switchInCurve: AppMotion.easeOut,
                          switchOutCurve: AppMotion.easeOut,
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
                            setState(
                              () => _answers[questionIndex] = optionIndex,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: GlassBottomBar(
        child: Row(
          children: [
            Expanded(
              child: _ReaderAction(
                icon: Icons.volume_up_outlined,
                label: '朗读',
                color: AppColors.primary,
                onTap: () {
                  HapticFeedback.lightImpact();
                  TtsService.instance.speak(
                    text: widget.article.articleText,
                  );
                },
              ),
            ),
            Expanded(
              child: _ReaderAction(
                icon: Icons.article_outlined,
                label: '生词表',
                color: AppColors.sage,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showWordList();
                },
              ),
            ),
            Expanded(
              child: _ReaderAction(
                icon: _showTranslation
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                label: '翻译',
                color: _showTranslation ? AppColors.primary : palette.inkMuted,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _showTranslation = !_showTranslation);
                },
              ),
            ),
          ],
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 23),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppTheme.mutedCaption(
                    size: 12,
                    context: context,
                  ).copyWith(color: AppColors.of(context).ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Level badge ─────────────────────────────────────────────────────

/// The single CEFR-level pill used by both the reading list and the
/// article detail header, so the two never drift apart. A solid bronze
/// pill (on-palette with the warm-paper system) that is width-capped and
/// ellipsised — the article `level` field can be arbitrary text from a
/// model response, so it must never overflow its row.
class _LevelBadge extends StatelessWidget {
  final String level;
  const _LevelBadge(this.level);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 96),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        level,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.onPrimary,
          fontWeight: FontWeight.w800,
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
        bg = AppColors.primaryContainerOf(context);
        border = AppColors.primary;
        textColor = AppColors.onPrimaryContainerOf(context);
        icon = Icons.check_circle_rounded;
        iconColor = AppColors.primary;
      } else if (isSelected && !isCorrect) {
        bg = AppColors.danger.withValues(alpha: 0.08);
        border = AppColors.danger;
        textColor = AppColors.danger;
        icon = Icons.cancel_rounded;
        iconColor = AppColors.danger;
      } else if (isCorrect) {
        bg = AppColors.primaryContainerOf(context).withValues(alpha: 0.3);
        border = AppColors.primary.withValues(alpha: 0.4);
        textColor = AppColors.onPrimaryContainerOf(context);
      }
    }

    // InkWell (not a bare GestureDetector) so the tap has a visible
    // pressed state; the enclosing AppCard provides the Material.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AnimatedContainer(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : AppMotion.fast,
        curve: AppMotion.easeOut,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: border,
            width: AppBorders.hairline,
          ),
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
      showDragHandle: true,
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

class _TargetWord extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback onTap;

  const _TargetWord({
    required this.text,
    required this.style,
    required this.onTap,
  });

  @override
  State<_TargetWord> createState() => _TargetWordState();
}

class _TargetWordState extends State<_TargetWord> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.text,
      hint: '查看释义',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.5 : 1,
          duration: AppMotion.press,
          curve: AppMotion.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.target, width: 5),
              ),
            ),
            child: Text(
              widget.text,
              style: widget.style.copyWith(
                color: AppColors.of(context).ink,
                fontWeight: FontWeight.w700,
              ),
            ),
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          0,
          AppSpacing.x5,
          AppSpacing.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    entry.word,
                    softWrap: true,
                    style: AppTheme.wordDisplay(
                      size: 28,
                      weight: FontWeight.w700,
                      context: context,
                    ),
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
    );
  }
}
