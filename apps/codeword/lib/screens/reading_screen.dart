import 'dart:async';
import 'dart:convert';

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

  const ReadingScreen({super.key, this.isActive = true, this.onGoWords});

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
  bool _selectingWords = false;

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

  Future<void> _loadPool({bool rotate = false}) async {
    final loadGeneration = ++_poolLoadGeneration;
    final previousSelection = _selection.map(_readingWordKey).toList();
    if (rotate) _rotation++;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(reviewStateProvider.notifier);
      final candidates = await notifier.readingCandidateWords(limit: 24);
      if (!mounted || loadGeneration != _poolLoadGeneration) return;
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
    } catch (e) {
      if (!mounted || loadGeneration != _poolLoadGeneration) return;
      setState(() {
        _loading = false;
        _error = '加载词表失败: $e';
      });
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
    setState(() => _selectingWords = true);
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
              AnimatedSwitcher(
                duration: AppMotion.medium,
                child: _selectingWords
                    ? _InlineReadingComposer(
                        key: const ValueKey('inline-reading-composer'),
                        candidates: _candidates,
                        initialSelection: _selection,
                        onGenerate: _generate,
                        onClose: () => setState(() => _selectingWords = false),
                        onOpenArticle: _openArticle,
                      )
                    : _ReadingHero(
                        key: const ValueKey('reading-summary'),
                        pool: _selection,
                        loading: _loading,
                        generating: _generating,
                        onGenerate: _openComposer,
                        onRefresh: () => _loadPool(rotate: true),
                        onGoWords: widget.onGoWords,
                      ),
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
    return Container(
      key: const ValueKey('reading-first-content'),
      constraints: const BoxConstraints(minHeight: 190),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        gradient: Theme.of(context).brightness == Brightness.light
            ? AppMaterials.paper
            : null,
        color: Theme.of(context).brightness == Brightness.light
            ? null
            : AppColors.of(context).surface,
        border: Border.all(color: AppColors.of(context).divider),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? AppShadows.paper
            : AppShadows.none,
      ),
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
                    Text('今日阅读', style: AppTheme.cardTitle(context: context)),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      '把今天的词放进一篇值得读完的文章',
                      style: AppTheme.mutedCaption(size: 12, context: context),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '换一批目标词',
                onPressed: loading || generating ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: AppColors.of(context).inkMuted,
                visualDensity: VisualDensity.compact,
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
                  duration: AppMotion.fast,
                  child: generating
                      ? const SizedBox(
                          key: ValueKey('reading-loading'),
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
    );
  }
}

class _InlineReadingComposer extends StatefulWidget {
  final List<PulseWordEntry> candidates;
  final List<PulseWordEntry> initialSelection;
  final Future<ReadingGenerationResult> Function(List<PulseWordEntry>)
  onGenerate;
  final VoidCallback onClose;
  final Future<void> Function(SavedArticle) onOpenArticle;

  const _InlineReadingComposer({
    super.key,
    required this.candidates,
    required this.initialSelection,
    required this.onGenerate,
    required this.onClose,
    required this.onOpenArticle,
  });

  @override
  State<_InlineReadingComposer> createState() => _InlineReadingComposerState();
}

class _InlineReadingComposerState extends State<_InlineReadingComposer> {
  static const _messages = ['正在构思自然语境', '正在检查目标词', '正在准备翻译和理解题'];

  late final Set<String> _selected = widget.initialSelection
      .map(_readingWordKey)
      .toSet();
  bool _generating = false;
  String? _error;
  int _messageIndex = 0;
  Timer? _timer;

  List<PulseWordEntry> get _selectedWords => widget.candidates
      .where((entry) => _selected.contains(_readingWordKey(entry)))
      .toList();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle(PulseWordEntry word) {
    if (_generating) return;
    final key = _readingWordKey(word);
    if (_selected.contains(key)) {
      if (_selected.length <= 3) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('至少保留 3 个词')));
        return;
      }
      setState(() => _selected.remove(key));
    } else {
      if (_selected.length >= 10) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('一篇文章最多选择 10 个词')));
        return;
      }
      setState(() => _selected.add(key));
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _generate() async {
    if (_generating || _selectedWords.length < 3) return;
    setState(() {
      _generating = true;
      _error = null;
      _messageIndex = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
    final result = await widget.onGenerate(_selectedWords);
    _timer?.cancel();
    if (!mounted) return;
    if (result.article case final article?) {
      await widget.onOpenArticle(article);
      if (mounted) widget.onClose();
      return;
    }
    setState(() {
      _generating = false;
      _error = result.error ?? '生成失败，请稍后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedWords;
    final available = widget.candidates
        .where((entry) => !_selected.contains(_readingWordKey(entry)))
        .toList();
    return AppCard(
      key: const ValueKey('reading-first-content'),
      padding: const EdgeInsets.all(AppSpacing.x4),
      color: AppColors.of(context).surface,
      child: AnimatedSwitcher(
        duration: AppMotion.medium,
        child: _generating
            ? SizedBox(
                key: const ValueKey('inline-reading-generating'),
                height: 248,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_stories_outlined,
                      size: 34,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.x5),
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: Text(
                        _messages[_messageIndex],
                        key: ValueKey(_messageIndex),
                        style: AppTheme.cardTitle(context: context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.x2,
                      runSpacing: AppSpacing.x2,
                      children: [
                        for (final word in selected)
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
                    const SizedBox(height: AppSpacing.x5),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
              )
            : Column(
                key: const ValueKey('inline-reading-selection'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TODAY\'S WORDS',
                              style: AppTheme.sectionLabel(context: context),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              '选择要在文章中复现的词',
                              style: AppTheme.cardTitle(context: context),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '收起',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _ReadingWordWrap(
                    words: selected,
                    selected: true,
                    onTap: _toggle,
                  ),
                  if (available.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.x4),
                    Text(
                      '可替换',
                      style: AppTheme.mutedCaption(size: 12, context: context),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    _ReadingWordWrap(
                      words: available.take(12).toList(),
                      selected: false,
                      onTap: _toggle,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.x3),
                    Text(
                      _error!,
                      style: AppTheme.mutedCaption(
                        size: 12,
                        color: AppColors.danger,
                        context: context,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x4),
                  SizedBox(
                    width: double.infinity,
                    child: EditorialPrimaryButton(
                      onPressed: _generate,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text('生成阅读 · ${selected.length} 词'),
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
        const SizedBox(height: AppSpacing.x3),
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
                    Divider(
                      height: 1,
                      indent: AppSpacing.x4,
                      endIndent: AppSpacing.x4,
                      color: AppColors.of(context).divider,
                    ),
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
                  for (final word in words)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x2,
                        vertical: AppSpacing.x1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.target.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        word['word'] ?? '',
                        style: AppTheme.editorial(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
              Divider(color: AppColors.of(context).divider, height: 1),
              const SizedBox(height: AppSpacing.x3),
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
                  Container(
                    constraints: const BoxConstraints(maxWidth: 72),
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
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingComposerPage extends StatefulWidget {
  final List<PulseWordEntry> candidates;
  final List<PulseWordEntry> initialSelection;
  final Future<ReadingGenerationResult> Function(List<PulseWordEntry>)
  onGenerate;
  final VoidCallback onCancelGeneration;

  const _ReadingComposerPage({
    required this.candidates,
    required this.initialSelection,
    required this.onGenerate,
    required this.onCancelGeneration,
  });

  @override
  State<_ReadingComposerPage> createState() => _ReadingComposerPageState();
}

class _ReadingComposerPageState extends State<_ReadingComposerPage> {
  static const _messages = ['正在构思自然语境', '正在让目标词自然出现', '正在准备翻译和理解题'];

  late final Set<String> _selected = widget.initialSelection
      .map(_readingWordKey)
      .toSet();
  bool _generating = false;
  String? _error;
  int _messageIndex = 0;
  int _highlightIndex = 0;
  Timer? _waitingTimer;

  List<PulseWordEntry> get _selectedWords => widget.candidates
      .where((entry) => _selected.contains(_readingWordKey(entry)))
      .toList();

  @override
  void dispose() {
    _waitingTimer?.cancel();
    super.dispose();
  }

  void _toggle(PulseWordEntry word) {
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

  void _startWaitingAnimation() {
    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted || !_generating) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _messages.length;
        final count = _selectedWords.length;
        if (count > 0) _highlightIndex = (_highlightIndex + 1) % count;
      });
    });
  }

  Future<void> _generate() async {
    final words = _selectedWords;
    if (words.length < 3 || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _messageIndex = 0;
      _highlightIndex = 0;
    });
    _startWaitingAnimation();
    final result = await widget.onGenerate(words);
    _waitingTimer?.cancel();
    if (!mounted) return;
    if (result.wasCancelled) {
      setState(() => _generating = false);
      return;
    }
    if (result.article case final article?) {
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(article: article),
        ),
      );
      return;
    }
    setState(() {
      _generating = false;
      _error = result.error ?? '生成失败，请稍后重试';
    });
  }

  Future<void> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final selectedWords = _selectedWords;
    final available = widget.candidates
        .where((entry) => !_selected.contains(_readingWordKey(entry)))
        .toList();
    return PopScope<void>(
      canPop: !_generating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _generating) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        appBar: AppBar(
          title: const Text('生成阅读'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '返回',
            onPressed: _generating
                ? _confirmCancel
                : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            child: _generating
                ? _ReadingGeneratingView(
                    key: const ValueKey('generating-reading'),
                    words: selectedWords,
                    message: _messages[_messageIndex],
                    highlightIndex: _highlightIndex,
                  )
                : CustomScrollView(
                    key: const ValueKey('select-reading-words'),
                    slivers: [
                      if (available.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.x5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '今日要复现的词',
                                  textAlign: TextAlign.center,
                                  style: AppTheme.screenHeader(
                                    context: context,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.x2),
                                Text(
                                  '已选 ${selectedWords.length} / 10 · 优先保留到期词',
                                  textAlign: TextAlign.center,
                                  style: AppTheme.mutedCaption(
                                    size: 13,
                                    context: context,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.x5),
                                _ReadingWordWrap(
                                  words: selectedWords,
                                  selected: true,
                                  alignment: WrapAlignment.center,
                                  onTap: _toggle,
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: AppSpacing.x5),
                                  _ErrorCard(message: _error!),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.x5,
                            AppSpacing.x4,
                            AppSpacing.x5,
                            AppSpacing.x8,
                          ),
                          sliver: SliverList.list(
                            children: [
                              Text(
                                '今日要复现的词',
                                style: AppTheme.screenHeader(context: context),
                              ),
                              const SizedBox(height: AppSpacing.x2),
                              Text(
                                '已选 ${selectedWords.length} / 10 · 优先保留到期词',
                                style: AppTheme.mutedCaption(
                                  size: 13,
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x4),
                              _ReadingWordWrap(
                                words: selectedWords,
                                selected: true,
                                onTap: _toggle,
                              ),
                              const SizedBox(height: AppSpacing.x8),
                              Text(
                                '可替换词',
                                style: AppTheme.cardTitle(context: context),
                              ),
                              const SizedBox(height: AppSpacing.x2),
                              Text(
                                '这些词都来自你已经学过的内容',
                                style: AppTheme.mutedCaption(
                                  size: 12,
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              _ReadingWordWrap(
                                words: available,
                                selected: false,
                                onTap: _toggle,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: AppSpacing.x5),
                                _ErrorCard(message: _error!),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        bottomNavigationBar: _generating
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x5,
                    AppSpacing.x3,
                    AppSpacing.x5,
                    AppSpacing.x3,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: FilledButton.icon(
                      onPressed: selectedWords.length >= 3 ? _generate : null,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        selectedWords.length >= 3
                            ? '生成阅读 · ${selectedWords.length} 词'
                            : '至少选择 3 个词',
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ReadingWordWrap extends StatelessWidget {
  final List<PulseWordEntry> words;
  final bool selected;
  final ValueChanged<PulseWordEntry> onTap;
  final WrapAlignment alignment;

  const _ReadingWordWrap({
    required this.words,
    required this.selected,
    required this.onTap,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
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
            backgroundColor: selected
                ? const Color(0xFFE4F7EE)
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

class _ReadingGeneratingView extends StatelessWidget {
  final List<PulseWordEntry> words;
  final String message;
  final int highlightIndex;

  const _ReadingGeneratingView({
    super.key,
    required this.words,
    required this.message,
    required this.highlightIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.x5),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            minHeight: (constraints.maxHeight - AppSpacing.x10).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFE4F7EE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: Text(
                  message,
                  key: ValueKey(message),
                  textAlign: TextAlign.center,
                  style: AppTheme.cardTitle(context: context),
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                '正在把这些词写成一篇值得读完的短文',
                textAlign: TextAlign.center,
                style: AppTheme.mutedCaption(size: 13, context: context),
              ),
              const SizedBox(height: AppSpacing.x6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x2,
                children: [
                  for (var i = 0; i < words.length; i++)
                    AnimatedContainer(
                      duration: AppMotion.fast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x3,
                        vertical: AppSpacing.x2,
                      ),
                      decoration: BoxDecoration(
                        color: i == highlightIndex
                            ? AppColors.primary
                            : const Color(0xFFE4F7EE),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        words[i].word,
                        style: TextStyle(
                          color: i == highlightIndex
                              ? Colors.white
                              : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.x6),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
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
                Wrap(
                  spacing: AppSpacing.x3,
                  runSpacing: AppSpacing.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                    duration: AppMotion.medium,
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
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easeOut,
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
      ),
    );
  }
}
