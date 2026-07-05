import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_content/lib_content.dart';
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
  const ReadingScreen({super.key});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  List<PulseWordEntry> _pool = const [];
  bool _loading = true;
  bool _generating = false;
  String? _article;
  String? _error;
  List<QuizQuestion> _questions = const [];
  List<int?> _answers = const [];
  bool _generatingQuiz = false;
  List<SavedArticle> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadPool();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final h = await ArticleRepository.instance.load();
    if (mounted) {
      setState(() => _history = h);
    }
  }

  Future<void> _loadPool() async {
    setState(() => _loading = true);
    try {
      final notifier = ref.read(reviewStateProvider.notifier);
      final due = await notifier.dueWords(limit: 5);
      final fresh = await notifier.recommendedNewWords(
        limit: 5,
        catalog: ref.read(qwertyCatalogProvider),
      );
      final seen = <String>{};
      final combined = <PulseWordEntry>[];
      for (final e in [...due, ...fresh]) {
        if (seen.add('${e.vocabId}:${e.word}')) combined.add(e);
      }
      if (!mounted) return;
      setState(() {
        _pool = combined;
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

  Future<void> _generate() async {
    final cfg = ref.read(llmConfigProvider);
    if (!cfg.isConfigured) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
      return;
    }
    if (_pool.isEmpty) {
      if (mounted) {
        setState(() => _error = '没有可用的词。先去学几轮。');
      }
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
      _questions = const [];
      _answers = const [];
    });
    HapticFeedback.lightImpact();
    try {
      final vocabName =
          ref.read(vocabMetaProvider)[_pool.first.vocabId]?.name ??
          _pool.first.vocabId;
      final words = _pool.map((e) => e.word).toList();
      final system = const LlmMessage(
        role: 'system',
        content:
            'You are a writing assistant for a vocabulary learning app. '
            'Write short, engaging English articles that naturally use the '
            'supplied target words. The article should have a clear theme '
            'and tell a mini-story or explain a concept. No markdown, no '
            'preamble — just the article text.',
      );
      final user = LlmMessage(
        role: 'user',
        content:
            'Theme: $vocabName.\n'
            'Target words (use each at least once, naturally): '
            '${words.join(", ")}.\n'
            'Constraints: 180-260 words. One or two paragraphs. '
            'Write for an intermediate English learner. Make it sound like '
            'a real article someone would want to read, not a forced word '
            'list exercise.',
      );
      final resp = await ref
          .read(llmClientProvider)
          .chat(
            LlmChatRequest(
              model: cfg.model,
              temperature: 0.7,
              maxTokens: 600,
              messages: [system, user],
            ),
          );
      if (!mounted) return;
      final articleText = resp.content.trim();
      setState(() {
        _article = articleText;
        _generating = false;
      });
      HapticFeedback.mediumImpact();

      // Save to history.
      final vocabId = _pool.first.vocabId;
      final saved = SavedArticle(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        articleText: articleText,
        vocabId: vocabId,
        vocabName: vocabName,
        wordPool: _pool
            .map((e) => {
                  'word': e.word,
                  'translation': e.translation,
                  'phonetic': e.phonetic,
                })
            .toList(),
      );
      await ArticleRepository.instance.save(saved);
      _loadHistory();

      // Auto-generate quiz.
      _generateQuiz(articleText, cfg);
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e.statusCode == 401
            ? '鉴权失败 (401) · 检查 API Key'
            : e.statusCode == 404
            ? '路径错误 (404) · 检查 Base URL'
            : 'AI 调用失败 (${e.statusCode ?? '-'}): ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = '网络错误: $e';
      });
    }
  }

  Future<void> _generateQuiz(String article, LlmConfig cfg) async {
    setState(() => _generatingQuiz = true);
    try {
      final system = const LlmMessage(
        role: 'system',
        content:
            'You generate reading comprehension quizzes. Return ONLY a '
            'valid JSON array. No markdown, no explanation.',
      );
      final user = LlmMessage(
        role: 'user',
        content:
            'Article:\n$article\n\n'
            'Generate 3 multiple-choice questions in Chinese to test '
            'understanding. Each has 4 options, one correct.\n'
            'Return ONLY this JSON format: '
            '[{"q":"...","options":["...","...","...","..."],"correct":0},...]',
      );
      final resp = await ref.read(llmClientProvider).chat(
            LlmChatRequest(
              model: cfg.model,
              temperature: 0.5,
              maxTokens: 400,
              messages: [system, user],
            ),
          );
      final parsed = _parseQuiz(resp.content);
      if (mounted && parsed.isNotEmpty) {
        setState(() {
          _questions = parsed;
          _answers = List.filled(parsed.length, null);
          _generatingQuiz = false;
        });
      } else if (mounted) {
        setState(() => _generatingQuiz = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _generatingQuiz = false);
      }
    }
  }

  List<QuizQuestion> _parseQuiz(String raw) {
    try {
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start == -1 || end == -1) return const [];
      final jsonStr = raw.substring(start, end + 1);
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) {
            final m = e as Map<String, dynamic>;
            final opts = (m['options'] as List).cast<String>();
            return QuizQuestion(
              question: m['q'] as String,
              options: opts,
              correctIndex: (m['correct'] as num).toInt(),
            );
          })
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _loadSavedArticle(SavedArticle a) {
    setState(() {
      _article = a.articleText;
      _pool = a.wordPool
          .map((m) => PulseWordEntry(
                word: m['word']!,
                translation: m['translation']!,
                phonetic: m['phonetic']!,
                level: '',
                vocabId: a.vocabId,
              ))
          .toList();
      if (a.questions != null) {
        _questions = a.questions!
            .map((m) => QuizQuestion(
                  question: m['q'] as String,
                  options: (m['options'] as List).cast<String>(),
                  correctIndex: (m['correct'] as num).toInt(),
                ))
            .toList();
        _answers = List.filled(_questions.length, null);
      } else {
        _questions = const [];
        _answers = const [];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          backgroundColor: AppColors.of(context).background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          floating: false,
          pinned: true,
          title: Text(
            '阅读',
            style: AppTheme.screenHeader(context: context),
          ),
        ),
        SliverSafeArea(
          top: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x6,
              AppSpacing.x3,
              AppSpacing.x6,
              AppSpacing.x8,
            ),
            sliver: SliverList.list(
              children: [
                Text(
                  'AI 用今天要学的词写一篇短文',
                  style: AppTheme.mutedCaption(size: 13, context: context),
                ),
                const SizedBox(height: AppSpacing.x3),
                if (_history.isNotEmpty) ...[
                  _ArticleHistoryRow(
                    articles: _history,
                    onTap: _loadSavedArticle,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                ],
                if (_loading)
                  const _PoolLoading()
                else
                  _PoolCard(pool: _pool, onRefresh: _loadPool),
                const SizedBox(height: AppSpacing.x4),
                if (_error != null) ...[
                  _ErrorCard(message: _error!),
                  const SizedBox(height: AppSpacing.x4),
                ],
                _GenerateButton(
                  generating: _generating,
                  onPressed: _pool.isEmpty ? null : _generate,
                  isConfigured: ref.watch(llmConfiguredProvider),
                ),
                if (_article != null) ...[
                  const SizedBox(height: AppSpacing.x5),
                  _ArticleCard(
                    article: _article!,
                    pool: _pool,
                    vocabId: _pool.isNotEmpty ? _pool.first.vocabId : null,
                    onRegenerate: _generate,
                    regenerating: _generating,
                  ),
                ],
                if (_generatingQuiz) ...[
                  const SizedBox(height: AppSpacing.x4),
                  const _QuizLoading(),
                ],
                if (_questions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x4),
                  _ComprehensionQuiz(
                    questions: _questions,
                    answers: _answers,
                    onAnswer: (qi, oi) {
                      setState(() {
                        _answers = [..._answers];
                        _answers[qi] = oi;
                      });
                      HapticFeedback.selectionClick();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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

// ── History row ─────────────────────────────────────────────────────

class _ArticleHistoryRow extends StatelessWidget {
  final List<SavedArticle> articles;
  final ValueChanged<SavedArticle> onTap;
  const _ArticleHistoryRow({required this.articles, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '历史文章',
          style: AppTheme.sectionLabel(context: context),
        ),
        const SizedBox(height: AppSpacing.x2),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: articles.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.x3),
            itemBuilder: (context, i) {
              final a = articles[i];
              final date =
                  '${a.createdAt.month}/${a.createdAt.day}';
              final preview = a.articleText
                  .replaceAll('\n', ' ')
                  .characters
                  .take(40)
                  .toString();
              return AppCard(
                onTap: () => onTap(a),
                padding: const EdgeInsets.all(AppSpacing.x3),
                child: SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            date,
                            style: AppTheme.mutedCaption(
                              size: 11,
                              context: context,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            a.vocabName,
                            style: AppTheme.mutedCaption(
                              size: 10,
                              context: context,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x1_5),
                      Text(
                        preview,
                        style: AppTheme.mutedCaption(
                          size: 12,
                          color: AppColors.of(context).ink,
                          context: context,
                        ).copyWith(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Pool loading & card ─────────────────────────────────────────────

class _PoolLoading extends StatelessWidget {
  const _PoolLoading();
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        height: 80,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Text(
                '加载今日词表…',
                style: AppTheme.mutedCaption(size: 13, context: context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  final List<PulseWordEntry> pool;
  final VoidCallback onRefresh;
  const _PoolCard({required this.pool, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_library_outlined,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.x1_5),
              Text('今日词表', style: AppTheme.cardTitle(context: context)),
              const Spacer(),
              IconButton(
                tooltip: '换一批',
                onPressed: onRefresh,
                icon: Icon(
                  Icons.refresh,
                  color: AppColors.of(context).inkMuted,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          if (pool.isEmpty)
            const EmptyHint(
              icon: Icons.local_library_outlined,
              message: '没有可用的词。先去学几轮再回来。',
            )
          else
            Wrap(
              spacing: AppSpacing.x1_5,
              runSpacing: AppSpacing.x1_5,
              children: [
                for (final e in pool)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x2 + 2,
                      vertical: AppSpacing.x1_5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      e.word,
                      style: AppTheme.wordDisplay(
                        size: 13,
                        color: AppColors.primaryDark,
                        weight: FontWeight.w700,
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

// ── Generate button ─────────────────────────────────────────────────

class _GenerateButton extends StatelessWidget {
  final bool generating;
  final bool isConfigured;
  final VoidCallback? onPressed;
  const _GenerateButton({
    required this.generating,
    required this.isConfigured,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final label = generating ? '生成中…' : (isConfigured ? '生成文章' : '去设置 AI');
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: generating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : Icon(isConfigured ? Icons.auto_awesome : Icons.bolt, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
          textStyle: AppTheme.cardTitle().copyWith(fontSize: 15),
        ),
      ),
    );
  }
}

// ── Quiz loading ────────────────────────────────────────────────────

class _QuizLoading extends StatelessWidget {
  const _QuizLoading();
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Text(
            '生成阅读理解题…',
            style: AppTheme.mutedCaption(size: 13, context: context),
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
              Text(
                '阅读理解',
                style: AppTheme.cardTitle(context: context),
              ),
              const Spacer(),
              if (answered == questions.length)
                Text(
                  '$correct / ${questions.length}',
                  style: AppTheme.mutedCaption(
                    size: 13,
                    context: context,
                  ).copyWith(
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

// ── Article card with tappable words ────────────────────────────────

class _ArticleCard extends ConsumerStatefulWidget {
  final String article;
  final List<PulseWordEntry> pool;
  final String? vocabId;
  final VoidCallback onRegenerate;
  final bool regenerating;

  const _ArticleCard({
    required this.article,
    required this.pool,
    required this.vocabId,
    required this.onRegenerate,
    required this.regenerating,
  });

  @override
  ConsumerState<_ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends ConsumerState<_ArticleCard> {
  List<VocabWord> _fullVocab = const [];
  bool _vocabLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadVocab();
  }

  Future<void> _loadVocab() async {
    final vid = widget.vocabId;
    if (vid == null) return;
    try {
      final words = await ContentLoader.loadList(vid);
      if (mounted) {
        setState(() {
          _fullVocab = words;
          _vocabLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _vocabLoaded = true);
      }
    }
  }

  VocabWord? _lookupInVocab(String word) {
    final lower = word.toLowerCase();
    for (final w in _fullVocab) {
      if (w.word.toLowerCase() == lower) return w;
    }
    return null;
  }

  PulseWordEntry? _lookupInPool(String word) {
    final lower = word.toLowerCase();
    for (final e in widget.pool) {
      if (e.word.toLowerCase() == lower) return e;
    }
    return null;
  }

  void _onWordTap(String word) {
    final poolEntry = _lookupInPool(word);
    final vocabEntry = _lookupInVocab(word);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WordDefinitionSheet(
        word: word,
        poolEntry: poolEntry,
        vocabEntry: vocabEntry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetWords = widget.pool.map((e) => e.word.toLowerCase()).toSet();
    final tokens = _tokenize(widget.article);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.x1_5),
              Text('今日阅读', style: AppTheme.cardTitle(context: context)),
              const Spacer(),
              IconButton(
                tooltip: '重新生成',
                onPressed: widget.regenerating ? null : widget.onRegenerate,
                icon: Icon(
                  Icons.refresh,
                  color: widget.regenerating
                      ? AppColors.of(context).inkSubtle
                      : AppColors.of(context).inkMuted,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Wrap(
            spacing: 2,
            runSpacing: 4,
            children: [
              for (final token in tokens)
                if (token.isWhitespace)
                  const SizedBox(width: 4)
                else if (token.isPunctuation)
                  Text(
                    token.text,
                    style: AppTheme.wordDisplay(
                      size: 16,
                      color: AppColors.of(context).ink,
                      context: context,
                    ).copyWith(height: 1.7),
                  )
                else
                  _TappableWord(
                    text: token.text,
                    isTarget: targetWords.contains(
                      token.text.toLowerCase().replaceAll(RegExp(r'[^\w]'), ''),
                    ),
                    onTap: () => _onWordTap(token.text),
                  ),
            ],
          ),
          if (!_vocabLoaded) ...[
            const SizedBox(height: AppSpacing.x3),
            Text(
              '加载词书中，点击更多词可查释义…',
              style: AppTheme.mutedCaption(size: 11, context: context),
            ),
          ],
          const SizedBox(height: AppSpacing.x4),
          if (widget.pool.isNotEmpty) _Glossary(pool: widget.pool),
        ],
      ),
    );
  }
}

List<_Token> _tokenize(String text) {
  final tokens = <_Token>[];
  final buffer = StringBuffer();
  const punctuation = '.,;:!?()[]"\'/\\-';
  for (final ch in text.characters) {
    if (ch.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        tokens.add(_Token.word(buffer.toString()));
        buffer.clear();
      }
      tokens.add(const _Token.whitespace());
    } else if (punctuation.contains(ch)) {
      if (buffer.isNotEmpty) {
        tokens.add(_Token.word(buffer.toString()));
        buffer.clear();
      }
      tokens.add(_Token.punctuation(ch));
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isNotEmpty) {
    tokens.add(_Token.word(buffer.toString()));
  }
  return tokens;
}

class _Token {
  final String text;
  final bool isWhitespace;
  final bool isPunctuation;
  const _Token.word(this.text)
      : isWhitespace = false,
        isPunctuation = false;
  const _Token.whitespace()
      : text = ' ',
        isWhitespace = true,
        isPunctuation = false;
  const _Token.punctuation(this.text)
      : isWhitespace = false,
        isPunctuation = true;
}

// ── Tappable word widget ────────────────────────────────────────────

class _TappableWord extends StatelessWidget {
  final String text;
  final bool isTarget;
  final VoidCallback onTap;
  const _TappableWord({
    required this.text,
    required this.isTarget,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTheme.wordDisplay(
      size: 16,
      color: AppColors.of(context).ink,
      context: context,
    ).copyWith(height: 1.7);

    if (isTarget) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: baseStyle.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Text(text, style: baseStyle),
    );
  }
}

// ── Word definition bottom sheet ────────────────────────────────────

class _WordDefinitionSheet extends StatelessWidget {
  final String word;
  final PulseWordEntry? poolEntry;
  final VocabWord? vocabEntry;
  const _WordDefinitionSheet({
    required this.word,
    required this.poolEntry,
    required this.vocabEntry,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = poolEntry != null || vocabEntry != null;
    final displayWord = vocabEntry?.word ?? poolEntry?.word ?? word;
    final phonetic = vocabEntry?.phonetic ?? poolEntry?.phonetic ?? '';
    final pos = vocabEntry?.pos ?? '';
    final translation =
        vocabEntry?.translation ?? poolEntry?.translation ?? '';
    final exampleEn = vocabEntry?.exampleEn ?? '';
    final exampleCn = vocabEntry?.exampleCn ?? '';

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
                    color: AppColors.of(context).inkSubtle.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayWord,
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
                      TtsService.instance.speak(text: displayWord);
                    },
                  ),
                ],
              ),
              if (phonetic.isNotEmpty || pos.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x1_5),
                Text(
                  [phonetic, pos].where((s) => s.isNotEmpty).join('  '),
                  style: AppTheme.phonetic(fontSize: 15, context: context),
                ),
              ],
              if (translation.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x3),
                Text(
                  translation,
                  style: AppTheme.cardTitle(context: context).copyWith(
                    fontSize: 17,
                    height: 1.5,
                  ),
                ),
              ],
              if (exampleEn.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.x3),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exampleEn,
                        style: AppTheme.mutedCaption(
                          size: 14,
                          color: AppColors.of(context).ink,
                          context: context,
                        ).copyWith(fontStyle: FontStyle.italic, height: 1.5),
                      ),
                      if (exampleCn.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.x1_5),
                        Text(
                          exampleCn,
                          style: AppTheme.mutedCaption(
                            size: 13,
                            context: context,
                          ).copyWith(height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (!hasData) ...[
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

// ── Glossary ────────────────────────────────────────────────────────

class _Glossary extends StatelessWidget {
  final List<PulseWordEntry> pool;
  const _Glossary({required this.pool});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '词表',
            style: AppTheme.sectionLabel(
              context: context,
            ).copyWith(fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.x1_5),
          for (final e in pool)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: AppTheme.wordDisplay(
                    size: 12,
                    color: AppColors.of(context).ink,
                  ),
                  children: [
                    TextSpan(
                      text: '${e.word}  ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    TextSpan(
                      text: e.translation,
                      style: TextStyle(
                        color: AppColors.of(context).inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
