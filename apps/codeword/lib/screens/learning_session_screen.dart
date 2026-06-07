import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        SessionPhase.loading => const _Loading(),
        SessionPhase.asking ||
        SessionPhase.feedback =>
          _QuestionView(session: session),
        SessionPhase.finished => _FinishedView(
            total: session.questions.length,
            correct: session.correctCount,
            onClose: () => Navigator.of(context).pop(),
          ),
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _QuestionView extends ConsumerWidget {
  final LearningSessionState session;
  const _QuestionView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = session.currentQuestion!;
    final showingFeedback = session.phase == SessionPhase.feedback;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x5,
          AppSpacing.x3,
          AppSpacing.x5,
          AppSpacing.x6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProgressBar(progress: session.progress),
            const SizedBox(height: AppSpacing.x4),
            _Card(
              progressLabel:
                  '${session.currentIndex + 1} / ${session.questions.length}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PillTag.domain(
                        q.word.domain.toUpperCase(),
                        color: _domainColor(q.word.domain),
                        icon: Icons.bolt,
                      ),
                      const SizedBox(width: 6),
                      PillTag.level(q.word.level),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Text(q.word.word, style: AppTheme.wordDisplay(size: 32)),
                  const SizedBox(height: 4),
                  Text('${q.word.phonetic}  ${q.word.pos}',
                      style: AppTheme.phonetic()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            Expanded(
              child: ListView.separated(
                itemCount: q.options.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.x3),
                itemBuilder: (_, i) {
                  return _OptionTile(
                    label: String.fromCharCode(65 + i), // A/B/C/D
                    text: q.options[i],
                    state: showingFeedback
                        ? _resolveState(
                            i,
                            q.correctIndex,
                            session.lastSelectedIndex,
                          )
                        : _OptionState.idle,
                    onTap: showingFeedback
                        ? null
                        : () => ref
                            .read(learningSessionProvider.notifier)
                            .answer(i),
                  );
                },
              ),
            ),
            if (showingFeedback) _FeedbackFooter(
              correct: session.isCorrect,
              onNext: () =>
                  ref.read(learningSessionProvider.notifier).next(),
            ),
          ],
        ),
      ),
    );
  }

  _OptionState _resolveState(
    int i,
    int correct,
    int? selected,
  ) {
    if (i == correct) return _OptionState.correct;
    if (i == selected) return _OptionState.wrong;
    return _OptionState.dimmed;
  }

  Color _domainColor(String domain) {
    switch (domain) {
      case 'cs':
        return AppColors.domainCs;
      case 'python':
        return AppColors.domainPython;
      case 'ai':
        return AppColors.domainAi;
      case 'web':
        return AppColors.domainWeb;
      default:
        return AppColors.primary;
    }
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

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
    final (bg, border, fg) = switch (state) {
      _OptionState.idle => (
        AppColors.surface,
        AppColors.inkSubtle.withValues(alpha: 0.2),
        AppColors.ink,
      ),
      _OptionState.correct => (
        AppColors.success.withValues(alpha: 0.12),
        AppColors.success,
        AppColors.success,
      ),
      _OptionState.wrong => (
        AppColors.danger.withValues(alpha: 0.12),
        AppColors.danger,
        AppColors.danger,
      ),
      _OptionState.dimmed => (
        AppColors.surface,
        AppColors.inkSubtle.withValues(alpha: 0.1),
        AppColors.inkMuted,
      ),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x4,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: fg,
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
                    color: fg,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              if (state == _OptionState.correct)
                const Icon(Icons.check_circle, color: AppColors.success),
              if (state == _OptionState.wrong)
                const Icon(Icons.cancel, color: AppColors.danger),
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

class _Card extends StatelessWidget {
  final String progressLabel;
  final Widget child;
  const _Card({required this.progressLabel, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x5,
        AppSpacing.x4,
        AppSpacing.x5,
        AppSpacing.x5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '选义',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                progressLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          child,
        ],
      ),
    );
  }
}

class _FeedbackFooter extends StatelessWidget {
  final bool correct;
  final VoidCallback onNext;
  const _FeedbackFooter({required this.correct, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x3),
      child: FilledButton(
        onPressed: onNext,
        style: FilledButton.styleFrom(
          backgroundColor: correct ? AppColors.success : AppColors.danger,
          minimumSize: const Size.fromHeight(48),
        ),
        child: Text(correct ? '下一题 →' : '记住了,下一题 →'),
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
                style: AppTheme.wordDisplay(
                  size: 24,
                  color: AppColors.ink,
                ),
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
                style: FilledButton.styleFrom(
                  minimumSize: const Size(180, 48),
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
