import 'dart:io';

import 'package:flutter/material.dart';

import '../models/dialogue_style.dart';
import '../models/ta.dart';
import '../state/app_controller.dart';
import '../utils/ui_feedback.dart';

/// 角色卡删除确认页。
///
/// 仅用于已归档的角色卡。提供两种删除确认方式（由设置项
/// `requireNameToDeleteTa` 决定）：
///
/// * 强制输入角色名（默认）：先完整输入角色名，点击「确认删除」后，整个页面
///   自动从上到下滚动 5 秒展示当前角色内容；滚动期间可「反悔」取消，反悔后想
///   再删需重新走 5 秒滚动确认。
/// * 长按删除（关闭强制输入后）：右下角长按按钮 5 秒，期间页面同步自动从上到
///   下滚动展示内容；松开则重置，需从头再按 5 秒。
///
/// 删除成功后自动备份该角色的完整 JSON（含图片）到特定目录。
class TaDeleteConfirmPage extends StatefulWidget {
  const TaDeleteConfirmPage({
    super.key,
    required this.controller,
    required this.ta,
  });

  final AppController controller;
  final TA ta;

  @override
  State<TaDeleteConfirmPage> createState() => _TaDeleteConfirmPageState();
}

class _TaDeleteConfirmPageState extends State<TaDeleteConfirmPage>
    with TickerProviderStateMixin {
  static const Duration _confirmDuration = Duration(seconds: 5);

  late final ScrollController _scrollController;
  late final AnimationController _animController;
  late final TextEditingController _nameInput;

  /// 模式 A：是否处于 5 秒滚动确认阶段。
  bool _scrolling = false;
  /// 模式 B：是否正在长按。
  bool _pressing = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(
      vsync: this,
      duration: _confirmDuration,
    )..addListener(_onAnimTick);
    _animController.addStatusListener(_onAnimStatus);
    _nameInput = TextEditingController();
  }

  @override
  void dispose() {
    _animController.removeListener(_onAnimTick);
    _animController.removeStatusListener(_onAnimStatus);
    _animController.dispose();
    _scrollController.dispose();
    _nameInput.dispose();
    super.dispose();
  }

  bool get _requireName => widget.controller.settings.requireNameToDeleteTa;

  bool get _autoScrolling => _scrolling || _pressing;

  bool get _nameMatches => _nameInput.text.trim() == widget.ta.name;

  void _onAnimTick() {
    if (_scrollController.hasClients) {
      final double max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(_animController.value * max);
    }
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_deleting) {
      _doDelete();
    }
  }

  /// 启动 5 秒自动滚动确认（模式 A）。
  void _startAutoScrollConfirm() {
    if (!_nameMatches) {
      return;
    }
    setState(() => _scrolling = true);
    // 等一帧拿到准确的 maxScrollExtent 后再开始。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _animController.forward(from: 0);
    });
  }

  /// 反悔：取消滚动确认，回到输入阶段。
  void _regret() {
    _animController.stop();
    _animController.reset();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (mounted) {
      setState(() => _scrolling = false);
    }
  }

  // ===== 模式 B：长按 =====

  void _onPressDown() {
    if (_deleting) return;
    setState(() => _pressing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _animController.forward(from: 0);
    });
  }

  void _onPressUp() {
    if (_deleting) return;
    if (_animController.status == AnimationStatus.completed) {
      // 已完成，删除流程接管。
      return;
    }
    _animController.stop();
    _animController.reset();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (mounted) {
      setState(() => _pressing = false);
    }
  }

  Future<void> _doDelete() async {
    if (_deleting) return;
    _deleting = true;
    final String? backupPath =
        await widget.controller.deleteTaWithBackup(widget.ta.id);
    if (!mounted) return;
    showSnack(
      context,
      backupPath != null ? '已删除「${widget.ta.name}」，JSON 备份已保存' : '已删除「${widget.ta.name}」',
      behavior: SnackBarBehavior.floating,
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  int get _remainingSeconds {
    final int s = (_confirmDuration.inSeconds * (1 - _animController.value)).ceil();
    return s < 0 ? 0 : s;
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('删除角色')),
      body: Column(
        children: <Widget>[
          _buildTopBar(cs),
          Expanded(child: _buildContent(cs)),
        ],
      ),
      floatingActionButton: !_requireName ? _buildLongPressButton(cs) : null,
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    final TextTheme tt = Theme.of(context).textTheme;
    final String name = widget.ta.name;

    if (_requireName) {
      // 模式 A
      if (_scrolling) {
        return AnimatedBuilder(
          animation: _animController,
          builder: (BuildContext context, Widget? child) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: cs.errorContainer.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: _animController.value,
                    color: cs.error,
                    backgroundColor: cs.error.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '正在滚动确认，$_remainingSeconds 秒后删除…',
                          style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _regret,
                        icon: const Icon(Icons.undo),
                        label: const Text('反悔'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: cs.errorContainer.withValues(alpha: 0.25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '请完整输入角色名「$name」以确认删除',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameInput,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '角色名',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _nameMatches ? _startAutoScrollConfirm : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('确认删除'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 模式 B
    if (_pressing) {
      return AnimatedBuilder(
        animation: _animController,
        builder: (BuildContext context, Widget? child) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: cs.errorContainer.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                  value: _animController.value,
                  color: cs.error,
                  backgroundColor: cs.error.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 8),
                Text(
                  '保持按住，$_remainingSeconds 秒后删除…（松开需重头开始）',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          );
        },
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: cs.errorContainer.withValues(alpha: 0.25),
      child: Text(
        '长按右下角按钮 5 秒以删除角色「$name」。期间页面会自动滚动供你查阅，松开需重头开始。',
        style: tt.bodyMedium,
      ),
    );
  }

  Widget _buildLongPressButton(ColorScheme cs) {
    return GestureDetector(
      onTapDown: (_) => _onPressDown(),
      onTapUp: (_) => _onPressUp(),
      onTapCancel: _onPressUp,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (BuildContext context, Widget? child) {
          return Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.errorContainer,
              shape: BoxShape.circle,
              border: Border.all(color: cs.error, width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: _animController.value,
                    strokeWidth: 6,
                    color: cs.error,
                    backgroundColor: cs.error.withValues(alpha: 0.15),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.delete_outline, color: cs.error),
                    const SizedBox(height: 2),
                    Text(
                      _pressing ? '$_remainingSeconds' : '长按',
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final TA ta = widget.ta;
    final TextTheme tt = Theme.of(context).textTheme;
    return ListView(
      controller: _scrollController,
      physics: _autoScrolling ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: <Widget>[
        _buildImageSection(cs, tt, ta),
        const SizedBox(height: 12),
        _buildInfoSection(cs, tt, ta),
        if (ta.dialogueStyle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _buildDialogueSection(cs, tt, ta),
        ],
        const SizedBox(height: 240),
      ],
    );
  }

  Widget _buildImageSection(ColorScheme cs, TextTheme tt, TA ta) {
    final List<Widget> slots = <Widget>[];
    void addSlot(String title, String? p, double aspect) {
      slots.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: tt.titleMedium),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: aspect,
                child: _imageOrPlaceholder(p, cs),
              ),
            ),
          ],
        ),
      ));
    }

    addSlot('1:1 形象', ta.images['square'], 1);
    addSlot('16:9 形象', ta.images['landscape'], 16 / 9);
    addSlot('9:16 形象', ta.images['portrait'], 9 / 16);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('TA 形象', style: tt.titleLarge),
            const SizedBox(height: 12),
            ...slots,
          ],
        ),
      ),
    );
  }

  Widget _imageOrPlaceholder(String? p, ColorScheme cs) {
    if (p == null || p.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
      );
    }
    return Image.file(
      File(p),
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
        );
      },
    );
  }

  Widget _buildInfoSection(ColorScheme cs, TextTheme tt, TA ta) {
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value.isEmpty ? '（空）' : value, style: tt.bodyMedium),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('人设', style: tt.titleLarge),
            const SizedBox(height: 12),
            row('名字', ta.name),
            row('性别', ta.gender),
            row('设定', ta.persona),
            row('介绍', ta.intro),
            row('开场白', ta.opening),
            if (ta.tags.isNotEmpty) ...<Widget>[
              Text('标签',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ta.tags
                    .map((String t) => Chip(label: Text(t)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDialogueSection(ColorScheme cs, TextTheme tt, TA ta) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('对话风格', style: tt.titleLarge),
            const SizedBox(height: 12),
            for (final DialogueTurn turn in ta.dialogueStyle) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('我：${turn.user}',
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('TA：${turn.assistant}', style: tt.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
