import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/card_publish_page.dart';

/// 发布角色卡第一步：选择入口（对齐网页版 `/publish/start`）。
///
/// 三个入口：
/// - 直接填写 → 进入空表单编辑页；
/// - 从 JSON 识别 → 粘贴 JSON 解析后预填；
/// - 从剪贴板识别 → 读剪贴板 JSON 解析后预填。
/// 识别/填写都进入第二步的 [CardPublishPage]，其本身不展示 JSON 输入框。
class CardPublishStartPage extends StatelessWidget {
  const CardPublishStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布角色卡'), centerTitle: true),
      body: const CardPublishStartBody(),
    );
  }
}

/// 发布入口的纯内容体（无自己的 Scaffold/AppBar）。
///
/// 既被 [CardPublishStartPage]（独立 push）复用，也被底部「上传」常驻 tab
/// 直接嵌入 RootShell 的 Scaffold 中（避免嵌套两层 AppBar）。
class CardPublishStartBody extends StatefulWidget {
  const CardPublishStartBody({super.key});

  @override
  State<CardPublishStartBody> createState() => _CardPublishStartBodyState();
}

class _CardPublishStartBodyState extends State<CardPublishStartBody> {
  final TextEditingController _jsonController = TextEditingController();
  bool _showJson = false;
  bool _busy = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openForm([Map<String, dynamic>? prefill]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardPublishPage(prefill: prefill),
      ),
    );
  }

  Future<void> _importFromJson() async {
    final raw = _jsonController.text.trim();
    if (raw.isEmpty) {
      _snack('请先粘贴角色卡 JSON');
      return;
    }
    setState(() => _busy = true);
    try {
      final parsed = await ApiClient.instance.parseCardImport(raw);
      if (!mounted) return;
      _openForm(parsed);
    } catch (e) {
      if (!mounted) return;
      _snack('解析失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromClipboard() async {
    setState(() => _busy = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final raw = (data?.text ?? '').trim();
      if (raw.isEmpty) {
        _snack('剪贴板没有可识别的 JSON');
        return;
      }
      final parsed = await ApiClient.instance.parseCardImport(raw);
      if (!mounted) return;
      _openForm(parsed);
    } catch (e) {
      if (!mounted) return;
      _snack('剪贴板内容不是有效的角色卡 JSON');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 12),
        const Text(
          '发布角色卡',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        _bigButton(
          label: '从剪贴板识别',
          filled: true,
          icon: Icons.content_paste_go_outlined,
          onTap: _busy ? null : _importFromClipboard,
        ),
        const SizedBox(height: 12),
        _bigButton(
          label: '从 JSON 识别',
          filled: false,
          icon: Icons.data_object_outlined,
          onTap: () => setState(() => _showJson = !_showJson),
        ),
        const SizedBox(height: 12),
        _bigButton(
          label: '直接开始编辑',
          filled: false,
          outlined: true,
          icon: Icons.edit_note_outlined,
          onTap: _busy ? null : () => _openForm(),
        ),
        if (_showJson) ...<Widget>[
          const SizedBox(height: 20),
          TextField(
            controller: _jsonController,
            maxLines: 10,
            minLines: 6,
            decoration: const InputDecoration(
              hintText: '在此粘贴从 DNA 客户端导出的角色卡 JSON…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _importFromJson,
            icon: const Icon(Icons.play_arrow),
            label: Text(_busy ? '识别中…' : '识别并继续'),
          ),
        ],
      ],
    );
  }

  Widget _bigButton({
    required String label,
    required VoidCallback? onTap,
    bool filled = false,
    bool outlined = false,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    if (filled) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (outlined) {
      bg = Colors.transparent;
      fg = scheme.primary;
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurface;
    }
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: outlined ? BorderSide(color: scheme.primary) : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
