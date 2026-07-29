import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../utils/ui_feedback.dart';
import 'package:dna/widgets/fit_text.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  late final TextEditingController _cmdCtrl;
  static const _clearCmd = 'CLEAR ALL DATAS YES I DO THIS PLEASE DEL MY DATAS THANK YOU 114514';

  @override
  void initState() { super.initState(); _cmdCtrl = TextEditingController(); }

  @override
  void dispose() { _cmdCtrl.dispose(); super.dispose(); }

  Future<void> _run() async {
    final cmd = _cmdCtrl.text;
    if (cmd == _clearCmd) {
      await widget.controller.clearAllData();
      if (!mounted) return;
      _cmdCtrl.clear();
      showSnack(context, '数据已清除。');
      return;
    }
    showSnack(context, '未知指令或指令不匹配。');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const FitText('高级')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    FitText('危险操作', style: TextStyle(fontWeight: FontWeight.w600, color: cs.error, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                FitText('输入命令并执行。命令大小写敏感。请确保您清楚自己在做什么。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                TextField(
                  controller: _cmdCtrl,
                  decoration: const InputDecoration(labelText: '输入命令', isDense: true),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _run,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                    child: const FitText('执行命令'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
