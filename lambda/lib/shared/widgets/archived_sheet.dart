import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import 'container_styles.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';

/// Bottom sheet listing archived dims — search, 10 per page with a pager,
/// tap a row to re-enable it. Self-contained (its own pager + page size) so
/// every library tab can reuse it.
class ArchivedSheet extends StatefulWidget {
  const ArchivedSheet({
    super.key,
    required this.title,
    required this.emptyText,
    required this.fetch,
    required this.onRestore,
    this.onDelete,
  });

  final String title;
  final String emptyText;
  final Future<List<({String id, String name})>> Function() fetch;
  final Future<void> Function(String id) onRestore;

  /// Null for libraries that can only be restored. When non-null every row
  /// grows a delete affordance, and this owns the confirmation — only the
  /// caller knows what the delete costs, so the sheet never asks on its own.
  final Future<void> Function(({String id, String name}) item)? onDelete;

  @override
  State<ArchivedSheet> createState() => _ArchivedSheetState();
}

class _ArchivedSheetState extends State<ArchivedSheet> {
  static const _pageSize = 10;
  final _searchController = TextEditingController();
  List<({String id, String name})> _items = const [];
  bool _loading = true;
  String _query = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {
      _query = _searchController.text;
      _page = 0;
    }));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await widget.fetch();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  List<({String id, String name})> get _filtered => _query.isEmpty
      ? _items
      : _items
            .where(
              (i) => i.name.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList();

  List<({String id, String name})> get _paged {
    final start = (_page * _pageSize).clamp(0, _filtered.length);
    final end = ((_page + 1) * _pageSize).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  bool get _canPrev => _page > 0;
  bool get _canNext => (_page + 1) * _pageSize < _filtered.length;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _searchController,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.primary,
              ),
              decoration: InputDecoration(
                hintText: 'Search…',
                hintStyle: AppFonts.ui(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (_filtered.isEmpty)
              Text(
                widget.emptyText,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.muted,
                ),
              )
            else ...[
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _paged.length,
                  itemBuilder: (context, i) {
                    final item = _paged[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () async {
                        await widget.onRestore(item.id);
                        await _load();
                      },
                      title: Text(
                        toProperCase(item.name),
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      trailing: widget.onDelete == null
                          ? Icon(
                              Icons.restore,
                              size: 18,
                              color: AppColors.accent,
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restore,
                                  size: 18,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                // Opaque, so the tap lands on the bin rather
                                // than falling through to the row's restore.
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    await widget.onDelete!(item);
                                    await _load();
                                  },
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
              if (_filtered.length > _pageSize)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PagerButton(
                        icon: Icons.chevron_left,
                        enabled: _canPrev,
                        onTap: () => setState(() => _page--),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        // Cumulative: everything shown up to this page.
                        '${((_page + 1) * _pageSize).clamp(0, _filtered.length)} of ${_filtered.length}',
                        style: AppFonts.mono(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _PagerButton(
                        icon: Icons.chevron_right,
                        enabled: _canNext,
                        onTap: () => setState(() => _page++),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        // The glass recipe — enabled in accent, disabled stays muted.
        decoration: enabled
            ? glassBox(AppColors.accent)
            : lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.accent : AppColors.muted,
        ),
      ),
    );
  }
}
