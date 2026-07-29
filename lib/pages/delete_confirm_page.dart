import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../utils/ui_feedback.dart';

/// 通用删除确认页。
///
/// 统一的「强制确认删除」机制，适用于角色卡 / 世界 / 单聊 / 群聊等可归档实体。
///
/// 两种确认模式由 [requireName] 决定：
/// * 强制输入名称（默认，[requireName] 为 true）：先完整输入 [validNames] 中的
///   某个名称，点击「确认删除」后，整个页面自动从上到下滚动 5 秒展示当前内容；
///   滚动期间可「反悔」取消，反悔后想再删需重新走 5 秒滚动确认。
/// * 长按删除（[requireName] 为 false，仅角色卡在关闭对应设置时启用）：右下角
///   长按按钮 5 秒，期间页面同步自动从上到下滚动展示内容；松开则重置，需从头
///   再按 5 秒。
///
/// 删除成功后由 [onDelete] 负责写库与备份，并返回备份文件路径（或 null）。
class DeleteConfirmPage extends StatefulWidget {
  const DeleteConfirmPage({
    super.key,
    required this.controller,
    required this.title,
    required this.entityName,
    required this.validNames,
    required this.promptHint,
    required this.contentBuilder,
    required this.onDelete,
    this.requireName = true,
  });

  final AppController controller;
  final String title;
  final String entityName;

  /// 可接受的确认识别名（输入去除首尾空白后需命中其中之一）。
  /// 为空时退化为「输入任意非空内容」即可（用于关联数据缺失的兜底）。
  final List<String> validNames;

  /// 输入框上方的提示文案（告知用户应输入什么）。
  final String promptHint;

  /// 构建可滚动的内容预览（传入本页 context，以便读取主题）。
  final List<Widget> Function(BuildContext) contentBuilder;

  /// 执行删除与备份，返回备份文件路径；失败返回 null。
  final Future<String?> Function() onDelete;

  /// 是否强制输入名称确认。false 时改用长按按钮（5 秒）。
  final bool requireName;

  @override
  State<DeleteConfirmPage> createState() => _DeleteConfirmPageState();
}

class _DeleteConfirmPageState extends State<DeleteConfirmPage>
    with TickerProviderStateMixin {
  static const Duration _confirmDuration = Duration(seconds: 5);

  late final ScrollController _scrollController;
  late final AnimationController _animController;
  late final TextEditingController _nameInput;

  bool _scrolling = false;
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

  bool get _autoScrolling => _scrolling || _pressing;

  bool get _nameMatches {
    final String input = _nameInput.text.trim();
    if (widget.validNames.isEmpty) {
      return input.isNotEmpty;
    }
    return widget.validNames.contains(input);
  }

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

  void _startAutoScrollConfirm() {
    if (!_nameMatches) {
      return;
    }
    setState(() => _scrolling = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _animController.forward(from: 0);
    });
  }

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
    final String? backupPath = await widget.onDelete();
    if (!mounted) return;
    showSnack(
      context,
      backupPath != null
          ? '已删除「${widget.entityName}」，JSON 备份已保存'
          : '已删除「${widget.entityName}」',
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

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: <Widget>[
          _buildTopBar(cs),
          Expanded(
            child: ListView(
              controller: _scrollController,
              physics: _autoScrolling ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: <Widget>[
                ...widget.contentBuilder(context),
                const SizedBox(height: 240),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton:
          widget.requireName ? null : _buildLongPressButton(cs),
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    final TextTheme tt = Theme.of(context).textTheme;

    if (widget.requireName) {
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
              widget.promptHint,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameInput,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '名称',
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
        '长按右下角按钮 5 秒以删除。期间页面会自动滚动供你查阅，松开需重头开始。',
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
}
