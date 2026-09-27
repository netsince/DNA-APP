// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'package:dna/theme/tokens.dart';
import 'package:dna/services/llm_provider.dart';
import 'package:dna/widgets/fit_text.dart';
import 'package:dna/widgets/setting_section.dart';

import 'widgets.dart';

/// 简易模式的连接面板:服务商 / 接口地址 / 密钥 / 连通性检测。
///
/// 全部输入仍是**普通输入框** —— 接口地址、密钥属于文本标识符,
/// 按规范不套折叠组件。
class AiConnectionSection extends StatefulWidget {
  const AiConnectionSection({
    super.key,
    required this.providers,
    required this.selectedProviderId,
    required this.fixedBaseUrl,
    required this.defaultBaseUrl,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.requiresApiKey,
    required this.checking,
    required this.statusMessage,
    required this.statusSuccess,
    required this.onProviderSelected,
    required this.onRestoreBaseUrl,
    required this.onCheck,
  });

  final List<LlmProvider> providers;
  final String selectedProviderId;
  final bool fixedBaseUrl;
  final String defaultBaseUrl;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final bool requiresApiKey;
  final bool checking;

  /// 上一次检测结果(为空表示尚未检测)。
  final String? statusMessage;

  /// [statusMessage] 是否为成功态。
  final bool statusSuccess;

  final ValueChanged<LlmProvider> onProviderSelected;
  final VoidCallback onRestoreBaseUrl;
  final VoidCallback onCheck;

  @override
  State<AiConnectionSection> createState() => _AiConnectionSectionState();
}

class _AiConnectionSectionState extends State<AiConnectionSection> {
  bool _showKey = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return SettingSection(
      icon: Icons.cable_outlined,
      title: '连接设置',
      description: '告诉应用该向哪个 AI 服务发消息。',
      children: <Widget>[
        AiChoiceGroup<LlmProvider>(
          options: widget.providers,
          selected: widget.providers.firstWhere(
            (LlmProvider p) => p.id == widget.selectedProviderId,
            orElse: () => widget.providers.first,
          ),
          labelOf: (LlmProvider p) => p.label,
          onSelected: widget.onProviderSelected,
        ),

        // 接口地址 —— 固定地址的服务商(FixedBaseUrl)不显示输入框。
        if (!widget.fixedBaseUrl) ...<Widget>[
          AppSpacing.hLg,
          TextField(
            controller: widget.baseUrlController,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '接口地址',
              hintText: widget.defaultBaseUrl,
              helperText: '留空则使用官方地址',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '恢复默认地址',
                icon: const Icon(Icons.restore),
                onPressed: widget.onRestoreBaseUrl,
              ),
            ),
          ),
        ],

        if (widget.requiresApiKey) ...<Widget>[
          AppSpacing.hLg,
          TextField(
            controller: widget.apiKeyController,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '密钥',
              helperText: '服务商提供的 Key，只保存在本机',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showKey ? '隐藏密钥' : '显示密钥',
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
          ),
        ],

        AppSpacing.hLg,
        OutlinedButton.icon(
          onPressed: widget.checking ? null : widget.onCheck,
          icon: widget.checking
              ? const SizedBox(
                  width: AppSize.iconInline,
                  height: AppSize.iconInline,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check),
          label: FitText(widget.checking ? '检测中…' : '检测连接'),
        ),

        if (widget.statusMessage != null)
          AiStatusRow(
            message: widget.statusMessage!,
            success: widget.statusSuccess,
          ),

        // 明文 HTTP 场景下的密钥安全提醒(原 `withTransportWarning` 文案太长,
        // 这里改为卡片内常驻一行提示)。
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: AiInlineNote(
            icon: Icons.lock_outline,
            iconColor: cs.outline,
            child: FitText(
              '密钥只保存在本机，不会随聊天内容发送。',
              style: AppTextStyles.caption(Theme.of(context))
                  .copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),

        AiGlossary(
          entries: const <String, String>{
            '服务商': '提供 AI 能力的公司或平台',
            '接口地址': '接收请求的网址，一般不用改',
            '密钥': '证明是你本人在使用的凭据',
          },
        ),
      ],
    );
  }
}
