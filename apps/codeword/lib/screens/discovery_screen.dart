import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lib_core/lib_core.dart';
import 'package:lib_ui/lib_ui.dart';

import '../state/learning_session.dart';
import 'learning_session_screen.dart';

/// 发现 — search and browse the full qwerty-derived catalog.
///
/// The library is grouped by category and can be filtered via the search
/// bar or the category chip row. Tapping a card launches its learning
/// session directly.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

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

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x5,
              AppSpacing.x4,
              AppSpacing.x5,
              AppSpacing.x3,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('发现', style: AppTheme.screenHeader()),
                      ),
                      Text(
                        '${lists.length} 本词书',
                        style: AppTheme.mutedCaption(size: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _SearchField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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
                ],
              ),
            ),
          ),
          if (categories.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: EmptyHint(
                  icon: Icons.search_off_outlined,
                  message: '没有找到相关词书',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x5,
                0,
                AppSpacing.x5,
                AppSpacing.x8,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final cat = categories[index];
                    return _CategorySection(
                      category: cat,
                      lists: grouped[cat]!,
                      available: meta,
                    );
                  },
                  childCount: categories.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Display order for categories. Anything not in here goes last.
  static const _categoryPriority = [
    '考试英语',
    '编程',
    '青少年英语',
    '语言',
    '词典',
    '专业词汇',
  ];

  Map<String, List<VocabList>> _groupAndFilter(List<VocabList> lists) {
    final byCategory = <String, List<VocabList>>{};
    for (final l in lists) {
      if (_selectedCategory != null && l.category != _selectedCategory) continue;
      if (_query.isNotEmpty) {
        final haystack = '${l.name} ${l.description} ${l.category}'.toLowerCase();
        if (!haystack.contains(_query)) continue;
      }
      byCategory.putIfAbsent(l.category, () => []).add(l);
    }
    for (final entry in byCategory.values) {
      entry.sort((a, b) => a.name.compareTo(b.name));
    }
    return byCategory;
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
        hintStyle: AppTheme.mutedCaption(size: 14, color: AppColors.inkSubtle),
        prefixIcon: const Icon(Icons.search, color: AppColors.inkSubtle, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.inkSubtle, size: 18),
              onPressed: onClear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.surface,
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
    // Use MediaQuery.textScalerOf to respect user's system text size,
    // and size the chip row to fit. Fixed 36px heights clip the text on
    // textScaleFactor > 1.2 (accessibility / large-font users).
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        vertical: Theme.of(context).chipTheme.labelPadding?.vertical ?? 4,
      ),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.x2),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final isSelected = (cat == '全部' && selected == null) || cat == selected;
        return ChoiceChip(
          label: Text(cat),
          selected: isSelected,
          onSelected: (_) => onSelected(cat),
          labelStyle: AppTheme.rowTitle().copyWith(
            fontSize: 13,
            color: isSelected ? AppColors.primary : AppColors.inkMuted,
          ),
          selectedColor: AppColors.primarySoft,
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: isSelected
                ? AppColors.primarySoft
                : AppColors.inkSubtle.withValues(alpha: 0.2),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String category;
  final List<VocabList> lists;
  final Map<String, VocabList> available;

  const _CategorySection({
    required this.category,
    required this.lists,
    required this.available,
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
            style: AppTheme.sectionLabel().copyWith(
              fontSize: 13,
              letterSpacing: 0.6,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.x3,
          crossAxisSpacing: AppSpacing.x3,
          childAspectRatio: 1.55,
          children: [
            for (final l in lists)
              _LibraryTile(list: l, available: available.containsKey(l.id)),
          ],
        ),
      ],
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  final VocabList list;
  final bool available;

  const _LibraryTile({required this.list, required this.available});

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
      onTap: available
          ? () async {
              HapticFeedback.selectionClick();
              // Persist the selection so the home tab uses this book.
              ref.read(selectedVocabProvider.notifier).state = list.id;
              try {
                await ReviewRepository.instance.setSelectedVocabId(list.id);
              } catch (_) {}
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LearningSessionScreen(vocabId: list.id),
                ),
              );
            }
          : null,
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
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 18)
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
            children: [
              Text(
                list.name,
                style: AppTheme.rowTitle(
                  color: isCurrent ? AppColors.primary : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                list.description,
                style: AppTheme.mutedCaption(size: 11).copyWith(height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
