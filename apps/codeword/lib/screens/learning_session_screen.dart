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
    // Accumulate study time (minimum 1 minute granularity).
    _accumulated += DateTime.now().difference(_sessionStart);
    final minutes = (_accumulated.inSeconds / 60).round();
    if (minutes > 0) {
      try {
        ReviewRepository.instance.addStudyMinutes(DateTime.now(), minutes);
      } catch (_) {}
    }
    // Best-effort flush: dispose can't await, so we fire the flush in
    // a detached Future. In practice Flutter keeps the process alive
    // long enough for a single file write to complete. We also force
    // an eager flush after every answer (below) so dispose only has
    // to drain the "final click" delta.
    try {
      unawaited(Future.microtask(() async {
        try {
          await ReviewRepository.instance.flush();
        } catch (_) {}
      }));
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    ref.watch(vocabMetaProvider)[widget.vocabId];

    final qCount = session.questions.length;
    final progress = session.phase == SessionPhase.finished
        ? 1.0
        : (session.phase == SessionPhase.wrongDetail && qCount > 0
              ? ((session.currentIndex + 1) / qCount).clamp(0.0, 1.0)
              : session.progress.clamp(0.0, 1.0));

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
            child: switch (session.phase) {
              SessionPhase.loading => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              SessionPhase.asking => _AskingView(
                session: session,
                key: const ValueKey('asking'),
              ),
              SessionPhase.wrongDetail => _WrongDetailView(
                session: session,
                key: const ValueKey('wrong'),
              ),
              SessionPhase.finished => _FinishedView(
                key: const ValueKey('finished'),
                onClose: () => Navigator.of(context).pop(),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _AskingView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const _AskingView({required this.session, super.key});

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
    final q = widget.session.currentQuestion;
    if (q == null) return;
    final correct = i == q.correctIndex;
    setState(() {
      _selectedIndex = i;
      _locked = true;
    });
    if (correct) {
      HapticFeedback.lightImpact();
      // No auto-play on correct — the user already knows the word.
      // Audio is reserved for: (1) listening questions where audio IS
      // the prompt, (2) the wrong-answer detail card where hearing the
      // correct pronunciation helps learning. Playing here just makes
      // the flow feel laggy.
      Future.delayed(const Duration(milliseconds: 320), () {
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
    final q = session.currentQuestion;
    if (q == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
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
                  style: AppTheme.rowTitle()
                      .copyWith(fontSize: 13, color: AppColors.inkMuted),
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
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
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
                      text: q.options[i],
                      state: _optionState(i, q.correctIndex),
                      onTap: () => _onOptionTap(i),
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

class _WrongDetailView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const _WrongDetailView({
    required this.session,
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
    _refreshFavorite();
    // Auto-play the word on entry so the user hears the correct
    // pronunciation for the one they got wrong.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPlay());
  }

  void _refreshFavorite() {
    final q = widget.session.currentQuestion;
    if (q == null) {
      _isFavorite = false;
      return;
    }
    try {
      _isFavorite = ReviewRepository.instance.favorites.contains(q.word.id);
    } catch (_) {
      _isFavorite = false;
    }
  }

  @override
  void didUpdateWidget(covariant _WrongDetailView old) {
    super.didUpdateWidget(old);
    // Reset whenever the question *identity* changes, not just the
    // index. This guards against future refactors where the same
    // index might host a different word (e.g. hot-reload of the
    // catalog, swap of the questions list mid-retry build).
    final newId = widget.session.currentQuestion?.word.id;
    final oldId = old.session.currentQuestion?.word.id;
    if (widget.session.currentIndex != old.session.currentIndex ||
        newId != oldId) {
      _refreshFavorite();
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
    final q = widget.session.currentQuestion;
    if (q == null) return;
    final wordId = q.word.id;
    bool nowFav;
    try {
      nowFav = await ReviewRepository.instance.toggleFavorite(wordId);
    } catch (_) {
      nowFav = !_isFavorite;
    }
    if (mounted) setState(() => _isFavorite = nowFav);
  }

  Future<void> _markRemoved() async {
    final q = widget.session.currentQuestion;
    if (q == null) return;
    final wordId = q.word.id;
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
    final q = widget.session.currentQuestion;
    if (q == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
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
                Text(
                  '答错了',
                  style: AppTheme.mutedCaption(
                    size: 13,
                    color: AppColors.danger,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _isFavorite ? '取消收藏' : '收藏',
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _isFavorite
                        ? AppColors.warning
                        : AppColors.inkSubtle,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: AppSpacing.x3),
                IconButton(
                  tooltip: '移除',
                  onPressed: _markRemoved,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.inkSubtle,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            _ContextCard(word: w),
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
                child: Text(
                  '继续，稍后再测',
                  style: AppTheme.cardTitle()
                      .copyWith(fontSize: 16, color: AppColors.onPrimary),
                ),
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
/// Content order follows 无痛单词's English-first layout:
/// word + phonetic (small header) → English example (hero) →
/// Chinese translation → Chinese example → synonyms/antonyms.
/// No section labels — content flows naturally.
class _ContextCard extends StatelessWidget {
  final VocabWord word;

  const _ContextCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final hasExample = word.exampleEn.trim().isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Word + phonetic as a compact header, not the hero.
            Row(
              children: [
                Flexible(
                  child: Text(
                    word.word,
                    style: AppTheme.wordDisplay(size: 20),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Flexible(
                  child: Text(
                    '${word.phonetic}  ${word.pos}',
                    style: AppTheme.phonetic(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const Spacer(),
                _AudioButton(word: word),
              ],
            ),
            // English example as the hero — largest text on the card.
            if (hasExample) ...[
              const SizedBox(height: AppSpacing.x5),
              Text(
                word.exampleEn,
                style: AppTheme.wordDisplay(
                  size: 20,
                  color: AppColors.ink,
                  weight: FontWeight.w400,
                ).copyWith(height: 1.6),
              ),
              const SizedBox(height: AppSpacing.x3),
              _SentenceAudioButton(word: word),
            ],
            // Chinese translation — the answer the user got wrong.
            const SizedBox(height: AppSpacing.x5),
            Text(
              word.translation,
              style: AppTheme.cardTitle().copyWith(fontSize: 16, height: 1.5),
            ),
            // Chinese example translation (muted, supplementary).
            if (hasExample && word.exampleCn.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x2),
              Text(
                word.exampleCn,
                style: AppTheme.mutedCaption(size: 14).copyWith(height: 1.5),
              ),
            ],
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
          vertical: AppSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.volume_up_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.x1_5),
            Text(
              '播放例句',
              style: AppTheme.chipCaption(),
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
          style: AppTheme.chipCaption(color: AppColors.inkSubtle),
        ),
        Expanded(
          child: Text(
            content,
            style: AppTheme.mutedCaption(size: 13, color: AppColors.ink)
                .copyWith(height: 1.5),
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
        vertical: AppSpacing.x1_5,
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
          const SizedBox(width: AppSpacing.x1),
          Text(
            label,
            style: AppTheme.chipCaption(),
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
          style: AppTheme.screenHeader().copyWith(
            fontSize: 28,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '选择对应的英文',
          style: AppTheme.mutedCaption(size: 13, color: AppColors.inkSubtle),
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
          style: AppTheme.mutedCaption(size: 13, color: AppColors.inkSubtle),
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
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  const _OptionTile({
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
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x5,
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
              Expanded(
                child: Text(
                  text,
                  style: AppTheme.mutedCaption(
                    size: 15,
                    color: colors.text,
                  ).copyWith(fontWeight: FontWeight.w500, height: 1.4),
                ),
              ),
              if (state == _OptionState.correct)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 20),
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
          background: AppColors.surface,
          border: AppColors.primary,
          text: AppColors.primary,
        );
      case _OptionState.wrong:
        return _OptionColors(
          background: AppColors.surface,
          border: AppColors.inkSubtle.withValues(alpha: 0.15),
          text: AppColors.inkSubtle,
        );
      case _OptionState.dimmed:
        return _OptionColors(
          background: AppColors.surfaceMuted,
          border: AppColors.inkSubtle.withValues(alpha: 0.1),
          text: AppColors.inkSubtle,
        );
      case _OptionState.normal:
        return _OptionColors(
          background: AppColors.surface,
          border: AppColors.inkSubtle.withValues(alpha: 0.2),
          text: AppColors.ink,
        );
    }
  }
}

class _OptionColors {
  final Color background;
  final Color border;
  final Color text;

  const _OptionColors({
    required this.background,
    required this.border,
    required this.text,
  });
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
          style: AppTheme.rowTitle()
              .copyWith(fontSize: 12, color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.x1),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: AppSpacing.x1_5,
            backgroundColor: AppColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _FinishedView extends StatelessWidget {
  final VoidCallback onClose;
  const _FinishedView({
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '本组完成',
                style: AppTheme.wordDisplay(size: 24, color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.x6),
              FilledButton(
                onPressed: onClose,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
