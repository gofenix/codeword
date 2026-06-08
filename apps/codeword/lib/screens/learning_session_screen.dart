import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';

class LearningSessionScreen extends ConsumerStatefulWidget {
  final String vocabId;
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
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(learningSessionProvider.notifier)
          .start(vocabId: widget.vocabId, count: widget.count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(learningSessionProvider);
    final meta = ref.watch(vocabMetaProvider)[widget.vocabId];
    final name = meta?.name ?? widget.vocabId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: switch (session.phase) {
        SessionPhase.loading => const Center(child: CircularProgressIndicator()),
        SessionPhase.asking => _AskingView(session: session),
        SessionPhase.feedback => _AutoAdvanceFeedback(session: session),
        SessionPhase.wrongDetail => _WrongDetailView(session: session),
        SessionPhase.finished => _FinishedView(
            total: session.questions.length,
            correct: session.correctCount,
            onClose: () => Navigator.of(context).pop(),
          ),
      },
    );
  }
}

class _AskingView extends ConsumerWidget {
  final LearningSessionState session;
  const _AskingView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = session.currentQuestion!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.x5, AppSpacing.x3, AppSpacing.x5, AppSpacing.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProgressBar(progress: session.progress),
            const SizedBox(height: AppSpacing.x4),
            _QuestionPrompt(type: q.type, prompt: q.prompt, word: q.word, questionCount: session.questions.length, currentIndex: session.currentIndex),
            const SizedBox(height: AppSpacing.x3),
            if (q.type == QuestionType.listenPickMeaning) _AudioButton(word: q.word),
            const SizedBox(height: AppSpacing.x5),
            if (q.type == QuestionType.spelling)
              _SpellingInput(
                correct: q.word.word,
                onCorrect: () => ref.read(learningSessionProvider.notifier).answer(0),
                onWrong: () => ref.read(learningSessionProvider.notifier).answer(-1),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: q.options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.x3),
                  itemBuilder: (_, i) => _OptionTile(
                    label: String.fromCharCode(65 + i),
                    text: q.options[i],
                    onTap: () => ref.read(learningSessionProvider.notifier).answer(i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AutoAdvanceFeedback extends ConsumerStatefulWidget {
  final LearningSessionState session;
  const _AutoAdvanceFeedback({required this.session});

  @override
  ConsumerState<_AutoAdvanceFeedback> createState() => _AutoAdvanceFeedbackState();
}

class _AutoAdvanceFeedbackState extends ConsumerState<_AutoAdvanceFeedback> {
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_advanced) {
        _advanced = true;
        ref.read(learningSessionProvider.notifier).next();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.xl),
            ),
            child: const Icon(Icons.check_circle_rounded, size: 48, color: AppColors.success),
          ),
          const SizedBox(height: AppSpacing.x4),
          const Text('正确!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.success)),
        ],
      ),
    );
  }
}

class _WrongDetailView extends ConsumerWidget {
  final LearningSessionState session;
  const _WrongDetailView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = session.currentQuestion!;
    final w = q.word;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.x5, AppSpacing.x3, AppSpacing.x5, AppSpacing.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProgressBar(progress: (session.currentIndex + 1) / session.questions.length),
            const SizedBox(height: AppSpacing.x2),
            Row(
              children: [
                const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
                const SizedBox(width: 6),
                const Text('答错了', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger)),
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

class _AudioButton extends StatelessWidget {
  final VocabWord word;
  const _AudioButton({required this.word});

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
        onPressed: () {
          HapticFeedback.lightImpact();
          _speak(word.word);
        },
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _speak(String text) {
    // Use platform TTS via a simple service message.
    // Falls back to text-to-speech via system channel.
    const MethodChannel('com.codeword/tts').invokeMethod('speak', {'text': text});
  }
}

class _SpellingInput extends StatefulWidget {
  final String correct;
  final VoidCallback onCorrect;
  final VoidCallback onWrong;
  const _SpellingInput({required this.correct, required this.onCorrect, required this.onWrong});

  @override
  State<_SpellingInput> createState() => _SpellingInputState();
}

class _SpellingInputState extends State<_SpellingInput> {
  final _controller = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (_submitted) return;
    _submitted = true;
    if (_controller.text.trim().toLowerCase() == widget.correct.toLowerCase()) {
      widget.onCorrect();
    } else {
      widget.onWrong();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _check(),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: 2),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '输入单词拼写',
            hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitted ? null : _check,
            child: const Text('确认'),
          ),
        ),
      ],
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
      QuestionType.spelling => '拼写',
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
      case QuestionType.spelling:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt, style: const TextStyle(fontSize: 20, color: AppColors.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(word.phonetic, style: AppTheme.phonetic()),
          ],
        );
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4, vertical: AppSpacing.x4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.inkSubtle.withValues(alpha: 0.2), width: 1.5),
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
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 14)),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 15, color: AppColors.ink, fontWeight: FontWeight.w500, height: 1.4)),
              ),
              const Icon(Icons.chevron_right, color: AppColors.inkSubtle, size: 18),
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
        Text('${(progress * 100).round()}%', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
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
