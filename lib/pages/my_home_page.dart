import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../island/island_import_entry.dart';
import '../models/ta.dart';
import '../services/image_storage.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_container.dart';
import '../widgets/app_icon_flight.dart';
import '../widgets/app_section.dart';
import '../widgets/ta_avatar.dart';
import '../widgets/ta_cover.dart';
import 'ta_editor_page.dart';
import 'ta_showcase_page.dart';
import 'package:dna/widgets/app_empty_state.dart';
import 'package:dna/widgets/fit_text.dart';

/// 我家栏目装配。
SectionPageData myHomeSection(AppController controller) {
  final ValueNotifier<bool> showArchived = ValueNotifier<bool>(false);

  void createTa(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => TaEditorPage(controller: controller),
      ),
    );
  }

  return SectionPageData(
    section: AppSection.myHome,
    showArchived: showArchived,
    // 瀑布流卡片墙:和群聊/身份一样用卡片网格的宽度,桌面才排得开列。
    contentMaxWidth: AppSize.cardGridMaxWidth,
    appBar: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => AppBar(
        title: FitText(archived ? 'TA归档' : '我家'),
        actions: <Widget>[
          if (!archived)
            // 从岛导入角色卡:粘贴链接/ID → 卡片页 → 试聊或直接导入。
            // 只依赖公开的卡片详情,没登录也能用。
            IconButton(
              tooltip: '从岛导入角色卡',
              onPressed: () => openIslandCardImport(context, controller),
              icon: const Icon(Icons.travel_explore_outlined),
            ),
          IconButton(
            tooltip: archived ? '查看TA' : '查看归档',
            onPressed: () => showArchived.value = !archived,
            icon: Icon(
              archived ? Icons.people_outline : Icons.archive_outlined,
            ),
          ),
          if (!archived)
            // 新建TA页:从图标位置放大,返回时缩回。
            AppBarIconAction<bool>(
              tooltip: '创建TA',
              icon: Icons.add,
              pageBuilder: (BuildContext context) =>
                  TaEditorPage(controller: controller),
            ),
        ],
      ),
    ),
    body: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => TaListBody(
        controller: controller,
        showArchived: archived,
        onCreateTa: () => createTa(context),
      ),
    ),
    fab: (BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: showArchived,
      builder: (BuildContext context, bool archived, Widget? _) => !archived
          // FAB 即源容器:圆形按钮放大为整页编辑器。
          ? AppContainer<bool>(
              closedShape: const CircleBorder(),
              closedBuilder: (BuildContext context, VoidCallback open) =>
                  FloatingActionButton(
                    onPressed: open,
                    child: const Icon(Icons.add),
                  ),
              openBuilder: (BuildContext context, VoidCallback close) =>
                  TaEditorPage(controller: controller),
            )
          : const SizedBox.shrink(),
    ),
  );
}

/// 「我家」主体:**瀑布流卡片墙**。
///
/// * 卡片高度由立绘槽位决定(1:1 → 竖 → 横,见 [TaCover])—— 不用等图片
///   解码就知道该给多高,所以排版不会跳;
/// * 点卡片进角色展示页;长按进入**排序模式**(网格切成可拖拽列表,沿用
///   原来的拖拽交互),顶部出现「完成」;
/// * 手写瀑布流(每张卡丢进当前最矮的那一列),不引第三方依赖。
class TaListBody extends StatefulWidget {
  const TaListBody({
    super.key,
    required this.controller,
    required this.showArchived,
    required this.onCreateTa,
  });

  final AppController controller;
  final bool showArchived;
  final VoidCallback onCreateTa;

  @override
  State<TaListBody> createState() => _TaListBodyState();
}

class _TaListBodyState extends State<TaListBody> {
  /// 排序模式:长按卡片进入,点「完成」退出。
  bool _reordering = false;

  /// 每列至少这么宽:手机 2 列,桌面能排到 4 列。
  static const double _minColumnWidth = 240;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final List<TA> tas = widget.controller.tas
            .where((TA t) => t.archived == widget.showArchived)
            .toList();

        if (tas.isEmpty) {
          return AppEmptyState(
            icon: widget.showArchived
                ? Icons.archive_outlined
                : Icons.people_outline,
            title: widget.showArchived ? '还没有归档TA。' : '暂无TA，先创建一个吧。',
            actionLabel: widget.showArchived ? null : '创建TA',
            actionIcon: widget.showArchived ? null : Icons.add,
            onAction: widget.showArchived ? null : widget.onCreateTa,
          );
        }

        // 归档列表不参与排序(归档的 TA 不在「我家」顺序里)。
        final bool canReorder = !widget.showArchived;
        if (_reordering && canReorder) {
          return _buildReorderList(context, tas);
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              SingleChildScrollView(
                padding: AppInsets.card,
                child: _buildMasonry(
                  context,
                  tas,
                  _columnsFor(constraints.maxWidth),
                  canReorder,
                ),
              ),
        );
      },
    );
  }

  int _columnsFor(double width) => (width / _minColumnWidth).floor().clamp(2, 4);

  /// 手写瀑布流:每张卡丢进"当前最矮的那一列";列高用立绘比例的倒数估算。
  Widget _buildMasonry(
    BuildContext context,
    List<TA> tas,
    int columns,
    bool canReorder,
  ) {
    final List<List<TA>> buckets = List<List<TA>>.generate(
      columns,
      (_) => <TA>[],
    );
    final List<double> filled = List<double>.filled(columns, 0);
    for (final TA ta in tas) {
      int target = 0;
      for (int i = 1; i < columns; i++) {
        if (filled[i] < filled[target] - 0.001) {
          target = i;
        }
      }
      buckets[target].add(ta);
      // 卡片高度 ≈ 宽度 / 宽高比(名字那行是常数,不影响分列结果)
      filled[target] += 1 / TaCover.ratioOf(TaCover.slotOf(ta));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < columns; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              children: <Widget>[
                for (final TA ta in buckets[i])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: _TaCard(
                      controller: widget.controller,
                      ta: ta,
                      onLongPress: canReorder ? _enterReorder : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _enterReorder() {
    HapticFeedback.mediumImpact();
    setState(() => _reordering = true);
  }

  Widget _buildReorderList(BuildContext context, List<TA> tas) {
    return Column(
      children: <Widget>[
        _buildReorderHeader(context),
        Expanded(
          child: ReorderableListView.builder(
            padding: AppInsets.card,
            buildDefaultDragHandles: false,
            itemCount: tas.length,
            // 这里刻意用旧的 onReorder:reorderTas 内部已经做了
            // 「newIndex > oldIndex 时 -1」的调整,换成 onReorderItem
            // (它会**预先**调整)就成了双重调整,顺序会错。
            // ignore: deprecated_member_use
            onReorder: (int oldIndex, int newIndex) async {
              await widget.controller.reorderTas(oldIndex, newIndex);
            },
            itemBuilder: (BuildContext context, int index) => _ReorderRow(
              key: ValueKey<String>(tas[index].id),
              ta: tas[index],
              index: index,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReorderHeader(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.drag_indicator, size: 18, color: cs.onSecondaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FitText(
                '拖动调整顺序（侧栏与左右滑动也按这个顺序）',
                style: TextStyle(color: cs.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _reordering = false),
              child: const FitText('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 瀑布流里的一张角色卡:立绘 + 名字(+ 标签/简介一行)。
class _TaCard extends StatelessWidget {
  const _TaCard({required this.controller, required this.ta, this.onLongPress});

  final AppController controller;
  final TA ta;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? slot = TaCover.slotOf(ta);
    final ImageProvider? image = slot == null
        ? null
        : ImageStorage.instance.providerFor(ta, slot);
    final String subtitle = ta.tags.isNotEmpty
        ? ta.tags.take(2).join(' · ')
        : ta.intro;
    final BorderRadius radius = BorderRadius.circular(AppRadius.md);

    return AppContainer<bool>(
      closedBuilder: (BuildContext context, VoidCallback open) => Material(
        color: cs.surfaceContainerLow,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AspectRatio(
                aspectRatio: TaCover.ratioOf(slot),
                child: image != null
                    ? Image(
                        // 只限宽,保持原始比例(限宽已经足够压住内存)
                        image: ResizeImage.resizeIfNeeded(600, null, image),
                        fit: BoxFit.cover,
                      )
                    : ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Center(
                          child: TaAvatar(
                            ta: ta,
                            size: 56,
                            borderRadius: AppRadius.sm,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FitText(
                      ta.name.trim().isEmpty ? '未命名TA' : ta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (subtitle.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      FitText(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // 卡片本身就是"源容器":点开时从卡片位置放大成展示页。
      openBuilder: (BuildContext context, VoidCallback close) =>
          TaShowcasePage(controller: controller, taId: ta.id),
    );
  }
}

/// 排序模式里的一行(可拖拽)。
class _ReorderRow extends StatelessWidget {
  const _ReorderRow({super.key, required this.ta, required this.index});

  final TA ta;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final ImageProvider? image = ImageStorage.instance.providerFor(ta, 'square');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              if (image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: Image(
                    image: ResizeImage.resizeIfNeeded(96, 96, image),
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                )
              else
                TaAvatar(ta: ta, size: 44, borderRadius: AppRadius.xs),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FitText(
                  ta.name.trim().isEmpty ? '未命名TA' : ta.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
