import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/tts_service.dart';
import '../state/learning_preferences.dart';
import '../state/learning_session.dart';

/// Compute a font size for [text] that fits within a phone-width budget.
/// [maxSize] is used for short text; longer text scales down proportionally.
double fitFontSize(String text, double maxSize, {int referenceChars = 10}) {
  final len = text.characters.length;
  if (len <= referenceChars) return maxSize;
  return (maxSize * referenceChars / len).clamp(18.0, maxSize);
}

class LearningSessionScreen extends ConsumerStatefulWidget {
  final String vocabId;

  const LearningSessionScreen({super.key, required this.vocabId});

  @override
  ConsumerState<LearningSessionScreen> createState() =>
      _LearningSessionScreenState();
}

class _LearningSessionScreenState extends ConsumerState<LearningSessionScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      await ref
          .read(learningSessionProvider.notifier)
          .start(vocabId: widget.vocabId);
    });
  }

  @override
  void dispose() {
    // Best-effort flush on exit. Session timing is recorded centrally by
    // LearningSessionNotifier when a round finishes.
    try {
      unawaited(
        Future.microtask(() async {
          try {
            await ReviewRepository.instance.flush();
          } catch (_) {}
        }),
      );
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    final mode = ref.watch(learningPreferencesProvider).learningMode;
    ref.watch(vocabMetaProvider)[widget.vocabId];

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: DecoratedBox(
        decoration: AppMaterials.canvasDecoration(context),
        child: SafeArea(
            child: Stack(
              // Full-size constraints so shrink-wrapping phase views
              // (loading spinner, swipe pager, empty state) stay
              // centered instead of hugging the leading edge.
              fit: StackFit.expand,
              children: [
                // Crossfade between session phases (loading → asking →
                // wrongDetail → finished) so the high-frequency learning
                // loop never hard-cuts. Reduced-motion skips the fade.
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : AppMotion.medium,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: AppMotion.easeOut,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: switch (session.phase) {
                    SessionPhase.loading => const Center(
                      key: ValueKey('loading'),
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                    SessionPhase.asking => mode == LearningMode.swipe
                        ? SwipeView(
                            session: session,
                            key: const ValueKey('swipe'),
                          )
                        : AskingView(
                            session: session,
                            key: const ValueKey('asking'),
                          ),
                    SessionPhase.wrongDetail => WrongDetailView(
                      session: session,
                      key: const ValueKey('wrong'),
                    ),
                    SessionPhase.finished => const _FinishedView(
                      key: ValueKey('finished'),
                    ),
                  },
                ),
                if (session.phase == SessionPhase.asking ||
                    session.phase == SessionPhase.wrongDetail)
                  Positioned(
                    top: AppSpacing.x2,
                    right: AppSpacing.x3,
                    child: ModeToggleButton(current: mode),
                  ),
              ],
            ),
          ),
        ),
    );
  }
}

class ModeToggleButton extends ConsumerWidget {
  final LearningMode current;
  const ModeToggleButton({required this.current, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSwipe = current == LearningMode.swipe;
    return AppGlassIconButton(
      tooltip: isSwipe ? '切换到选择题' : '切换到卡片',
      icon: isSwipe ? Icons.quiz_outlined : Icons.swipe_vertical_rounded,
      size: 20,
      color: AppColors.of(context).inkMuted,
      onPressed: () {
        HapticFeedback.selectionClick();
        ref
            .read(learningPreferencesProvider.notifier)
            .setLearningMode(isSwipe ? LearningMode.quiz : LearningMode.swipe);
      },
    );
  }
}

class AskingView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const AskingView({required this.session, super.key});

  @override
  ConsumerState<AskingView> createState() => _AskingViewState();
}

class _AskingViewState extends ConsumerState<AskingView> {
  String? _lastAutoPlayedQuestion;
  int? _selectedIndex;
  bool _locked = false;
  bool? _typedCorrect;
  final _typingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-play on mount. Slight delay so the question card animates in
    // before audio starts (a touch less jarring than a simultaneous
    // flash + bang).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPlay());
  }

  @override
  void didUpdateWidget(covariant AskingView old) {
    super.didUpdateWidget(old);
    if (_questionIdentity(widget.session.currentQuestion) !=
        _questionIdentity(old.session.currentQuestion)) {
      // New question — reset feedback state.
      _selectedIndex = null;
      _locked = false;
      _typedCorrect = null;
      _typingController.clear();
      _maybeAutoPlay();
    }
  }

  @override
  void dispose() {
    _typingController.dispose();
    super.dispose();
  }

  void _maybeAutoPlay() {
    final q = widget.session.currentQuestion;
    if (q == null) return;
    final identity = _questionIdentity(q);
    if (identity == _lastAutoPlayedQuestion) return;
    _lastAutoPlayedQuestion = identity;
    // Only auto-play when audio IS the prompt (listening question).
    // For the other two question types, auto-playing would either
    // give away the answer (seeMeaningPickWord) or distract from
    // the written text the user is supposed to read
    // (seeWordPickMeaning). The audio button is still on screen so
    // the user can opt in to hear pronunciation as a hint.
    if (q.type != QuestionType.listenPickMeaning) return;
    TtsService.instance.speak(text: q.word.word);
  }

  String? _questionIdentity(LearningQuestion? question) {
    if (question == null) return null;
    return '${question.word.id}:${question.type.name}:${question.attemptNo}';
  }

  void _onOptionTap(int i) {
    if (_locked) return;
    final q = widget.session.currentQuestion;
    if (q == null) return;
    final questionIdentity = _questionIdentity(q);
    final correct = i == q.correctIndex;
    setState(() {
      _selectedIndex = i;
      _locked = true;
    });
    if (correct) {
      HapticFeedback.lightImpact();
      Future.delayed(_answerDelay(correct), () {
        if (!mounted || !_isCurrentQuestion(questionIdentity)) return;
        ref.read(learningSessionProvider.notifier).answer(i);
      });
    } else {
      HapticFeedback.heavyImpact();
      Future.delayed(_answerDelay(correct), () {
        if (!mounted || !_isCurrentQuestion(questionIdentity)) return;
        ref.read(learningSessionProvider.notifier).answer(i);
      });
    }
  }

  /// Answer-feedback delay, collapsed under reduced motion so the
  /// high-frequency loop never waits on vestibular motion (§14).
  Duration _answerDelay(bool correct) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return Duration.zero;
    return correct ? AppMotion.answerCorrect : AppMotion.answerWrong;
  }

  void _submitTyped() {
    if (_locked || _typingController.text.trim().isEmpty) return;
    final q = widget.session.currentQuestion;
    if (q == null) return;
    final questionIdentity = _questionIdentity(q);
    final submitted = _typingController.text;
    final correct =
        submitted.trim().toLowerCase() == q.word.word.trim().toLowerCase();
    setState(() {
      _locked = true;
      _typedCorrect = correct;
    });
    correct ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    Future.delayed(
      _answerDelay(correct),
      () {
        if (!mounted || !_isCurrentQuestion(questionIdentity)) return;
        ref.read(learningSessionProvider.notifier).answerTyped(submitted);
      },
    );
  }

  bool _isCurrentQuestion(String? identity) {
    return _questionIdentity(
          ref.read(learningSessionProvider).currentQuestion,
        ) ==
        identity;
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
    if (q.type == QuestionType.typeWord) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
        child: Column(
          children: [
            // Same vertical rhythm as the choice questions: prompt band
            // sits at 3/13 from the top so switching between typing and
            // picking never moves the prompt.
            const Spacer(flex: 3),
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Center(
                  child: _QuestionStage(
                    type: q.type,
                    prompt: q.prompt,
                    word: q.word,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: AppSpacing.x6 + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextField(
                      controller: _typingController,
                      autofocus: true,
                      enabled: !_locked,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _submitTyped(),
                      decoration: InputDecoration(
                        hintText: '输入英文单词',
                        prefixIcon: const Icon(Icons.keyboard_rounded),
                        suffixIcon: _typedCorrect == null
                            ? null
                            : Icon(
                                _typedCorrect!
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                color: _typedCorrect!
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    SizedBox(
                      width: double.infinity,
                      child: EditorialPrimaryButton(
                        onPressed: _locked ? null : _submitTyped,
                        minHeight: 52,
                        label: const Text('确认'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
      child: Column(
        children: [
          // Mirror the swipe page's vertical rhythm: the word hero sits
          // at ~35% from the top (Spacer flex 3 of 7) so switching modes
          // doesn't make the word jump.
          const Spacer(flex: 3),
          // The word / meaning — the only thing the user should look at.
          // Expanded (not Flexible) locks this region to a fixed 4/13 of
          // the viewport so the option list below never shifts up when a
          // shorter prompt (e.g. a meaning) takes less vertical space.
          // Center keeps the prompt vertically centred inside that fixed
          // band, so question types with different intrinsic heights share
          // one stable visual anchor.
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              child: Center(
                child: _QuestionStage(
                  type: q.type,
                  prompt: q.prompt,
                  word: q.word,
                ),
              ),
            ),
          ),
          // Options sit right below, no gap.
          Expanded(
            flex: 6,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: AppSpacing.x6 + MediaQuery.of(context).padding.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < q.options.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.x3),
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
            ),
          ),
        ],
      ),
    );
  }
}

class WrongDetailView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const WrongDetailView({required this.session, super.key});

  @override
  ConsumerState<WrongDetailView> createState() => _WrongDetailViewState();
}

class _WrongDetailViewState extends ConsumerState<WrongDetailView> {
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
  void didUpdateWidget(covariant WrongDetailView old) {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除该词？'),
        content: Text(
          '「${q.word.word}」将不再出现在学习队列中，可在设置中恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              '移除',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final wordId = q.word.id;
    try {
      await ReviewRepository.instance.markRemoved(wordId);
    } catch (_) {}
    if (mounted) {
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
    final hasExample = w.exampleEn.trim().isNotEmpty;
    // Match the quiz-mode word hero exactly (see [_WordStage]) so the
    // word does not visibly shrink when a wrong answer flips the phase
    // from asking → wrongDetail on the same word.
    final wordSize = fitFontSize(w.word, 56);
    final phoneticSize = (wordSize * 0.28).clamp(12.0, 16.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
        child: Column(
          children: [
            // Word as the hero — same treatment as _AskingView.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  w.word,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: AppTheme.wordDisplay(
                                    size: wordSize,
                                    weight: FontWeight.w700,
                                    context: context,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              [w.phonetic, w.pos]
                                  .where((e) => e.trim().isNotEmpty)
                                  .join('  ·  '),
                              style: AppTheme.phonetic(
                                fontSize: phoneticSize,
                                context: context,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            AppGlassIconButton(
                              tooltip: '播放发音',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                TtsService.instance.speak(text: w.word);
                              },
                              icon: Icons.volume_up_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: AppSpacing.x6),
                            Text(
                              '正确答案',
                              style: AppTheme.mutedCaption(
                                size: 12,
                                color: AppColors.success,
                                context: context,
                              ).copyWith(letterSpacing: 1),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              w.translation,
                              textAlign: TextAlign.center,
                              style: AppTheme.cardTitle(
                                context: context,
                              ).copyWith(fontSize: 18, height: 1.5),
                            ),
                            if (hasExample) ...[
                              const SizedBox(height: AppSpacing.x6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.x4,
                                ),
                                child: Text(
                                  w.exampleEn,
                                  textAlign: TextAlign.center,
                                  style: AppTheme.mutedCaption(
                                    size: 15,
                                    color: AppColors.of(context).ink,
                                    context: context,
                                  ).copyWith(height: 1.6),
                                ),
                              ),
                              if (w.exampleCn.trim().isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.x2),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.x4,
                                  ),
                                  child: Text(
                                    w.exampleCn,
                                    textAlign: TextAlign.center,
                                    style: AppTheme.mutedCaption(
                                      size: 13,
                                      context: context,
                                    ).copyWith(height: 1.5),
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: AppSpacing.x4),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: AppSpacing.x2,
                              runSpacing: AppSpacing.x2,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _toggleFavorite,
                                  icon: Icon(
                                    _isFavorite
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 18,
                                  ),
                                  label: Text(_isFavorite ? '已收藏' : '加入收藏'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _isFavorite
                                        ? AppColors.warning
                                        : AppColors.of(context).inkMuted,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _markRemoved,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: AppColors.of(context).inkSubtle,
                                    size: 18,
                                  ),
                                  label: const Text('移除该词'),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.x4),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Continue button at the bottom.
            Padding(
              padding: EdgeInsets.only(
                bottom: AppSpacing.x6 + MediaQuery.of(context).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: EditorialPrimaryButton(
                  onPressed: () =>
                      ref.read(learningSessionProvider.notifier).next(),
                  minHeight: 52,
                  label: Text(
                    '继续',
                    style: AppTheme.cardTitle().copyWith(
                      fontSize: 16,
                      color: AppColors.onPrimary,
                    ),
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
      case QuestionType.typeWord:
        return _RecallStage(meaning: prompt, word: word);
    }
  }
}

class _RecallStage extends StatelessWidget {
  final String meaning;
  final VocabWord word;

  const _RecallStage({required this.meaning, required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          meaning,
          textAlign: TextAlign.center,
          style: AppTheme.screenHeader(context: context).copyWith(
            fontSize: fitFontSize(meaning, 28, referenceChars: 12),
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        _LargePlayButton(word: word),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '听音或根据释义拼写',
          style: AppTheme.mutedCaption(size: 13, context: context),
        ),
      ],
    );
  }
}

class _WordStage extends StatelessWidget {
  final VocabWord word;
  const _WordStage({required this.word});

  @override
  Widget build(BuildContext context) {
    final wordSize = fitFontSize(word.word, 56);
    final phoneticSize = (wordSize * 0.28).clamp(12.0, 16.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              word.word,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: AppTheme.wordDisplay(
                size: wordSize,
                weight: FontWeight.w700,
                context: context,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          word.phonetic,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: AppTheme.phonetic(fontSize: phoneticSize, context: context),
        ),
        const SizedBox(height: AppSpacing.x2),
        AppGlassIconButton(
          tooltip: '播放发音',
          onPressed: () {
            HapticFeedback.lightImpact();
            TtsService.instance.speak(text: word.word);
          },
          icon: Icons.volume_up_outlined,
          size: 20,
          color: AppColors.primary,
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '最符合该单词意思的是？',
          style: AppTheme.mutedCaption(size: 13, context: context),
        ),
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
    final meaningSize = fitFontSize(meaning, 28, referenceChars: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          child: Text(
            meaning,
            textAlign: TextAlign.center,
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: AppTheme.screenHeader(
              context: context,
            ).copyWith(fontSize: meaningSize, height: 1.4),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          '选择对应的英文',
          style: AppTheme.mutedCaption(
            size: 13,
            color: AppColors.of(context).inkSubtle,
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
          style: AppTheme.mutedCaption(
            size: 13,
            color: AppColors.of(context).inkSubtle,
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
    // The pronunciation control is one of the sanctioned interactive-glass
    // surfaces (design-qa): a floating glass disc, not a flat filled circle.
    return PressableScale(
      scaleFactor: 0.95,
      onTap: () {
        HapticFeedback.lightImpact();
        TtsService.instance.speak(text: word.word);
      },
      child: AppGlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: const SizedBox(
          width: 120,
          height: 120,
          child: Icon(
            Icons.volume_up_rounded,
            size: 48,
            color: AppColors.primary,
          ),
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
    final colors = _colors(context);
    final enabled = state == _OptionState.normal && onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label $text',
      onTap: enabled ? onTap : null,
      child: PressableScale(
        scaleFactor: enabled ? 0.97 : 1.0,
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : AppMotion.fast,
            curve: AppMotion.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x5,
              vertical: AppSpacing.x3,
            ),
            decoration: BoxDecoration(
              color:
                  state == _OptionState.normal &&
                      Theme.of(context).brightness == Brightness.light
                  ? null
                  : colors.background,
              gradient:
                  state == _OptionState.normal &&
                      Theme.of(context).brightness == Brightness.light
                  ? AppMaterials.paper
                  : null,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: colors.border,
                width: AppBorders.hairline,
              ),
              boxShadow:
                  state == _OptionState.normal &&
                      Theme.of(context).brightness == Brightness.light
                  ? AppShadows.paper
                  : AppShadows.none,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : AppMotion.fast,
                  curve: AppMotion.easeOut,
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.badgeBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    label,
                    style: AppTheme.mutedCaption(
                      size: 12,
                      color: colors.badgeText,
                      context: context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Text(
                    text,
                    style: AppTheme.mutedCaption(
                      size: 14,
                      color: colors.text,
                    ).copyWith(fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
                if (state == _OptionState.correct)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _OptionColors _colors(BuildContext context) {
    final palette = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Deep status colours sink into the dark card; brighten them toward
    // white so the correct/wrong wash keeps the same legibility it has
    // on the light paper surface.
    final success = isDark
        ? Color.lerp(AppColors.success, AppColors.surfaceDark, 0.4)!
        : AppColors.success;
    final danger = isDark
        ? Color.lerp(AppColors.danger, AppColors.surfaceDark, 0.4)!
        : AppColors.danger;
    switch (state) {
      case _OptionState.correct:
        return _OptionColors(
          background: AppColors.sageContainerOf(context),
          border: success,
          text: success,
          badgeBackground: success,
          badgeText: isDark ? AppColors.ink : AppColors.onPrimary,
        );
      case _OptionState.wrong:
        return _OptionColors(
          background: danger.withValues(alpha: isDark ? 0.16 : 0.08),
          border: danger,
          text: danger,
          badgeBackground: danger,
          badgeText: isDark ? AppColors.ink : AppColors.onPrimary,
        );
      case _OptionState.dimmed:
        return _OptionColors(
          background: palette.surfaceMuted,
          border: palette.inkSubtle.withValues(alpha: 0.1),
          text: palette.inkSubtle,
          badgeBackground: palette.inkSubtle.withValues(alpha: 0.12),
          badgeText: palette.inkSubtle,
        );
      case _OptionState.normal:
        return _OptionColors(
          background: palette.surface,
          border: palette.inkSubtle.withValues(alpha: 0.2),
          text: palette.ink,
          badgeBackground: palette.surfaceMuted,
          badgeText: palette.inkMuted,
        );
    }
  }
}

class _OptionColors {
  final Color background;
  final Color border;
  final Color text;
  final Color badgeBackground;
  final Color badgeText;

  const _OptionColors({
    required this.background,
    required this.border,
    required this.text,
    required this.badgeBackground,
    required this.badgeText,
  });
}

class _FinishedView extends StatelessWidget {
  const _FinishedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              color: AppColors.of(context).inkSubtle,
              size: 36,
            ),
            const SizedBox(height: AppSpacing.x3),
            Text('当前没有待学单词', style: AppTheme.cardTitle(context: context)),
          ],
        ),
      ),
    );
  }
}

/// Douyin/TikTok-style full-screen vertical pager. Each word fills the
/// whole screen; the next word sits one screen-height below and slides
/// up as you drag. A fast flick (or dragging past 30% of the screen)
/// flips to the next word; otherwise the page springs back. Only
/// swiping up advances — swiping down does nothing (no going back).
/// Dwell time grades SM-2 mastery, and the result is shown to the user
/// as a brief "已掌握 / 记住了 / 再看看 / 不熟悉" pill so the judgment
/// is visible, not hidden.
class SwipeView extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const SwipeView({required this.session, super.key});

  @override
  ConsumerState<SwipeView> createState() => _SwipeViewState();
}

class _SwipeViewState extends ConsumerState<SwipeView>
    with TickerProviderStateMixin {
  /// Fraction of screen height you must drag past to flip the page.
  static const _flipThreshold = 0.3;

  /// Velocity (px/s) above which a flick flips regardless of distance.
  static const _flickVelocity = 500.0;

  /// Rubber-band constant (Designing Fluid Interfaces sample code).
  static const _rubberBandConstant = 0.55;

  double _dragDy = 0;
  /// True finger position (1:1 with the pointer). [_dragDy] is the
  /// rubber-banded display value derived from this — keeping them
  /// separate prevents the rubber-band from being compounded across
  /// frames (which would make the page drift opposite the finger).
  double _rawDragDy = 0;
  DateTime? _cardShownAt;
  String? _activeWordId;
  late final AnimationController _controller;
  Animation<Offset>? _anim;
  bool _animating = false;
  /// Cached page widgets so a drag/animation frame only re-applies the
  /// transform instead of rebuilding the entire subtree (§11).
  Widget? _currentPage;
  Widget? _nextPage;
  Widget? _prevPage;

  /// Real-time dwell progress (0.0 → 1.0 over 15s) driving the bottom
  /// mastery bar so the user sees the card "filling up" as they study.
  double _dwellProgress = 0;
  late final Ticker _dwellTicker;

  /// When a flip is triggered by swipe, the next word's audio is spoken
  /// immediately (in lockstep with the page flying in) instead of waiting
  /// for the session state to propagate and _onQuestionChanged to fire.
  /// This flag suppresses the duplicate speak in _onQuestionChanged.
  bool _swipeSpeakPending = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _dwellTicker = createTicker(_onDwellTick)..start();
    _onQuestionChanged();
  }

  @override
  void didUpdateWidget(covariant SwipeView old) {
    super.didUpdateWidget(old);
    if (widget.session.currentQuestion?.word.id !=
        old.session.currentQuestion?.word.id) {
      _onQuestionChanged();
    }
  }

  void _onQuestionChanged() {
    final id = widget.session.currentQuestion?.word.id;
    if (id == _activeWordId) return;
    _activeWordId = id;
    _dragDy = 0;
    _rawDragDy = 0;
    _anim = null;
    _animating = false;
    _controller.value = 0;
    _cardShownAt = DateTime.now();
    _rebuildPages();
    if (id != null && !_swipeSpeakPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final text = widget.session.currentQuestion?.word.word;
        if (text != null) TtsService.instance.speak(text: text);
      });
    }
    _swipeSpeakPending = false;
  }

  /// Rebuild cached page widgets — only called when the question changes,
  /// not on every drag/animation frame.
  void _rebuildPages() {
    final q = widget.session.currentQuestion;
    final nextQ = widget.session.questions.length >
            widget.session.currentIndex + 1
        ? widget.session.questions[widget.session.currentIndex + 1]
        : null;
    final prevQ = ref.read(learningSessionProvider.notifier).previousQuestion;
    _currentPage = q != null
        ? _SwipePage(word: q.word, dwellProgress: _dwellProgress)
        : null;
    _nextPage = nextQ != null
        ? _SwipePage(word: nextQ.word, dwellProgress: 0)
        : null;
    _prevPage = prevQ != null
        ? _SwipePage(word: prevQ.word, dwellProgress: 0)
        : null;
  }

  /// Dwell tick — tracks dwell time for scoring only. Does NOT rebuild
  /// the page tree: the mastery bar fill comes from SM-2 review state,
  /// not dwell time, so per-frame setState() was pure waste (swipe jank).
  void _onDwellTick(Duration elapsed) {
    if (!mounted || _cardShownAt == null) return;
    final ms = DateTime.now().difference(_cardShownAt!).inMilliseconds;
    _dwellProgress = (ms / 18000).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _dwellTicker.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Apple's rubber-band: the further past the boundary, the less the
  /// element follows — real things slow before they stop (§9).
  double _rubberBand(double overshoot, double dimension) {
    if (overshoot == 0) return 0;
    return (overshoot * dimension * _rubberBandConstant) /
        (dimension + _rubberBandConstant * overshoot.abs());
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    // Mid-drag catch: grab the page back while it's animating.
    // Read the live on-screen value so there's no jump (§3).
    if (_animating) {
      _dragDy = _anim?.value.dy ?? _dragDy;
      _rawDragDy = _dragDy;
      _controller.stop();
      _animating = false;
      _anim = null;
    }
    final screenH = MediaQuery.of(context).size.height;
    // Accumulate the true finger position, then apply rubber-band only
    // for display — never feed the rubber-banded value back into the
    // accumulator (§9). Rubber-band on the downward edge only when
    // there is no previous word to flip back to.
    _rawDragDy += d.delta.dy;
    var display = _rawDragDy;
    if (display > 0 &&
        !ref.read(learningSessionProvider.notifier).canGoBack) {
      display = _rubberBand(display, screenH);
    }
    setState(() => _dragDy = display);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_animating) return;
    final velocity = d.velocity.pixelsPerSecond.dy;
    final screenH = MediaQuery.of(context).size.height;
    final canGoBack = ref.read(learningSessionProvider.notifier).canGoBack;

    // 统一判断：速度超过阈值 或 拖动距离超过阈值 即翻转。
    // 快速和慢速走同一条路径，只是速度不同导致动画时长不同。
    final projected = _dragDy + AppMotion.projectMomentum(velocity);
    if (projected < -screenH * _flipThreshold || velocity < -_flickVelocity) {
      _flipToNext(velocity);
    } else if (canGoBack &&
        (projected > screenH * _flipThreshold || velocity > _flickVelocity)) {
      _flipToPrev(velocity);
    } else {
      _springBack(velocity);
    }
  }

  /// Stop any in-flight animation and reset drag state so the next
  /// interaction starts from a clean slate.
  void _interruptAnimation() {
    if (_animating) {
      _controller.stop();
      _animating = false;
      _anim = null;
    }
    _dragDy = 0;
    _rawDragDy = 0;
  }

  int _dwellMs() {
    return _cardShownAt != null
        ? DateTime.now().difference(_cardShownAt!).inMilliseconds
        : 3000;
  }

  /// 松手后让页面从当前位置快速线性滑到目标位置。
  /// 固定 50ms + linear 曲线——没有任何减速/弹簧/刹车感，
  /// 像刷短视频那样"唰"地一下到位。
  void _animateFlip({
    required double end,
    required VoidCallback onComplete,
  }) {
    _animating = true;
    _controller.duration = const Duration(milliseconds: 50);
    _anim = Tween<Offset>(
      begin: Offset(0, _dragDy),
      end: Offset(0, end),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      _dragDy = 0;
      _rawDragDy = 0;
      _anim = null;
      _animating = false;
      onComplete();
    });
  }

  void _flipToNext(double velocity) {
    HapticFeedback.lightImpact();
    // Use the latest state, not the stale widget.session snapshot, so
    // rapid consecutive swipes don't compute nextQ from an old index.
    final session = ref.read(learningSessionProvider);
    final nextQ = session.questions.length > session.currentIndex + 1
        ? session.questions[session.currentIndex + 1]
        : null;
    if (nextQ != null) {
      TtsService.instance.speak(text: nextQ.word.word);
      _swipeSpeakPending = true;
    }
    final dwell = _dwellMs();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _submitSwipe(dwellMs: dwell);
      return;
    }
    // 立即切换内容：把 nextPage 提升为 currentPage，预取下一个。
    // 不等动画结束，不等 Riverpod rebuild——内容先换，动画只是
    // 让新页面从底部一小段距离快速归位。
    if (nextQ != null) {
      _activeWordId = nextQ.word.id;
      _cardShownAt = DateTime.now();
      final afterNextQ = session.questions.length > session.currentIndex + 2
          ? session.questions[session.currentIndex + 2]
          : null;
      _prevPage = _currentPage;
      _currentPage = _nextPage;
      _nextPage = afterNextQ != null
          ? _SwipePage(word: afterNextQ.word, dwellProgress: 0)
          : null;
    }
    // 新页面从底部 80px 快速滑入到位（50ms linear）。
    _dragDy = 80;
    _rawDragDy = 80;
    _submitSwipe(dwellMs: dwell);
    _animateFlip(end: 0, onComplete: () {});
  }
  void _flipToPrev(double velocity) {
    HapticFeedback.lightImpact();
    final session = ref.read(learningSessionProvider);
    final prevQ = ref.read(learningSessionProvider.notifier).previousQuestion;
    if (prevQ != null) {
      TtsService.instance.speak(text: prevQ.word.word);
      _swipeSpeakPending = true;
    }
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      ref.read(learningSessionProvider.notifier).goBack();
      return;
    }
    // 立即切换内容：prevPage → currentPage。
    if (prevQ != null) {
      _activeWordId = prevQ.word.id;
      _cardShownAt = DateTime.now();
      final prevPrevQ = session.currentIndex >= 2
          ? session.questions[session.currentIndex - 2]
          : null;
      _nextPage = _currentPage;
      _currentPage = _prevPage;
      _prevPage = prevPrevQ != null
          ? _SwipePage(word: prevPrevQ.word, dwellProgress: 0)
          : null;
    }
    // 新页面从顶部 80px 快速滑入到位。
    _dragDy = -80;
    _rawDragDy = -80;
    ref.read(learningSessionProvider.notifier).goBack();
    _animateFlip(end: 0, onComplete: () {});
  }

  void _springBack(double velocity) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _dragDy = 0;
      setState(() {});
      return;
    }
    // 50ms 线性弹回，干脆不拖泥带水。
    _animateFlip(end: 0, onComplete: () => setState(() {}));
  }

  void _submitSwipe({required int dwellMs}) {
    ref.read(learningSessionProvider.notifier).answerSwipe(dwellMs: dwellMs);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.session.currentQuestion;
    if (q == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    final screenH = MediaQuery.of(context).size.height;
    final currentPage = _currentPage;
    final nextPage = _nextPage;
    final prevPage = _prevPage;

    return Semantics(
      label: '单词卡片，上下滑动切换',
      onIncrease: () => _submitSwipe(dwellMs: 5000),
      onDecrease: ref.read(learningSessionProvider.notifier).canGoBack
          ? () => ref.read(learningSessionProvider.notifier).goBack()
          : null,
      child: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offset = _anim?.value ?? Offset(0, _dragDy);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (prevPage != null)
                    Transform.translate(
                      offset: offset - Offset(0, screenH),
                      child: prevPage,
                    ),
                  if (nextPage != null)
                    Transform.translate(
                      offset: offset + Offset(0, screenH),
                      child: nextPage,
                    ),
                  if (currentPage != null)
                    Transform.translate(
                      offset: offset,
                      child: currentPage,
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

/// One full-screen word page laid out like a dictionary entry: word at
/// the top, then phonetic, audio, meaning, example, and a memory
/// mastery indicator pinned to the bottom.
class _SwipePage extends ConsumerWidget {
  final VocabWord word;
  final double dwellProgress;

  const _SwipePage({required this.word, this.dwellProgress = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppColors.of(context);
    // Match the quiz-mode word hero exactly (see [_WordStage]): same
    // fit budget (56) and the same phonetic size derived from it, so the
    // word reads at one weight across both modes.
    final wordSize = fitFontSize(word.word, 56);
    final phoneticSize = (wordSize * 0.28).clamp(12.0, 16.0);
    final reviewState = ref.watch(reviewStateProvider)[word.id];
    final hasExample = word.exampleEn.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
        // Mirror the quiz layout skeleton (see [AskingView]): the word
        // hero is centred in the top 5/10 of the screen and the rest of
        // the entry fills the lower 5/10. This keeps the optical centre
        // and vertical rhythm identical between the two learning modes,
        // instead of the old top-stacked content that left the whole
        // lower half empty.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Position the whole entry (word + meaning) as one group in the
            // upper-middle of the screen, where the quiz-mode word hero sits
            // (~35% of the height). The top spacer is smaller than the bottom
            // one so the group sits above the geometric centre — the eye
            // lands on the word first, then drops to the meaning, mirroring
            // the quiz rhythm of "prompt on top, answer below".
            const Spacer(flex: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                word.word,
                textAlign: TextAlign.center,
                style: AppTheme.wordDisplay(
                  size: wordSize,
                  weight: FontWeight.w700,
                  context: context,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            if (word.phonetic.trim().isNotEmpty)
              Text(
                word.phonetic,
                style: AppTheme.phonetic(
                  fontSize: phoneticSize,
                  context: context,
                ),
              ),
            const SizedBox(height: AppSpacing.x2),
            AppGlassIconButton(
              tooltip: '播放发音',
              onPressed: () {
                HapticFeedback.lightImpact();
                TtsService.instance.speak(text: word.word);
              },
              icon: Icons.volume_up_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            // Only show part-of-speech when present. `level` is never
            // real per-word CEFR data (uniform placeholder or empty),
            // so it is hidden to avoid displaying fake grades.
            if (word.pos.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x2),
              Text(
                word.pos,
                style: AppTheme.mutedCaption(
                  size: 13,
                  color: palette.inkMuted,
                  context: context,
                ).copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.x6),
            ...word.translations.map(
              (t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1),
                child: Text(
                  t,
                  textAlign: TextAlign.center,
                  style: AppTheme.screenHeader(context: context)
                      .copyWith(fontSize: 18, height: 1.5),
                ),
              ),
            ),
            if (hasExample) ...[
              const SizedBox(height: AppSpacing.x5),
              _ExampleCard(word: word),
            ],
            const Spacer(flex: 4),
            _MasteryIndicator(
              reviewState: reviewState,
              dwellProgress: dwellProgress,
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
        ),
      ),
    );
  }
}

/// Example sentence card. The target word is bolded inside the
/// sentence so the eye lands on it, mirroring the reference app's
/// "highlight the headword" pattern.
class _ExampleCard extends StatelessWidget {
  final VocabWord word;
  const _ExampleCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PillTag(
            label: '例句',
            color: palette.inkMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x2,
              vertical: AppSpacing.x1,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          _buildHighlightedExample(context),
          if (word.exampleCn.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(
              word.exampleCn,
              style: AppTheme.mutedCaption(
                size: 13,
                context: context,
              ).copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHighlightedExample(BuildContext context) {
    final text = word.exampleEn;
    final target = word.word;
    final spans = <TextSpan>[];
    var cursor = 0;
    final lower = text.toLowerCase();
    final targetLower = target.toLowerCase();
    while (cursor < text.length) {
      final idx = lower.indexOf(targetLower, cursor);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (idx > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + target.length),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      cursor = idx + target.length;
    }
    return RichText(
      text: TextSpan(
        style: AppTheme.mutedCaption(
          size: 15,
          color: AppColors.of(context).ink,
          context: context,
        ).copyWith(height: 1.6),
        children: spans,
      ),
    );
  }
}

/// A thin, full-width accent line at the bottom of the swipe page.
/// Shows the word's existing SM-2 mastery only — a familiar word
/// begins nearly full, a new word begins near empty. Dwell time is
/// used for scoring but deliberately NOT shown here, so the bar's
/// direction (more = better) never contradicts the scoring logic
/// (longer dwell = worse).
class _MasteryIndicator extends StatelessWidget {
  final ReviewState? reviewState;
  final double dwellProgress;

  const _MasteryIndicator({
    required this.reviewState,
    this.dwellProgress = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = _classify(reviewState);
    final value = _baseline(reviewState);
    final label = _label(reviewState);
    return Semantics(
      label: '掌握程度：$label',
      value: '${(value * 100).round()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.mutedCaption(
              size: 11,
              color: color,
              context: context,
            ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          const SizedBox(height: AppSpacing.x1),
          SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(
              value: value,
              minHeight: 2,
              backgroundColor: color.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  String _label(ReviewState? s) {
    if (s == null) return '待学习';
    final ef = s.easiness / 100.0;
    if (s.repetitions == 0) return '陌生';
    if (ef >= 2.5 && s.repetitions >= 3) return '熟悉';
    if (ef >= 2.3 && s.repetitions >= 2) return '认识';
    return '模糊';
  }

  /// Baseline fill from the existing SM-2 state, before any dwell
  /// time is added. A brand-new word starts at 0.15; a word you've
  /// already mastered starts at 0.85.
  double _baseline(ReviewState? s) {
    if (s == null) return 0.15;
    final ef = s.easiness / 100.0;
    if (s.repetitions == 0) return 0.2;
    if (ef >= 2.5 && s.repetitions >= 3) return 0.85;
    if (ef >= 2.3 && s.repetitions >= 2) return 0.65;
    return 0.4;
  }

  Color _classify(ReviewState? s) {
    if (s == null) return AppColors.danger;
    final ef = s.easiness / 100.0;
    if (s.repetitions == 0) return AppColors.danger;
    if (ef >= 2.5 && s.repetitions >= 3) return AppColors.success;
    if (ef >= 2.3 && s.repetitions >= 2) return AppColors.success;
    return AppColors.warning;
  }
}

