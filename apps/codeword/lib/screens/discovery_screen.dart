import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';
import '../state/app_settings.dart';
import 'settings_screen.dart';

/// 词书 — search and browse the full qwerty-derived catalog.
///
/// The library is grouped by category and can be filtered via the search
/// bar or the category chip row. Tapping a card launches its learning
/// session directly. Settings remains a secondary page from this tab.
class DiscoveryScreen extends ConsumerStatefulWidget {
  final VoidCallback onGoWords;

  const DiscoveryScreen({super.key, required this.onGoWords});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(vocabMetaProvider);
    final lists = ref.watch(qwertyCatalogProvider);
    ref.watch(reviewStateProvider);
    final stats = ref.read(reviewStateProvider.notifier).stats(catalog: lists);
    final selectedVocab = ref.watch(selectedVocabProvider);
    final current = meta[selectedVocab];
    final currentProgress = vocabProgressFor(stats, selectedVocab);

    final grouped = _groupAndFilter(lists);
    final categories = grouped.keys.toList()
      ..sort((a, b) {
        final ai = _categoryPriority.indexOf(a);
        final bi = _categoryPriority.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    return TabPageScaffold(
      title: '词书',
      scrollKey: const PageStorageKey('library-scroll'),
      trailing: IconButton.filledTonal(
        tooltip: '设置',
        onPressed: () {
          HapticFeedback.selectionClick();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
        icon: const Icon(Icons.settings_outlined, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.of(context).surface,
          foregroundColor: AppColors.of(context).inkMuted,
          minimumSize: const Size(44, 44),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchField(
                controller: _searchController,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: AppSpacing.x3),
              _CategoryChips(
                categories: [
                  '全部',
                  ...lists.map((l) => l.category).toSet().toList()..sort(),
                ],
                selected: _selectedCategory,
                onSelected: (cat) => setState(
                  () => _selectedCategory = cat == '全部' ? null : cat,
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              _CurrentBookCard(
                current: current,
                progress: currentProgress,
                totalBooks: lists.length,
                onContinue: current == null
                    ? null
                    : () => _startBook(current.id),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x5)),
        if (categories.isEmpty)
          SliverToBoxAdapter(
            child: AppCard(
              child: const SizedBox(
                height: 160,
                child: Center(
                  child: EmptyHint(
                    icon: Icons.search_off_outlined,
                    message: '没有找到相关词书',
                  ),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final cat = categories[index];
              return _CategorySection(
                category: cat,
                lists: grouped[cat]!,
                available: meta,
                onSelect: _selectBook,
                onStart: _startBook,
              );
            }, childCount: categories.length),
          ),
      ],
    );
  }

  /// Display order for categories. Anything not in here goes last.
  static const _categoryPriority = ['考试英语', '编程', '青少年英语', '语言', '词典', '专业词汇'];

  Map<String, List<VocabList>> _groupAndFilter(List<VocabList> lists) {
    final byCategory = <String, List<VocabList>>{};
    for (final l in lists) {
      if (_selectedCategory != null && l.category != _selectedCategory) {
        continue;
      }
      if (_query.isNotEmpty) {
        final haystack = '${l.name} ${l.description} ${l.category}'
            .toLowerCase();
        if (!haystack.contains(_query)) continue;
      }
      byCategory.putIfAbsent(l.category, () => []).add(l);
    }
    for (final entry in byCategory.values) {
      entry.sort((a, b) => a.name.compareTo(b.name));
    }
    return byCategory;
  }

  Future<void> _selectBook(String vocabId, {bool resetSession = true}) async {
    HapticFeedback.selectionClick();
    final changed = ref.read(selectedVocabProvider) != vocabId;
    ref.read(selectedVocabProvider.notifier).state = vocabId;
    try {
      await ReviewRepository.instance.setSelectedVocabId(vocabId);
    } catch (_) {}
    if (changed && resetSession) await _loadSession(vocabId);
  }

  Future<void> _startBook(String vocabId) async {
    await _selectBook(vocabId, resetSession: false);
    await _loadSession(vocabId);
    if (mounted) widget.onGoWords();
  }

  Future<void> _loadSession(String vocabId) async {
    await ref.read(appSettingsProvider.notifier).ready;
    if (!mounted) return;
    final settings = ref.read(appSettingsProvider);
    await ref
        .read(learningSessionProvider.notifier)
        .start(
          vocabId: vocabId,
          dailyNewWordLimit: settings.dailyNewWords,
          maxSessionSize: settings.dailyNewWords + 20,
        );
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
      controller: controller,
      onChanged: onChanged,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: '搜索词书、分类…',
        hintStyle: AppTheme.mutedCaption(
          size: 14,
          color: AppColors.of(context).inkSubtle,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: AppColors.of(context).inkSubtle,
          size: 20,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: AppColors.of(context).inkSubtle,
                size: 18,
              ),
              onPressed: onClear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.of(context).surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
      ),
    );
  }
}

class _CurrentBookCard extends StatelessWidget {
  final VocabList? current;
  final VocabProgress? progress;
  final int totalBooks;
  final VoidCallback? onContinue;

  const _CurrentBookCard({
    required this.current,
    required this.progress,
    required this.totalBooks,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final total = progress?.availableWords ?? current?.wordCount ?? 0;
    final learned = progress?.learned ?? 0;
    final due = progress?.due ?? 0;
    final pct = total == 0 ? 0.0 : (learned / total).clamp(0.0, 1.0);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.x5),
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
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.library_books,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current?.name ?? '选择一本词书',
                      style: AppTheme.cardTitle(context: context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalBooks 本词书 · ${due > 0 ? "待复习 $due" : "继续积累"}',
                      style: AppTheme.mutedCaption(size: 12, context: context),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4,
                  ),
                ),
                child: const Text('继续学习'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: palette.surfaceMuted,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            total == 0 ? '先选择词书开始学习' : '已学 $learned / $total',
            style: AppTheme.mutedCaption(size: 12, context: context),
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Horizontal ListView inside a Column needs a bounded cross-axis height.
    // IndexedStack keeps every tab mounted, so an unbounded chip row would
    // crash layout for the whole shell — not just the Discovery tab.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final verticalPad = Theme.of(context).chipTheme.labelPadding?.vertical ?? 4;
    final rowHeight = (36 * textScale).clamp(36.0, 56.0) + verticalPad * 2;
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(vertical: verticalPad),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.x2),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected =
              (cat == '全部' && selected == null) || cat == selected;
          return ChoiceChip(
            label: Text(cat),
            selected: isSelected,
            onSelected: (_) => onSelected(cat),
            labelStyle: AppTheme.rowTitle().copyWith(
              fontSize: 13,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.of(context).inkMuted,
            ),
            selectedColor: AppColors.primarySoft,
            backgroundColor: AppColors.of(context).surface,
            side: BorderSide(
              color: isSelected
                  ? AppColors.primarySoft
                  : AppColors.of(context).inkSubtle.withValues(alpha: 0.2),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<VocabList> lists;
  final Map<String, VocabList> available;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onStart;

  const _CategorySection({
    required this.category,
    required this.lists,
    required this.available,
    required this.onSelect,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.x3,
            bottom: AppSpacing.x3,
          ),
          child: Text(
            '$category · ${lists.length}',
            style: AppTheme.sectionLabel(
              context: context,
            ).copyWith(fontSize: 13, letterSpacing: 0.6),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.x3,
          crossAxisSpacing: AppSpacing.x3,
          childAspectRatio: 1.0,
          children: [
            for (final l in lists)
              _LibraryTile(
                list: l,
                available: available.containsKey(l.id),
                onSelect: onSelect,
                onStart: onStart,
              ),
          ],
        ),
      ],
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  final VocabList list;
  final bool available;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onStart;

  const _LibraryTile({
    required this.list,
    required this.available,
    required this.onSelect,
    required this.onStart,
  });

  Color _color() {
    final h = list.id.hashCode.abs() % AppColors.qwertyPalette.length;
    return AppColors.qwertyPalette[h >= 0 ? h : 0];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _color();
    final selectedVocab = ref.watch(selectedVocabProvider);
    final isCurrent = selectedVocab == list.id;
    return AppCard(
      onTap: available ? () => onSelect(list.id) : null,
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: AppSpacing.x5,
                height: AppSpacing.x5,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                alignment: Alignment.center,
                child: Builder(
                  builder: (context) {
                    final chars = list.name.characters;
                    return Text(
                      chars.isEmpty ? '·' : chars.first,
                      style: AppTheme.cardTitle().copyWith(
                        fontSize: 16,
                        color: color,
                      ),
                    );
                  },
                ),
              ),
              if (isCurrent)
                const PillTag(
                  label: '当前',
                  color: AppColors.primary,
                  icon: Icons.check,
                )
              else if (available)
                PillTag(
                  label: 'Lv ${list.level}',
                  color: color,
                  variant: PillVariant.soft,
                )
              else
                const PillTag(
                  label: '即将推出',
                  color: AppColors.inkSubtle,
                  variant: PillVariant.soft,
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                list.name,
                style: AppTheme.rowTitle(
                  color: isCurrent ? AppColors.primary : null,
                  context: context,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Flexible so the description yields inside the fixed-height
              // grid cell instead of forcing a vertical overflow when the
              // OS text scale grows.
              Flexible(
                child: Text(
                  list.description,
                  style: AppTheme.mutedCaption(
                    size: 11,
                    context: context,
                  ).copyWith(height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              SizedBox(
                height: 30,
                child: OutlinedButton(
                  onPressed: available ? () => onStart(list.id) : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x3,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(isCurrent ? '继续' : '开始'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
