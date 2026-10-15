import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/llm_provider.dart';
import '../theme/tokens.dart';
import '../utils/base_url_guard.dart';
import 'brand_icon.dart';
import 'config_status_banner.dart';
import 'fit_text.dart';

/// 服务商选择 + 连接参数输入的通用表单。
///
/// OOBE 的「API 配置」步骤与设置页「AI 服务（精简模式）」共用本组件，差异全部
/// 由参数表达：
/// * [providerLabel] 为空时不渲染「服务商」小标题（外层已有分组标题）；
/// * [onRestoreDefault] 非空时才在 Base URL 右侧挂「恢复默认地址」；
/// * [onCheck] 为空时不渲染检测按钮；
/// * [onIgnoreChanged] 非空时，检测失败才出现「忽略此问题」；
/// * [requiresApiKey] 为 false 时（本地推理等）不渲染 API Key 输入框，也不再
///   要求填 Key —— 这是 LlmProvider 接口早就声明、但一直没被接上的能力。
///
/// 组件只做输入与展示，**不持有业务状态**：控制器、检测结果与回调都由调用方
/// 传入。内部只保留纯 UI 状态（Key 的明文开关、剪贴板提示、Base URL 的格式错误）。
class ProviderConfigForm extends StatefulWidget {
  const ProviderConfigForm({
    super.key,
    required this.providers,
    required this.selectedProviderId,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.defaultBaseUrl,
    required this.onProviderChanged,
    required this.onInputChanged,
    this.hideBaseUrl = false,
    this.requiresApiKey = true,
    this.providerLabel,
    this.showProviderIcons = true,
    this.onRestoreDefault,
    this.checking = false,
    this.checkLabel = '检测连接',
    this.checkingLabel = '检测中...',
    this.checkIcon = Icons.verified_outlined,
    this.onCheck,
    this.onSubmitApiKey,
    this.validated = false,
    this.validatedMessage = '连接验证成功。',
    this.error,
    this.ignoreIssue = false,
    this.onIgnoreChanged,
    this.ignoreHint = '勾选后允许跳过本次检测并继续。',
  });

  final List<LlmProvider> providers;
  final String selectedProviderId;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final String defaultBaseUrl;
  final ValueChanged<LlmProvider> onProviderChanged;
  final VoidCallback onInputChanged;

  /// 当前服务商锁定了地址 —— 隐藏 Base URL 输入框。
  final bool hideBaseUrl;

  /// 当前服务商是否需要 API Key。
  final bool requiresApiKey;

  final String? providerLabel;
  final bool showProviderIcons;
  final VoidCallback? onRestoreDefault;
  final bool checking;
  final String checkLabel;
  final String checkingLabel;
  final IconData checkIcon;
  final VoidCallback? onCheck;

  /// 在 API Key 输入框里按回车时触发（一般是「保存并检测」）。
  final VoidCallback? onSubmitApiKey;

  final bool validated;
  final String validatedMessage;
  final String? error;
  final bool ignoreIssue;
  final ValueChanged<bool>? onIgnoreChanged;
  final String ignoreHint;

  @override
  State<ProviderConfigForm> createState() => _ProviderConfigFormState();
}

class _ProviderConfigFormState extends State<ProviderConfigForm> {
  final FocusNode _baseUrlFocus = FocusNode();

  /// Base URL 的格式错误（失焦时才提示，避免边打字边报红）。
  String? _baseUrlFormatError;

  bool _obscureApiKey = true;

  /// 剪贴板里那段「看起来像 Key」的文本；为空表示不提示。
  String? _clipboardKey;

  @override
  void initState() {
    super.initState();
    _baseUrlFocus.addListener(_onBaseUrlFocusChanged);
    _probeClipboard();
  }

  @override
  void dispose() {
    _baseUrlFocus
      ..removeListener(_onBaseUrlFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onBaseUrlFocusChanged() {
    if (_baseUrlFocus.hasFocus) return;
    final String? formatError =
        baseUrlFormatError(widget.baseUrlController.text);
    if (formatError != _baseUrlFormatError) {
      setState(() => _baseUrlFormatError = formatError);
    }
  }

  /// 探一次剪贴板：里面如果是「够长、单行、无空格」的一段文本，就当成 Key 候选
  /// 提示用户粘贴。读剪贴板在部分平台需要权限、测试环境也没有实现，所以整段
  /// 吞掉异常，失败就当没有。
  Future<void> _probeClipboard() async {
    if (!widget.requiresApiKey) return;
    try {
      final ClipboardData? data =
          await Clipboard.getData(Clipboard.kTextPlain);
      final String text = (data?.text ?? '').trim();
      if (!mounted || text.isEmpty) return;
      if (text.length >= 20 && !text.contains(RegExp(r'\s'))) {
        setState(() => _clipboardKey = text);
      }
    } catch (_) {
      // 忽略：拿不到剪贴板只是少一个便利提示。
    }
  }

  void _pasteClipboardKey() {
    final String? text = _clipboardKey;
    if (text == null) return;
    widget.apiKeyController.text = text;
    setState(() => _clipboardKey = null);
    widget.onInputChanged();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.providerLabel != null) ...<Widget>[
          FitText(widget.providerLabel!, style: AppTextStyles.sectionTitle(theme)),
          AppSpacing.hSm,
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: widget.providers.map((LlmProvider p) {
            return ChoiceChip(
              // 用真实厂商标：一排 Chip 里最先被扫到的就是图形，通用机器人
              // 图标认不出是哪一家。18 是 M3 Chip avatar 的常规尺寸，品牌图形
              // 比 Material 字形密，16 会糊。
              avatar: widget.showProviderIcons ? BrandIcon(id: p.id) : null,
              showCheckmark: false,
              label: FitText(p.label),
              selected: p.id == widget.selectedProviderId,
              onSelected: (_) => widget.onProviderChanged(p),
            );
          }).toList(),
        ),
        AppSpacing.hLg,
        const Divider(),
        AppSpacing.hLg,
        if (!widget.hideBaseUrl) ...<Widget>[
          TextField(
            controller: widget.baseUrlController,
            focusNode: _baseUrlFocus,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: widget.defaultBaseUrl,
              prefixIcon: const Icon(Icons.link),
              errorText: _baseUrlFormatError,
              suffixIcon: widget.onRestoreDefault == null
                  ? null
                  : IconButton(
                      tooltip: '恢复默认地址',
                      icon: const Icon(Icons.restore),
                      onPressed: widget.onRestoreDefault,
                    ),
            ),
            onChanged: (_) {
              // 一边改一边清掉上一次的格式报错，别让用户对着红字打字。
              if (_baseUrlFormatError != null) {
                setState(() => _baseUrlFormatError = null);
              }
              widget.onInputChanged();
            },
          ),
          AppSpacing.hMd,
        ],
        if (!widget.requiresApiKey)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FitText(
              '这个服务商不需要 API Key。',
              style: AppTextStyles.caption(theme)
                  .copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else ...<Widget>[
          TextField(
            controller: widget.apiKeyController,
            obscureText: _obscureApiKey,
            // 关掉自动更正与联想：Key 是一串无意义字符，被键盘「纠正」过就废了。
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureApiKey ? '显示' : '隐藏',
                icon: Icon(
                  _obscureApiKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
            onChanged: (_) {
              if (_clipboardKey != null) {
                setState(() => _clipboardKey = null);
              }
              widget.onInputChanged();
            },
            onSubmitted: (_) => widget.onSubmitApiKey?.call(),
          ),
          if (_clipboardKey != null &&
              widget.apiKeyController.text.trim().isEmpty) ...<Widget>[
            AppSpacing.hSm,
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pasteClipboardKey,
                icon: const Icon(Icons.content_paste, size: AppSize.iconInline),
                label: const FitText('粘贴剪贴板里的内容'),
              ),
            ),
          ],
        ],
        if (widget.onCheck != null) ...<Widget>[
          AppSpacing.hLg,
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: widget.checking ? null : widget.onCheck,
              icon: widget.checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.checkIcon),
              label: FitText(
                widget.checking ? widget.checkingLabel : widget.checkLabel,
              ),
            ),
          ),
        ],
        if (widget.validated) ...<Widget>[
          AppSpacing.hMd,
          ConfigStatusBanner(message: widget.validatedMessage),
        ],
        if (widget.error != null) ...<Widget>[
          AppSpacing.hMd,
          ConfigStatusBanner(message: widget.error!, isError: true),
          if (widget.onIgnoreChanged != null)
            CheckboxListTile(
              value: widget.ignoreIssue,
              title: const FitText('忽略此问题'),
              subtitle: FitText(widget.ignoreHint),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              onChanged: (bool? value) =>
                  widget.onIgnoreChanged!(value ?? false),
            ),
        ],
      ],
    );
  }
}
