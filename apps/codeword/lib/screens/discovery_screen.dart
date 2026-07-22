import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';
import 'settings_screen.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  final VoidCallback onGoWords;

  const DiscoveryScreen({super.key, required this.onGoWords});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _category;

  static const _categoryPriority = ['编程', '考试英语', '青少年英语', '语言', '词典', '专业词汇'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(qwertyCatalogProvider);
    final selectedId = ref.watch(selectedVocabProvider);
    ref.watch(reviewStateProvider);
    final stats = ref
        .read(reviewStateProvider.notifier)
        .stats(catalog: catalog);
    final selected = catalog.where((item) => item.id == selectedId);
    final current = selected.isEmpty ? null : selected.first;
    final currentProgress = vocabProgressFor(stats, selectedId);
    final grouped = _groupedCatalog(catalog);

    return TabPageScaffold(
      title: '词书',
      scrollKey: const PageStorageKey('library-scroll'),
      trailing: IconButton(
        tooltip: '设置',
        onPressed: () {
          HapticFeedback.selectionClick();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
        icon: const Icon(Icons.settings_outlined, size: 21),
        color: AppColors.of(context).inkMuted,
      ),
      slivers: [
        SliverList.list(
          children: [
            _SearchField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              onClear: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
            const SizedBox(height: AppSpacing.x3),
            _CategoryFilter(
              categories: catalog.map((item) => item.category).toSet().toList()
                ..sort(),
              selected: _category,
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: AppSpacing.x4),
            _CurrentBookBand(
              list: current,
              progress: currentProgress,
              onTap: current == null ? null : () => _startBook(current.id),
            ),
            const SizedBox(height: AppSpacing.x5),
            if (grouped.isEmpty)
              const SizedBox(
                height: 180,
                child: EmptyHint(
                  icon: Icons.search_off_outlined,
                  message: '没有找到相关词书',
                ),
              )
            else
              for (final entry in grouped.entries) ...[
                _BookSection(
                  category: entry.key,
                  books: entry.value,
                  selectedId: selectedId,
                  stats: stats,
                  onTap: _startBook,
                ),
                const SizedBox(height: AppSpacing.x4),
              ],
          ],
        ),
      ],
    );
  }

  Map<String, List<VocabList>> _groupedCatalog(List<VocabList> catalog) {
    final result = <String, List<VocabList>>{};
    for (final list in catalog) {
      if (_category != null && list.category != _category) continue;
      final haystack = '${list.name} ${list.description} ${list.category}'
          .toLowerCase();
      if (_query.isNotEmpty && !haystack.contains(_query)) continue;
      result.putIfAbsent(list.category, () => []).add(list);
    }
    final keys = result.keys.toList()
      ..sort((a, b) {
        final ai = _categoryPriority.indexOf(a);
        final bi = _categoryPriority.indexOf(b);
        if (ai < 0 && bi < 0) return a.compareTo(b);
        if (ai < 0) return 1;
        if (bi < 0) return -1;
        return ai.compareTo(bi);
      });
    return {for (final key in keys) key: result[key]!};
  }

  Future<void> _startBook(String vocabId) async {
    HapticFeedback.selectionClick();
    ref.read(selectedVocabProvider.notifier).state = vocabId;
    try {
      await ReviewRepository.instance.setSelectedVocabId(vocabId);
    } catch (_) {}
    await ref.read(learningSessionProvider.notifier).start(vocabId: vocabId);
    if (mounted) widget.onGoWords();
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('library-first-content'),
      controller: controller,
      onChanged: onChanged,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: '搜索词书或分类',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: '清空搜索',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        ),
        filled: true,
        fillColor: AppColors.of(context).surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _CategoryFilter({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.x2),
        itemBuilder: (context, index) {
          final value = index == 0 ? null : categories[index - 1];
          final active = selected == value;
          return ChoiceChip(
            label: Text(value ?? '全部'),
            selected: active,
            showCheckmark: false,
            onSelected: (_) => onChanged(value),
            visualDensity: VisualDensity.compact,
            selectedColor: AppColors.primarySoft,
            backgroundColor: AppColors.of(context).surface,
            side: BorderSide.none,
            labelStyle: AppTheme.mutedCaption(
              size: 12,
              color: active
                  ? AppColors.primary
                  : AppColors.of(context).inkMuted,
            ).copyWith(fontWeight: FontWeight.w600),
          );
        },
      ),
    );
  }
}

class _CurrentBookBand extends StatelessWidget {
  final VocabList? list;
  final VocabProgress? progress;
  final VoidCallback? onTap;

  const _CurrentBookBand({
    required this.list,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = progress?.availableWords ?? list?.wordCount ?? 0;
    final learned = progress?.learned ?? 0;
    final ratio = total == 0 ? 0.0 : learned / total;
    return Material(
      color: const Color(0xFFEAF7EE),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(
                      Icons.book_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          list?.name ?? '尚未选择词书',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitle(context: context),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '当前词书 · 已学 $learned / $total',
                          style: AppTheme.mutedCaption(
                            size: 12,
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.8),
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookSection extends StatelessWidget {
  final String category;
  final List<VocabList> books;
  final String selectedId;
  final ReviewStats stats;
  final ValueChanged<String> onTap;

  const _BookSection({
    required this.category,
    required this.books,
    required this.selectedId,
    required this.stats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$category · ${books.length}',
          style: AppTheme.sectionLabel(context: context),
        ),
        const SizedBox(height: AppSpacing.x2),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < books.length; i++) ...[
                _BookRow(
                  list: books[i],
                  progress: vocabProgressFor(stats, books[i].id),
                  selected: books[i].id == selectedId,
                  onTap: () => onTap(books[i].id),
                ),
                if (i != books.length - 1)
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

class _BookRow extends StatelessWidget {
  final VocabList list;
  final VocabProgress? progress;
  final bool selected;
  final VoidCallback onTap;

  const _BookRow({
    required this.list,
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final learned = progress?.learned ?? 0;
    final total = progress?.availableWords ?? list.wordCount;
    final due = progress?.due ?? 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _categoryColor(list.category).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Text(
                list.name.characters.isEmpty ? '·' : list.name.characters.first,
                style: AppTheme.cardTitle(
                  context: context,
                ).copyWith(color: _categoryColor(list.category), fontSize: 16),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          list.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.rowTitle(
                            color: selected ? AppColors.primary : null,
                            context: context,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: AppSpacing.x2),
                        const PillTag(
                          label: '当前',
                          color: AppColors.primary,
                          variant: PillVariant.soft,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    due > 0
                        ? '待复习 $due · 已学 $learned / $total'
                        : '已学 $learned / $total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mutedCaption(size: 11, context: context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.of(context).inkSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

Color _categoryColor(String category) => switch (category) {
  '编程' => const Color(0xFF3977C2),
  '考试英语' => const Color(0xFFBC6A32),
  '青少年英语' => const Color(0xFF8D6BB8),
  '专业词汇' => const Color(0xFF3A8C7A),
  '语言' => const Color(0xFFD29B2C),
  _ => const Color(0xFF687673),
};
