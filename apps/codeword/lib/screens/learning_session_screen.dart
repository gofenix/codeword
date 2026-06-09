import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/tts_service.dart';
import '../state/learning_session.dart';

class LearningSessionScreen extends ConsumerStatefulWidget {
  final String vocabId;
  /// Legacy alias for total session size. Kept so existing call sites
  /// still compile. Split 70/30 between new and review slots.
  final int count;
  const LearningSessionScreen({
    super.key,
    required this.vocabId,
    this.count = 10,
  });

  @override
  ConsumerState<LearningSessionScreen> createState() =>
      _LearningSessionScreenState();
}

class _LearningSessionScreenState
    extends ConsumerState<LearningSessionScreen> {
  late DateTime _sessionStart;
  Duration _accumulated = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    Future.microtask(() {
      // 70% new / 30% review split. The total is `count` so the
      // session feels the same size as before the split.
      final total = widget.count;
      final review = (total * 0.3).round().clamp(1, total - 1);
      final newC = total - review;
      ref.read(learningSessionProvider.notifier).start(
            vocabId: widget.vocabId,
            newCount: newC,
            reviewCount: review,
          );
    });
  }

  @override
  void dispose() {
    // Persist the accumulated study time for today. Minimum 1 minute
    // granularity — anything less rounds to 0.
    _accumulated += DateTime.now().difference(_sessionStart);
    final minutes = (_accumulated.inSeconds / 60).round();
    if (minutes > 0) {
      try {
        ReviewRepository.instance
            .addStudyMinutes(DateTime.now(), minutes);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    final meta = ref.watch(vocabMetaProvider)[widget.vocabId];
    final name = meta?.name ?? widget.vocabId;

    // Progress lives OUTSIDE the AnimatedSwitcher so it's always
    // rendered once. Otherwise a cross-fade between asking and
    // wrongDetail would briefly stack two progress bars at 50%.
    final progress = session.phase == SessionPhase.finished
        ? 1.0
        : (session.phase == SessionPhase.wrongDetail
            ? (session.currentIndex + 1) / session.questions.length
            : session.progress);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x6, AppSpacing.x3, AppSpacing.x6, AppSpacing.x4,
            ),
            child: _ProgressBar(progress: progress),
          ),
          Expanded(
            child: _PushSwitcher(
              phase: session.phase,
              child: switch (session.phase) {
                SessionPhase.loading =>
                  const Center(child: CircularProgressIndicator()),
                SessionPhase.asking => _AskingView(session: session),
                SessionPhase.wrongDetail => _WrongDetailView(session: session),
                SessionPhase.finished => _FinishedView(
                    total: session.questions.length,
                    correct: session.correctCount,
                    onClose: () => Navigator.of(context).pop(),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AskingView extends ConsumerWidget {
  final LearningSessionState session;
  const _AskingView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = session.currentQuestion!;
    final notifier = ref.read(learningSessionProvider.notifier);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar is hoisted to the Scaffold body so the
          // AnimatedSwitcher doesn't render two of them at once.
          // Scrollable top region: prompt card + audio button.
          // The options below are NOT in this scroll area, so they stay
          // anchored to the bottom regardless of prompt length.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.x2),
                  _QuestionPrompt(
                    type: q.type,
                    prompt: q.prompt,
                    word: q.word,
                    questionCount: session.questions.length,
                    currentIndex: session.currentIndex,
                  ),
                  if (q.type == QuestionType.listenPickMeaning) ...[
                    const SizedBox(height: AppSpacing.x3),
                    _AudioButton(word: q.word),
                  ],
                ],
              ),
            ),
          ),
          // Fixed options anchored to the bottom of the screen.
          // Their Y position never changes between questions, so the
          // user's tap position stays consistent (good for muscle memory).
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x6, AppSpacing.x3, AppSpacing.x6, AppSpacing.x5,
            ),
              child: Column(
              children: [
                for (var i = 0; i < q.options.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.x2),
                  _OptionTile(
                    label: String.fromCharCode(65 + i),
                    text: q.options[i],
                    onTap: () {
                      // Stronger haptic on wrong, lighter on correct —
                      // gives the user a tiny signal of their answer
                      // even before the color change registers.
                      final correct = i == q.correctIndex;
                      HapticFeedback.mediumImpact();
                      if (correct) {
                        // Light feedback on correct (slight tap).
                        HapticFeedback.lightImpact();
                      }
                      notifier.answer(i);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _WrongDetailView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const _WrongDetailView({required this.session});

  @override
  ConsumerState<_WrongDetailView> createState() => _WrongDetailViewState();
}

class _WrongDetailViewState extends ConsumerState<_WrongDetailView> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    // Read the persisted favorite state for this word.
    try {
      _isFavorite =
          ReviewRepository.instance.favorites.contains(widget.session.currentQuestion!.word.id);
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final wordId = widget.session.currentQuestion!.word.id;
    bool nowFav;
    try {
      nowFav = await ReviewRepository.instance.toggleFavorite(wordId);
    } catch (_) {
      nowFav = !_isFavorite;
    }
    if (mounted) setState(() => _isFavorite = nowFav);
  }

  Future<void> _markRemoved() async {
    final wordId = widget.session.currentQuestion!.word.id;
    try {
      await ReviewRepository.instance.markRemoved(wordId);
    } catch (_) {}
    if (mounted) {
      // Quiet acknowledgment. The user just removed a word — no need
      // to explain what 'removed' means in the toast.
      ref.read(learningSessionProvider.notifier).next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.session.currentQuestion!;
    final w = q.word;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.x5, AppSpacing.x3, AppSpacing.x5, AppSpacing.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.x2),
            Row(
              children: [
                const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
                const SizedBox(width: 6),
                const Text('答错了', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger)),
                const Spacer(),
                _FavoriteChip(
                  filled: _isFavorite,
                  onTap: _toggleFavorite,
                ),
                const SizedBox(width: 8),
                _SmallIconButton(
                  icon: Icons.remove_circle_outline,
                  label: '移除',
                  color: AppColors.danger,
                  onTap: _markRemoved,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            _HeroWordDetail(word: w),
            const SizedBox(height: AppSpacing.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => ref.read(learningSessionProvider.notifier).next(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('记住了,下一题 →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SmallIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleFactor: 0.94,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Star-shaped chip: filled = gold star, outlined = grey.
/// Uses [FavoriteStar] for a small rotate+scale transition on toggle.
class _FavoriteChip extends StatelessWidget {
  final bool filled;
  final VoidCallback onTap;
  const _FavoriteChip({required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = filled ? AppColors.warning : AppColors.inkMuted;
    return PressableScale(
      scaleFactor: 0.94,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FavoriteStar(filled: filled, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              filled ? '已收藏' : '收藏',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroWordDetail extends StatelessWidget {
  final VocabWord word;
  const _HeroWordDetail({required this.word});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PillTag.domain(word.domain.toUpperCase(), color: _domainColor(word.domain), icon: Icons.bolt),
              const SizedBox(width: 6),
              PillTag.level(word.level),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              Expanded(
                child: Text(word.word, style: AppTheme.wordDisplay(size: 28)),
              ),
              _AudioButton(word: word),
            ],
          ),
          const SizedBox(height: 2),
          Text('${word.phonetic}  ${word.pos}', style: AppTheme.phonetic()),
          const SizedBox(height: AppSpacing.x4),
          Text(word.translation, style: const TextStyle(fontSize: 16, color: AppColors.ink, fontWeight: FontWeight.w600, height: 1.5)),
          if (word.exampleEn.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x4),
            _DetailRow(label: '例句', content: word.exampleEn),
            Text(word.exampleCn, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.5)),
          ],
          if (word.synonyms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x3),
            _DetailRow(label: '同义', content: word.synonyms.join(' · ')),
          ],
          if (word.antonyms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x2),
            _DetailRow(label: '反义', content: word.antonyms.join(' · ')),
          ],
        ],
      ),
    );
  }

  Color _domainColor(String domain) {
    switch (domain) {
      case 'cs': return AppColors.domainCs;
      case 'python': return AppColors.domainPython;
      case 'ai': return AppColors.domainAi;
      case 'web': return AppColors.domainWeb;
      default: return AppColors.primary;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String content;
  const _DetailRow({required this.label, required this.content});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSubtle)),
        Expanded(child: Text(content, style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.5))),
      ],
    );
  }
}

class _AudioButton extends StatefulWidget {
  final VocabWord word;
  const _AudioButton({required this.word});

  @override
  State<_AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<_AudioButton> {
  bool _warned = false;

  @override
  void initState() {
    super.initState();
    // If the bundled audio asset is missing for this word, surface a
    // single short toast per session. No dev-talk about v0.4.5 history.
    TtsService.instance.availabilityStream.listen((ok) {
      if (!ok && mounted && !_warned) {
        _warned = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音频缺失 · 重新安装 app 可恢复'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    final ok = await TtsService.instance.speak(widget.word.id);
    if (!ok && mounted) {
      // No toast for missing audio — the once-per-session toast above
      // already covers it. This keeps the learning flow quiet.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: IconButton(
        icon: const Icon(Icons.volume_up_rounded, size: 20, color: AppColors.primary),
        onPressed: _onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }
}


class _QuestionPrompt extends StatelessWidget {
  final QuestionType type;
  final String prompt;
  final VocabWord word;
  final int questionCount;
  final int currentIndex;

  const _QuestionPrompt({
    required this.type,
    required this.prompt,
    required this.word,
    required this.questionCount,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      QuestionType.seeWordPickMeaning => '看词选义',
      QuestionType.seeMeaningPickWord => '看义选词',
      QuestionType.listenPickMeaning => '听音选义',
      QuestionType.seeContextPickWord => '语境选词',
    };
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.x5, AppSpacing.x4, AppSpacing.x5, AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkMuted, letterSpacing: 1.2)),
              Text('${currentIndex + 1} / $questionCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkMuted)),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          _promptContent(),
        ],
      ),
    );
  }

  Widget _promptContent() {
    switch (type) {
      case QuestionType.seeWordPickMeaning:
        return _WordPrompt(word: prompt, wordObj: word);
      case QuestionType.seeMeaningPickWord:
        return Text(prompt, style: const TextStyle(fontSize: 18, color: AppColors.ink, fontWeight: FontWeight.w600, height: 1.5));
      case QuestionType.listenPickMeaning:
        return _WordPrompt(word: prompt, wordObj: word);
      case QuestionType.seeContextPickWord:
        return _ContextPrompt(sentence: prompt);
    }
  }
}

class _WordPrompt extends StatelessWidget {
  final String word;
  final VocabWord wordObj;
  const _WordPrompt({required this.word, required this.wordObj});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(word, style: AppTheme.wordDisplay(size: 28)),
            const SizedBox(width: AppSpacing.x2),
            _AudioButton(word: wordObj),
          ],
        ),
        const SizedBox(height: 2),
        Text(wordObj.phonetic, style: AppTheme.phonetic()),
      ],
    );
  }
}

class _ContextPrompt extends StatelessWidget {
  final String sentence;
  const _ContextPrompt({required this.sentence});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选择划线词的正确意思:', style: TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.x3),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 16, color: AppColors.ink, height: 1.6),
            children: [
              const TextSpan(text: '...'),
              TextSpan(
                text: ' ___ ',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                ),
              ),
              TextSpan(text: sentence.substring(sentence.indexOf(' ') + 1)),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final String text;
  final VoidCallback? onTap;

  const _OptionTile({required this.label, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleFactor: 0.97,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: AppColors.inkSubtle.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${(progress * 100).round()}%',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        // TweenAnimationBuilder smoothly tweens the bar from its previous
        // value to the new one, so advancing a question feels fluid.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _FinishedView extends ConsumerWidget {
  final int total;
  final int correct;
  final VoidCallback onClose;
  const _FinishedView({required this.total, required this.correct, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pct = total == 0 ? 0 : (correct * 100 / total).round();
    final passed = pct >= 60;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(passed ? '🎉' : '💪', style: const TextStyle(fontSize: 48)),
              const SizedBox(height: AppSpacing.x4),
              Text(passed ? '本组完成' : '继续加油', style: AppTheme.wordDisplay(size: 24, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.x2),
              Text('$correct / $total  ·  正确率 $pct%', style: const TextStyle(fontSize: 14, color: AppColors.inkMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: AppSpacing.x6),
              FilledButton(onPressed: onClose, style: FilledButton.styleFrom(minimumSize: const Size(180, 48)), child: const Text('完成')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom push transition. AnimatedSwitcher's default fades the outgoing
/// widget (which is what was making the "wrong" → "detail" transition
/// look like a fade). Here we do a clean push:
///
///   1. New child slides in from the right (+0.12 → 0)
///   2. Old child slides out to the left    (0 → -0.12)
///   3. No opacity change. No fade.
///
/// 200ms easeOutCubic — punchy but not rushed.
class _PushSwitcher extends StatefulWidget {
  final SessionPhase phase;
  final Widget child;
  const _PushSwitcher({required this.phase, required this.child});

  @override
  State<_PushSwitcher> createState() => _PushSwitcherState();
}

class _PushSwitcherState extends State<_PushSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  SessionPhase? _fromPhase;
  Widget? _fromChild;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void didUpdateWidget(covariant _PushSwitcher old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) {
      // Capture the outgoing child + its phase, then animate.
      setState(() {
        _fromPhase = old.phase;
        _fromChild = old.child;
      });
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOutgoing = _fromChild != null &&
        _controller.value < 1.0 &&
        _controller.isAnimating;

    return ClipRect(
      child: Stack(
        children: [
          // Incoming: slides from +0.12 (right) to 0.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Transform.translate(
                offset: Offset(0.12 * (1.0 - t) * MediaQuery.of(context).size.width, 0),
                child: child,
              );
            },
            child: KeyedSubtree(
              key: ValueKey('in_${widget.phase}'),
              child: widget.child,
            ),
          ),
          // Outgoing: slides from 0 to -0.12 (left).
          if (showOutgoing && _fromChild != null)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                return Transform.translate(
                  offset: Offset(-0.12 * t * MediaQuery.of(context).size.width, 0),
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey('out_$_fromPhase'),
                child: _fromChild!,
              ),
            ),
        ],
      ),
    );
  }
}
