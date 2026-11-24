part of '../chat_surface.dart';

mixin ChatActionsInspiration on ChatStateMixin {
  List<Map<String, dynamic>> _buildInspirationPayload(String topic);

  Future<void> _startInspiration() async {
    if (_inspirationInProgress) {
      return;
    }
    final String model = widget.controller.settings.selectedModel;
    final String apiKey = widget.controller.settings.apiKey;
    final String baseUrl = widget.controller.settings.baseUrl;
    if (!ensureApiReady(context: context, controller: widget.controller)) {
      return;
    }
    // 一个 sheet 走完「填主题 → 生成 → 选用」。
    // 以前是先弹 dialog 让用户输入主题、生成完再弹第二个 sheet 看候选，
    // 连续两个模态面（审计 3.2）。
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _InspirationSheet(
        accentTheme: _accentTheme,
        initialTopic: _inspirationPrompt,
        onGenerate: (String topic) async {
          _inspirationPrompt = topic;
          setState(() => _inspirationInProgress = true);
          try {
            final List<String> next = await _generateInspirations(
              _buildInspirationPayload(topic),
              count: 3,
              model: model,
              apiKey: apiKey,
              baseUrl: baseUrl,
            );
            if (next.isNotEmpty) {
              _inspirationOptions
                ..clear()
                ..addAll(next);
            }
            return next;
          } finally {
            if (mounted) {
              setState(() => _inspirationInProgress = false);
            }
          }
        },
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) {
      return;
    }
    // 选用：填进输入框，发不发仍由用户决定（与改造前一致）。
    _inputController.text = picked;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: picked.length),
    );
  }

  Future<List<String>> _generateInspirations(
    List<Map<String, dynamic>> payload, {
    required int count,
    required String model,
    required String apiKey,
    required String baseUrl,
  }) {
    // 与「重说」共用同一个候选生成器；差别只在清洗方式：灵感要剥思考标签。
    return generateChatCandidates(
      controller: widget.controller,
      payload: payload,
      sequential: widget.controller.settings.retrySequential,
      count: count,
      transform: (String raw) => stripThoughtTags(raw).trim(),
    );
  }
}

/// 「生成灵感」的单一 sheet：顶部填主题 → 生成 → 候选列表 → 选用。
///
/// 以前是「dialog 输主题」+「sheet 看候选」两个模态面（审计 3.2）。合并后
/// 一次打开就能完成；主题是必填项，错误就地显示（旧流程里直接弹 snackbar）。
/// 候选仍是 RetryOptionCard（点击选中 → 底部「使用」），「再试」只追加新批次
/// 并给新结果打「新」标。
class _InspirationSheet extends StatefulWidget {
  const _InspirationSheet({
    required this.accentTheme,
    required this.initialTopic,
    required this.onGenerate,
  });

  final ThemeData accentTheme;

  /// 上一次用过的主题（首次打开为空串）。
  final String initialTopic;

  /// 生成一批候选：由聊天页实现（负责置 _inspirationInProgress 并发请求）。
  final Future<List<String>> Function(String topic) onGenerate;

  @override
  State<_InspirationSheet> createState() => _InspirationSheetState();
}

class _InspirationSheetState extends State<_InspirationSheet> {
  late final TextEditingController _topicController = TextEditingController(
    text: widget.initialTopic,
  );

  bool _loading = false;
  String? _topicError;
  String _lastTopic = '';
  final List<String> _options = <String>[];
  int _newlyAdded = 0;
  int? _selectedIndex;

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final String topic = _topicController.text.trim();
    if (topic.isEmpty) {
      setState(() => _topicError = '请先填写灵感主题。');
      return;
    }
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _topicError = null;
    });
    final List<String> next = await widget.onGenerate(topic);
    if (!mounted) {
      return;
    }
    if (next.isEmpty) {
      setState(() {
        _loading = false;
        _topicError = '生成失败，请再试。';
      });
      return;
    }
    setState(() {
      _loading = false;
      // 换了主题 = 新一批：旧候选作废，避免上一题的答案混进这一题。
      if (_lastTopic != topic) {
        _options.clear();
        _selectedIndex = null;
      }
      _lastTopic = topic;
      _options.addAll(next);
      _newlyAdded = next.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int firstNewIndex = _options.length - _newlyAdded;
    return Theme(
      data: widget.accentTheme,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.lightbulb, color: cs.primary),
                    const SizedBox(width: 8),
                    FitText('灵感列表', style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _topicController,
                  autofocus: _options.isEmpty,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _generate(),
                  decoration: InputDecoration(
                    labelText: '灵感主题',
                    hintText: '例如 重新开场 / 继续推进 / 某个话题',
                    errorText: _topicError,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: FitText(_loading ? '生成中…' : '生成'),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              Flexible(
                child: _options.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: FitText(
                            '填好主题后点「生成」，灵感会出现在这里。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        children: <Widget>[
                          for (int i = 0; i < _options.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: RetryOptionCard(
                                index: i,
                                text: _options[i],
                                isNew: _newlyAdded > 0 && i >= firstNewIndex,
                                selected: _selectedIndex == i,
                                onTap: () =>
                                    setState(() => _selectedIndex = i),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const FitText('关闭'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: (_loading || _lastTopic.isEmpty)
                            ? null
                            : _generate,
                        icon: const Icon(Icons.autorenew),
                        label: const FitText('再试'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _selectedIndex == null || _loading
                            ? null
                            : () => Navigator.of(context).pop(
                                  _options[_selectedIndex!],
                                ),
                        child: const FitText('使用'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
