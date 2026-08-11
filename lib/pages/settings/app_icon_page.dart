import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/app_icon_service.dart';
import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';

/// 换图标页面：以大图预览展示所有可用图标，点击即可切换并立即应用。
class AppIconPage extends StatefulWidget {
  const AppIconPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconPageState extends State<AppIconPage> {
  late String _iconKey;

  /// 本平台是否支持运行时切换图标：Android（启动器）或 Web（浏览器标签页）。
  final bool _iconSupported = AppIconService.isSupported || kIsWeb;

  @override
  void initState() {
    super.initState();
    _iconKey = widget.controller.settings.appIcon;
  }

  Future<void> _selectIcon(AppIconOption opt) async {
    if (_iconKey == opt.key) return;
    setState(() => _iconKey = opt.key);
    await widget.controller.saveAppIcon(opt);
    if (!mounted) return;
    showSnack(
      context,
      kIsWeb ? '浏览器标签页图标已切换。' : '应用图标已切换，返回桌面即可看到效果。',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('换图标')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth > 900 ? 900 : constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                children: <Widget>[
                  if (!_iconSupported)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FitText(
                        '当前平台不支持切换图标，仅展示预览。',
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    )
                  else
                    FitText(
                      kIsWeb
                          ? '选择浏览器标签页上显示的图标，点击后立即应用。'
                          : '选择启动器上显示的图标，点击后立即应用。',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  const SizedBox(height: 16),
                  for (final opt in AppIconService.availableOptions) ...[
                    _IconCard(
                      option: opt,
                      selected: _iconKey == opt.key,
                      enabled: _iconSupported,
                      onTap: () => _selectIcon(opt),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 单个图标卡片：大图预览 + 名称 + 选中态。
class _IconCard extends StatelessWidget {
  const _IconCard({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppIconOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color borderColor = selected ? cs.primary : cs.outlineVariant;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            children: <Widget>[
              // 大图预览
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  option.assetPath,
                  width: 96,
                  height: 96,
                  errorBuilder: (_, _, _) => Container(
                    width: 96,
                    height: 96,
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(Icons.android, size: 48, color: cs.outline),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  FitText(
                    option.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: enabled ? null : cs.outline,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, size: 20, color: cs.primary),
                  ],
                ],
              ),
              if (!enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FitText(
                    '当前平台不支持切换',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
