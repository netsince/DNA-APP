import 'package:flutter/material.dart';

import 'package:dna/island_app/api/client.dart' show ApiClient;
import 'package:dna/island_app/server_config.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/server_address_form.dart';

import 'oobe_steps.dart' show CommunityStepStatus;

/// 社区编辑页的返回结果。
class CommunityEditResult {
  const CommunityEditResult({
    required this.url,
    required this.status,
    required this.ignoreIssue,
  });

  final String url;
  final CommunityStepStatus status;
  final bool ignoreIssue;
}

/// OOBE「社区」步骤的编辑页。
///
/// 从折叠态点「改」进来。这里才放输入框、检测按钮和那些「不想让所有人第一眼
/// 看到」的东西：
/// * **更多选项** → 「忽略这个错误」（检测失败时可用）与「不常用选项」；
/// * **不常用选项** → 「不使用社区功能」（原本只在设置里的开关，提前到这里），
///   关闭前会劝阻一次。
///
/// 检测失败时「更多选项」会自动展开 —— 忽略这条路必须和以前一样摆在眼前，
/// 只是被归了组，不能因为折叠而变得难找。
class CommunityEditPage extends StatefulWidget {
  const CommunityEditPage({
    super.key,
    required this.initialUrl,
    required this.defaultUrl,
    required this.enableCommunity,
    required this.onToggleCommunity,
    this.validator,
  });

  final String initialUrl;
  final String defaultUrl;
  final bool enableCommunity;

  /// 开关社区功能（与「设置 → 界面与显示 → 社区」是同一项）。
  final ValueChanged<bool> onToggleCommunity;

  /// 注入用：地址校验器（测试时替换）。
  final Future<String?> Function(String url)? validator;

  @override
  State<CommunityEditPage> createState() => _CommunityEditPageState();
}

class _CommunityEditPageState extends State<CommunityEditPage> {
  late final TextEditingController _controller;
  bool _checking = false;
  bool _validated = false;
  String? _error;
  bool _ignoreIssue = false;
  bool _showMore = false;
  bool _showUncommon = false;
  late bool _enabled;

  Future<String?> Function(String url) get _validator =>
      widget.validator ?? ApiClient.instance.validateServer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialUrl.trim().isEmpty
          ? widget.defaultUrl
          : widget.initialUrl,
    );
    _enabled = widget.enableCommunity;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final String base = ServerConfig.normalize(_controller.text);
    if (base.isEmpty) {
      setState(() {
        _validated = false;
        _error = '请输入社区服务器地址';
        _ignoreIssue = false;
        _showMore = true;
      });
      return;
    }
    setState(() {
      _checking = true;
      _validated = false;
      _error = null;
      _ignoreIssue = false;
    });

    // 先落盘再检测：检测失败也不会丢掉用户填的地址。
    //
    // 整段包 try/catch：落盘或校验任何一步抛异常，都必须把 _checking 落回来 ——
    // 否则按钮会永远停在转圈状态，用户既检测不了也退不出去。
    String? error;
    try {
      await ServerConfig.setBaseUrl(base);
      if (!mounted) return;
      error = await _validator(base);
    } catch (_) {
      error = '检测失败，请稍后重试。';
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _validated = error == null;
      _error = error;
      // 失败时把「更多选项」摊开，忽略这条路和以前一样显眼。
      if (error != null) _showMore = true;
    });
  }

  void _useOfficial() {
    setState(() {
      _controller.text = widget.defaultUrl;
      _validated = false;
      _error = null;
      _ignoreIssue = false;
    });
  }

  void _pop() {
    if (!mounted) return;
    final String base = ServerConfig.normalize(_controller.text);
    final CommunityStepStatus status;
    if (_validated) {
      status = CommunityStepStatus.connected;
    } else if (_error == null) {
      status = CommunityStepStatus.unchecked;
    } else if (_ignoreIssue) {
      status = CommunityStepStatus.ignored;
    } else {
      status = CommunityStepStatus.failed;
    }
    Navigator.of(context).pop(
      CommunityEditResult(
        url: base.isEmpty ? widget.defaultUrl : base,
        status: status,
        ignoreIssue: _ignoreIssue,
      ),
    );
  }

  void _ignoreError() {
    setState(() => _ignoreIssue = true);
    _pop();
  }

  Future<void> _disableCommunity() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const FitText('确定不使用社区功能？'),
        content: const FitText(
          '关闭后，你将失去社区里百余个角色卡，以及与其他人的互动。\n\n'
          '之后可以在「设置 → 界面与显示 → 社区」里重新打开。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const FitText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const FitText('仍然关闭'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    widget.onToggleCommunity(false);
    setState(() {
      _enabled = false;
      _showUncommon = false;
    });
    _pop();
  }

  void _enableCommunity() {
    widget.onToggleCommunity(true);
    setState(() => _enabled = true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const FitText('社区设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: _pop,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSize.editorMaxWidth),
          child: ListView(
            padding: AppInsets.page,
            children: <Widget>[
              FitText(
                'DNAISLAND 是开源项目，默认使用官方服务器；也可以填写自建服务器的地址。',
                style: AppTextStyles.caption(
                  theme,
                ).copyWith(color: cs.onSurfaceVariant),
              ),
              AppSpacing.hLg,
              // 复用共享的地址表单：地址输入、使用官方服务器、检测按钮与结果
              // 横幅都和设置页/兜底页是同一份实现。
              ServerAddressForm(
                controller: _controller,
                defaultUrl: widget.defaultUrl,
                onUseDefault: _useOfficial,
                onSubmit: _check,
                checking: _checking,
                error: _error,
                validated: _validated,
                validatedMessage: '社区连接验证成功。',
                actionLabel: '保存并检测社区',
                onChanged: () => setState(() {
                  _validated = false;
                  _error = null;
                  _ignoreIssue = false;
                }),
              ),
              AppSpacing.hLg,
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showMore = !_showMore),
                  icon: Icon(
                    _showMore ? Icons.expand_less : Icons.expand_more,
                    size: AppSize.iconInline,
                  ),
                  label: const FitText('更多选项'),
                ),
              ),
              if (_showMore) ...<Widget>[
                AppSpacing.hXs,
                _MoreOptionTile(
                  icon: Icons.report_gmailerrorred_outlined,
                  title: '忽略这个错误',
                  subtitle: _error == null
                      ? '当前没有检测错误。'
                      : '地址先存下来，连接问题之后再说。',
                  enabled: _error != null,
                  onTap: _ignoreError,
                ),
                AppSpacing.hXs,
                _MoreOptionTile(
                  icon: Icons.more_horiz,
                  title: '不常用选项',
                  subtitle: '不打算用社区的人可以在这里关掉它。',
                  trailing: Icon(
                    _showUncommon ? Icons.expand_less : Icons.expand_more,
                    size: AppSize.iconInline,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: () =>
                      setState(() => _showUncommon = !_showUncommon),
                ),
                if (_showUncommon) ...<Widget>[
                  AppSpacing.hXs,
                  _MoreOptionTile(
                    icon: _enabled ? Icons.block_outlined : Icons.restore,
                    title: _enabled ? '不使用社区功能' : '重新启用社区功能',
                    subtitle: _enabled
                        ? '底栏与侧栏不再显示社区。'
                        : '把社区重新放回底栏与侧栏。',
                    onTap: _enabled ? _disableCommunity : _enableCommunity,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「更多选项」里的一行。
class _MoreOptionTile extends StatelessWidget {
  const _MoreOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Opacity(
      opacity: enabled ? 1 : AppAlpha.half,
      child: ListTile(
        enabled: enabled,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          icon,
          size: AppSize.iconCard,
          color: enabled ? cs.primary : cs.outline,
        ),
        title: FitText(title),
        subtitle: FitText(
          subtitle,
          style: AppTextStyles.caption(
            theme,
          ).copyWith(color: cs.onSurfaceVariant),
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
