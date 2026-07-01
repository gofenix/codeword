import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';
import '../state/llm_config.dart';
import 'ai_settings_screen.dart';

/// Reading tab — AI-generated short article built from today's due
/// and new words.
///
/// Flow:
///   1. Build a pool: top 5 SM-2 due words + top 5 recommended new
///      words. This is what the user is studying today.
///   2. User taps "生成文章" → POST to the LLM with a system prompt
///      that says "write a 200-word English article on [vocab theme]
///      naturally using these 8-10 words: [word list]".
///   3. Render the article. Highlight each target word in primary
///      green so the user can spot them. Show Chinese gloss on tap.
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

  @override
  void initState() {
    super.initState();
    _loadPool();
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
      // Dedupe by word id (a "new" word can't be due; but be safe).
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
      );
      return;
    }
    if (_pool.isEmpty) {
      if (mounted) setState(() => _error = '没有可用的词。先去学几轮。');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    HapticFeedback.lightImpact();
    try {
      final vocabName =
          ref.read(vocabMetaProvider)[_pool.first.vocabId]?.name ??
              _pool.first.vocabId;
      final words = _pool.map((e) => e.word).toList();
      final system = const LlmMessage(
        role: 'system',
        content: 'You are a writing assistant for a vocabulary app. '
            'Write short, engaging English articles for programmers and '
            'AI practitioners. Use the supplied target words naturally. '
            'No preamble, no markdown — just the article text.',
      );
      final user = LlmMessage(
        role: 'user',
        content: 'Theme: $vocabName.\n'
            'Target words (use each at least once, naturally): '
            '${words.join(", ")}.\n'
            'Constraints: 180-260 words. One paragraph. No bullet points. '
            'No headings. Tone: a senior engineer explaining a concept to '
            'a junior over coffee.',
      );
      final resp = await ref.read(llmClientProvider).chat(
        LlmChatRequest(
          model: cfg.model,
          temperature: 0.7,
          maxTokens: 600,
          messages: [system, user],
        ),
      );
      if (!mounted) return;
      setState(() {
        _article = resp.content.trim();
        _generating = false;
      });
      HapticFeedback.mediumImpact();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
              const _ReadingHeader(),
              const SizedBox(height: AppSpacing.x4),
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
                  onRegenerate: _generate,
                  regenerating: _generating,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingHeader extends StatelessWidget {
  const _ReadingHeader();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读', style: AppTheme.screenHeader()),
        const SizedBox(height: 2),
        Text(
          'AI 用今天要学的词写一篇短文',
          style: AppTheme.mutedCaption(size: 13),
        ),
      ],
    );
  }
}

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
                style: AppTheme.mutedCaption(size: 13),
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
              const Icon(Icons.local_library_outlined,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.x1_5),
              Text('今日词表', style: AppTheme.cardTitle()),
              const Spacer(),
              IconButton(
                tooltip: '换一批',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh,
                    color: AppColors.inkMuted, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.danger.withValues(alpha: 0.08),
      shadow: AppShadows.none,
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(
              message,
              style: AppTheme.rowTitle()
                  .copyWith(fontSize: 13, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final label = generating
        ? '生成中…'
        : (isConfigured ? '生成文章' : '去设置 AI');
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
            : Icon(
                isConfigured ? Icons.auto_awesome : Icons.bolt,
                size: 18,
              ),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
          textStyle: AppTheme.cardTitle().copyWith(fontSize: 15),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final String article;
  final List<PulseWordEntry> pool;
  final VoidCallback onRegenerate;
  final bool regenerating;

  const _ArticleCard({
    required this.article,
    required this.pool,
    required this.onRegenerate,
    required this.regenerating,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = _highlight(article, pool);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.x1_5),
              Text('今日阅读', style: AppTheme.cardTitle()),
              const Spacer(),
              IconButton(
                tooltip: '重新生成',
                onPressed: regenerating ? null : onRegenerate,
                icon: Icon(
                  Icons.refresh,
                  color: regenerating
                      ? AppColors.inkSubtle
                      : AppColors.inkMuted,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          SelectableText.rich(
            highlighted,
            style: AppTheme.wordDisplay(size: 16, color: AppColors.ink)
                .copyWith(height: 1.7),
          ),
          const SizedBox(height: AppSpacing.x4),
          if (pool.isNotEmpty) _Glossary(pool: pool),
        ],
      ),
    );
  }

  /// Build a TextSpan tree with target words wrapped in primary green.
  /// Matches case-insensitively on word boundaries. Tolerates common
  /// suffixes (-s, -ed, -ing) by checking the lemma.
  TextSpan _highlight(String text, List<PulseWordEntry> pool) {
    final words = pool.map((e) => e.word.toLowerCase()).toList();
    final lemmas = <String, String>{}; // lemma -> original
    for (final w in words) {
      // Only stem words longer than the suffix to avoid over-stemming
      // short words like "loss" → "los" which would match "lose", "lost".
      if (w.endsWith('ies') && w.length > 4) {
        lemmas['${w.substring(0, w.length - 3)}y'] = w;
      } else if (w.endsWith('es') && w.length > 4) {
        lemmas[w.substring(0, w.length - 2)] = w;
      } else if (w.endsWith('s') && !w.endsWith('ss') && w.length > 3) {
        lemmas[w.substring(0, w.length - 1)] = w;
      } else if (w.endsWith('ed') && w.length > 4) {
        lemmas[w.substring(0, w.length - 2)] = w;
        lemmas[w.substring(0, w.length - 1)] = w; // doubled-consonant
      } else if (w.endsWith('ing') && w.length > 5) {
        lemmas[w.substring(0, w.length - 3)] = w;
        lemmas['${w.substring(0, w.length - 3)}e'] = w;
      }
      lemmas[w] = w;
    }

    // Sort lemmas by length descending so the longest match wins in the
    // regex alternation (prevents shorter lemmas from shadowing longer ones).
    final sortedLemmas = lemmas.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = sortedLemmas.map(RegExp.escape).join('|');
    if (pattern.isEmpty) {
      return TextSpan(text: text);
    }
    final re = RegExp('\\b($pattern)[a-z]*', caseSensitive: false);
    final spans = <TextSpan>[];
    var idx = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, m.start)));
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w700,
          backgroundColor: AppColors.primarySoft.withValues(alpha: 0.2),
        ),
      ));
      idx = m.end;
    }
    if (idx < text.length) {
      spans.add(TextSpan(text: text.substring(idx)));
    }
    return TextSpan(children: spans);
  }
}

class _Glossary extends StatelessWidget {
  final List<PulseWordEntry> pool;
  const _Glossary({required this.pool});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('词表', style: AppTheme.sectionLabel().copyWith(fontSize: 11)),
          const SizedBox(height: AppSpacing.x1_5),
          for (final e in pool)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: AppTheme.wordDisplay(size: 12, color: AppColors.ink),
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
                      style: const TextStyle(
                        color: AppColors.inkMuted,
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
