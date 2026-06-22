import 'dart:async';

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

class _LearningSessionScreenState extends ConsumerState<LearningSessionScreen> {
  late DateTime _sessionStart;
  Duration _accumulated = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    Future.microtask(() {
      ref.read(learningSessionProvider.notifier).start(vocabId: widget.vocabId);
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
        ReviewRepository.instance.addStudyMinutes(DateTime.now(), minutes);
      } catch (_) {}
    }
    // Flush any pending debounced writes (review state, activity) so
    // data isn't lost if the user kills the app right after answering.
    try {
      ReviewRepository.instance.flush();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    ref.watch(vocabMetaProvider)[widget.vocabId];

    final progress = session.phase == SessionPhase.finished
        ? 1.0
        : (session.phase == SessionPhase.wrongDetail
              ? (session.currentIndex + 1) / session.questions.length
              : session.progress);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const SizedBox.shrink(),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          // Thin progress bar pinned to the very top, behind the AppBar.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x6,
              0,
              AppSpacing.x6,
              0,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.x10),
                child: _ProgressBar(progress: progress),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: switch (session.phase) {
                SessionPhase.loading => const Center(
                  child: CircularProgressIndicator(),
                ),
                SessionPhase.asking => _AskingView(
                  session: session,
                  vocabId: widget.vocabId,
                  key: const ValueKey('asking'),
                ),
                SessionPhase.wrongDetail => _WrongDetailView(
                  session: session,
                  vocabId: widget.vocabId,
                  key: const ValueKey('wrong'),
                ),
                SessionPhase.finished => _FinishedView(
                  key: const ValueKey('finished'),
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

class _AskingView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  final String vocabId;
  const _AskingView({required this.session, required this.vocabId, super.key});

  @override
  ConsumerState<_AskingView> createState() => _AskingViewState();
}

class _AskingViewState extends ConsumerState<_AskingView> {
  String? _lastWordId;
  int? _selectedIndex;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    // Auto-play on mount. Slight delay so the question card animates in
    // before audio starts (a touch less jarring than a simultaneous
    // flash + bang).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPlay());
  }

  @override
  void didUpdateWidget(covariant _AskingView old) {
    super.didUpdateWidget(old);
    if (widget.session.currentIndex != old.session.currentIndex) {
      // New question — reset feedback state.
      _selectedIndex = null;
      _locked = false;
      _maybeAutoPlay();
    }
  }

  void _maybeAutoPlay() {
    final q = widget.session.currentQuestion;
    if (q == null) return;
    if (q.word.id == _lastWordId) return;
    _lastWordId = q.word.id;
    // Only auto-play when audio IS the prompt (listening question).
    // For the other two question types, auto-playing would either
    // give away the answer (seeMeaningPickWord) or distract from
    // the written text the user is supposed to read
    // (seeWordPickMeaning). The audio button is still on screen so
    // the user can opt in to hear pronunciation as a hint.
    if (q.type != QuestionType.listenPickMeaning) return;
    TtsService.instance.speak(text: q.word.word);
  }

  void _onOptionTap(int i) {
    if (_locked) return;
    final q = widget.session.currentQuestion!;
    final correct = i == q.correctIndex;
    setState(() {
      _selectedIndex = i;
      _locked = true;
    });
    if (correct) {
      HapticFeedback.lightImpact();
      // Positive reinforcement: play the word on every correct answer.
      TtsService.instance.speak(text: q.word.word);
      Future.delayed(const Duration(milliseconds: 750), () {
        if (!mounted) return;
        ref.read(learningSessionProvider.notifier).answer(i);
      });
    } else {
      HapticFeedback.heavyImpact();
      // Brief pause so the user sees the red highlight before the
      // immersive wrong-answer card takes over.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        ref.read(learningSessionProvider.notifier).answer(i);
      });
    }
  }

  _OptionState _optionState(int i, int correctIndex) {
    if (_selectedIndex == null) return _OptionState.normal;
    if (i == _selectedIndex) {
      return i == correctIndex ? _OptionState.correct : _OptionState.wrong;
    }
    return _OptionState.dimmed;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final q = session.currentQuestion!;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x6,
              AppSpacing.x4,
              AppSpacing.x6,
              0,
            ),
            child: Row(
              children: [
                _QuestionTypeChip(type: q.type),
                const Spacer(),
                Text(
                  '${session.currentIndex + 1} / ${session.questions.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          // Center stage: the big word (or meaning) the user has to
          // resolve. Everything else fades behind it.
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x6,
                ),
                child: _QuestionStage(
                  type: q.type,
                  prompt: q.prompt,
                  word: q.word,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.x5,
              AppSpacing.x3,
              AppSpacing.x5,
              AppSpacing.x4 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              children: [
                for (var i = 0; i < q.options.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.x2),
                  _OptionTile(
                    label: String.fromCharCode(65 + i),
                    text: q.options[i],
                    state: _optionState(i, q.correctIndex),
                    onTap: () => _onOptionTap(i),
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
  final String vocabId;
  const _WrongDetailView({
    required this.session,
    required this.vocabId,
    super.key,
  });

  @override
  ConsumerState<_WrongDetailView> createState() => _WrongDetailViewState();
}

class _WrongDetailViewState extends ConsumerState<_WrongDetailView> {
  bool _isFavorite = false;
  String? _lastWordId;

  @override
  void initState() {
    super.initState();
    // Read the persisted favorite state for this word.
    try {
      _isFavorite = ReviewRepository.instance.favorites.contains(
        widget.session.currentQuestion!.word.id,
      );
    } catch (_) {}
    // Auto-play the word on entry so the user hears the correct
    // pronunciation for the one they got wrong.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPlay());
  }

  @override
  void didUpdateWidget(covariant _WrongDetailView old) {
    super.didUpdateWidget(old);
    if (widget.session.currentIndex != old.session.currentIndex) {
      _maybeAutoPlay();
    }
  }

  void _maybeAutoPlay() {
    final q = widget.session.currentQuestion;
    if (q == null) return;
    if (q.word.id == _lastWordId) return;
    _lastWordId = q.word.id;
    TtsService.instance.speak(text: q.word.word);
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
      ref.read(learningSessionProvider.notifier).next(skipRetry: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.session.currentQuestion!;
    final w = q.word;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x6,
          AppSpacing.x3,
          AppSpacing.x6,
          AppSpacing.x6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.x2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x3,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.cancel_rounded,
                        color: AppColors.danger,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '答错了',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _FavoriteChip(filled: _isFavorite, onTap: _toggleFavorite),
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
            _ContextCard(word: w, vocabId: widget.vocabId),
            const SizedBox(height: AppSpacing.x5),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    ref.read(learningSessionProvider.notifier).next(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text(
                  '继续，稍后再测',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
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

/// Immersive wrong-answer context card.
///
/// Shows the word, then the example sentence above the definition so the
/// user can learn from context. Whole-sentence TTS is available when an
/// English example exists.
class _ContextCard extends ConsumerWidget {
  final VocabWord word;
  final String vocabId;

  const _ContextCard({required this.word, required this.vocabId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(vocabMetaProvider)[vocabId];
    final hasExample = word.exampleEn.trim().isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PillTag.domain(
                  meta?.name ?? vocabId,
                  color: _domainColor(word.domain),
                  icon: Icons.bolt,
                ),
                const SizedBox(width: 6),
                PillTag.level(word.level),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    word.word,
                    style: AppTheme.wordDisplay(size: 32),
                  ),
                ),
                _AudioButton(word: word),
              ],
            ),
            const SizedBox(height: 2),
            Text('${word.phonetic}  ${word.pos}', style: AppTheme.phonetic()),
            if (hasExample) ...[
              const SizedBox(height: AppSpacing.x5),
              _SectionTitle(icon: Icons.format_quote_rounded, label: '例句'),
              const SizedBox(height: AppSpacing.x3),
              Text(
                word.exampleEn,
                style: const TextStyle(
                  fontSize: 17,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                word.exampleCn,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.x3),
              _SentenceAudioButton(word: word),
            ],
            const SizedBox(height: AppSpacing.x5),
            _SectionTitle(icon: Icons.translate_rounded, label: '释义'),
            const SizedBox(height: AppSpacing.x3),
            Text(
              word.translation,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            if (word.synonyms.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x4),
              _DetailRow(label: '同义', content: word.synonyms.join(' · ')),
            ],
            if (word.antonyms.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x2),
              _DetailRow(label: '反义', content: word.antonyms.join(' · ')),
            ],
          ],
        ),
      ),
    );
  }

  Color _domainColor(String domain) {
    final h = domain.hashCode.abs();
    return AppColors.qwertyPalette[h % AppColors.qwertyPalette.length];
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _SentenceAudioButton extends StatelessWidget {
  final VocabWord word;

  const _SentenceAudioButton({required this.word});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleFactor: 0.96,
      onTap: () {
        HapticFeedback.lightImpact();
        TtsService.instance.speak(text: word.exampleEn);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.volume_up_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            SizedBox(width: 6),
            Text(
              '播放例句',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
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
        Text(
          '$label  ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSubtle,
          ),
        ),
        Expanded(
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.ink,
              height: 1.5,
            ),
          ),
        ),
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
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '播放发音',
      icon: const Icon(Icons.volume_up_outlined),
      onPressed: () async {
        HapticFeedback.lightImpact();
        await TtsService.instance.speak(text: widget.word.word);
      },
    );
  }
}

class _QuestionTypeChip extends StatelessWidget {
  final QuestionType type;
  const _QuestionTypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      QuestionType.seeWordPickMeaning => '看词选义',
      QuestionType.seeMeaningPickWord => '看义选词',
      QuestionType.listenPickMeaning => '听音选义',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.bolt_rounded,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The big, centered prompt — this is what the user is solving right
/// now. Word, meaning, or "tap to hear" depending on question type.
class _QuestionStage extends StatelessWidget {
  final QuestionType type;
  final String prompt;
  final VocabWord word;

  const _QuestionStage({
    required this.type,
    required this.prompt,
    required this.word,
  });

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case QuestionType.seeWordPickMeaning:
        return _WordStage(word: word);
      case QuestionType.seeMeaningPickWord:
        return _MeaningStage(meaning: prompt, word: word);
      case QuestionType.listenPickMeaning:
        return _ListenStage(word: word);
    }
  }
}

class _WordStage extends StatelessWidget {
  final VocabWord word;
  const _WordStage({required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          word.word,
          textAlign: TextAlign.center,
          style: AppTheme.wordDisplay(size: 56, weight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(word.phonetic, style: AppTheme.phonetic(fontSize: 16)),
      ],
    );
  }
}

class _MeaningStage extends StatelessWidget {
  final String meaning;
  final VocabWord word;
  const _MeaningStage({required this.meaning, required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          meaning,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '选择对应的英文',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.inkSubtle,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ListenStage extends StatelessWidget {
  final VocabWord word;
  const _ListenStage({required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LargePlayButton(word: word),
        const SizedBox(height: AppSpacing.x4),
        Text(
          '点击播放发音',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.inkSubtle,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LargePlayButton extends StatelessWidget {
  final VocabWord word;
  const _LargePlayButton({required this.word});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleFactor: 0.95,
      onTap: () {
        HapticFeedback.lightImpact();
        TtsService.instance.speak(text: word.word);
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.volume_up_rounded,
          size: 56,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

enum _OptionState { normal, correct, wrong, dimmed }

class _OptionTile extends StatelessWidget {
  final String label;
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.label,
    required this.text,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _colors();
    return PressableScale(
      scaleFactor: state == _OptionState.normal ? 0.97 : 1.0,
      onTap: state == _OptionState.normal ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: colors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.badgeBg,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.badgeText,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.text,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              if (state == _OptionState.correct)
                const Icon(Icons.check_circle_rounded, color: AppColors.success),
              if (state == _OptionState.wrong)
                const Icon(Icons.cancel_rounded, color: AppColors.danger),
            ],
          ),
        ),
      ),
    );
  }

  _OptionColors _colors() {
    switch (state) {
      case _OptionState.correct:
        return _OptionColors(
          background: AppColors.success.withValues(alpha: 0.1),
          border: AppColors.success.withValues(alpha: 0.4),
          badgeBg: AppColors.success.withValues(alpha: 0.15),
          badgeText: AppColors.success,
          text: AppColors.success,
        );
      case _OptionState.wrong:
        return _OptionColors(
          background: AppColors.danger.withValues(alpha: 0.1),
          border: AppColors.danger.withValues(alpha: 0.4),
          badgeBg: AppColors.danger.withValues(alpha: 0.15),
          badgeText: AppColors.danger,
          text: AppColors.danger,
        );
      case _OptionState.dimmed:
        return _OptionColors(
          background: AppColors.surface,
          border: AppColors.inkSubtle.withValues(alpha: 0.15),
          badgeBg: AppColors.surfaceMuted,
          badgeText: AppColors.inkSubtle,
          text: AppColors.inkSubtle,
        );
      case _OptionState.normal:
        return _OptionColors(
          background: AppColors.surface,
          border: AppColors.inkSubtle.withValues(alpha: 0.2),
          badgeBg: AppColors.primary.withValues(alpha: 0.1),
          badgeText: AppColors.primary,
          text: AppColors.ink,
        );
    }
  }
}

class _OptionColors {
  final Color background;
  final Color border;
  final Color badgeBg;
  final Color badgeText;
  final Color text;

  const _OptionColors({
    required this.background,
    required this.border,
    required this.badgeBg,
    required this.badgeText,
    required this.text,
  });
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: progress),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishedView extends ConsumerWidget {
  final int total;
  final int correct;
  final VoidCallback onClose;
  const _FinishedView({
    required this.total,
    required this.correct,
    required this.onClose,
    super.key,
  });

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
              Text(
                passed ? '本组完成' : '继续加油',
                style: AppTheme.wordDisplay(size: 24, color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                '$correct / $total  ·  正确率 $pct%',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.x6),
              FilledButton(
                onPressed: onClose,
                style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
