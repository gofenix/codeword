import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../services/tts_service.dart';
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
    ref.watch(vocabMetaProvider)[widget.vocabId];

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: MediaQuery.withClampedTextScaling(
        minScaleFactor: 1,
        maxScaleFactor: 1.3,
        child: SafeArea(
          child: switch (session.phase) {
            SessionPhase.loading => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            SessionPhase.asking => AskingView(
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
      ),
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
      // No auto-play on correct — the user already knows the word.
      // Audio is reserved for: (1) listening questions where audio IS
      // the prompt, (2) the wrong-answer detail card where hearing the
      // correct pronunciation helps learning. Playing here just makes
      // the flow feel laggy.
      Future.delayed(AppMotion.answerCorrect, () {
        if (!mounted || !_isCurrentQuestion(questionIdentity)) return;
        ref.read(learningSessionProvider.notifier).answer(i);
      });
    } else {
      HapticFeedback.heavyImpact();
      // Brief pause so the user sees the red highlight before the
      // immersive wrong-answer card takes over.
      Future.delayed(AppMotion.answerWrong, () {
        if (!mounted || !_isCurrentQuestion(questionIdentity)) return;
        ref.read(learningSessionProvider.notifier).answer(i);
      });
    }
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
      correct ? AppMotion.answerCorrect : AppMotion.answerWrong,
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
            Expanded(
              child: Center(
                child: _QuestionStage(
                  type: q.type,
                  prompt: q.prompt,
                  word: q.word,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom:
                    AppSpacing.x6 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: Column(
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
                                  ? AppColors.primary
                                  : AppColors.danger,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _locked ? null : _submitTyped,
                      child: const Text('确认'),
                    ),
                  ),
                ],
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
          // The word / meaning — the only thing the user should look at.
          Expanded(
            flex: 5,
            child: Center(
              child: _QuestionStage(
                type: q.type,
                prompt: q.prompt,
                word: q.word,
              ),
            ),
          ),
          // Options sit right below, no gap.
          Flexible(
            flex: 5,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: AppSpacing.x6 + MediaQuery.of(context).padding.bottom,
              ),
              child: SingleChildScrollView(
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
    final hasExample = w.exampleEn.trim().isNotEmpty;
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
                                    size: 40,
                                    weight: FontWeight.w700,
                                    context: context,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              '${w.phonetic}  ${w.pos}',
                              style: AppTheme.phonetic(
                                fontSize: 15,
                                context: context,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            IconButton(
                              tooltip: '播放发音',
                              icon: const Icon(
                                Icons.volume_up_outlined,
                                size: 22,
                              ),
                              color: AppColors.of(context).inkMuted,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                TtsService.instance.speak(text: w.word);
                              },
                            ),
                            const SizedBox(height: AppSpacing.x6),
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
          size: 18,
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
          color: AppColors.primaryContainerOf(context),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.volume_up_rounded,
          size: 48,
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
            duration: AppMotion.fast,
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
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: colors.border, width: 1),
              boxShadow:
                  state == _OptionState.normal &&
                      Theme.of(context).brightness == Brightness.light
                  ? AppShadows.paper
                  : AppShadows.none,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AppMotion.fast,
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
    switch (state) {
      case _OptionState.correct:
        return _OptionColors(
          background: AppColors.sageSoft,
          border: AppColors.success,
          text: AppColors.success,
          badgeBackground: AppColors.success,
          badgeText: AppColors.onPrimary,
        );
      case _OptionState.wrong:
        return _OptionColors(
          background: AppColors.danger.withValues(alpha: 0.08),
          border: AppColors.danger,
          text: AppColors.danger,
          badgeBackground: AppColors.danger,
          badgeText: AppColors.onPrimary,
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
