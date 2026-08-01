import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/tts/tts_player.dart';
import '../services/tts/tts_service.dart';
import 'fit_text.dart';

/// 可复用的 seed 输入组件：输入框 + 「测试」按钮。
///
/// 点击「测试」会用当前 seed 合成并播放一段默认文本；合成期间按钮文字变为进度提示。
class SeedInputField extends StatefulWidget {
  const SeedInputField({
    super.key,
    required this.controller,
    this.label = 'Seed（可选）',
    this.hint,
    this.testText = '你好，我是你的数字伙伴，很高兴见到你。',
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String testText;

  /// 文本变化回调（供外部持久化 seed）。
  final ValueChanged<String>? onChanged;

  @override
  State<SeedInputField> createState() => _SeedInputFieldState();
}

class _SeedInputFieldState extends State<SeedInputField> {
  String _status = ''; // '' 正常；非空时按钮显示此进度文本
  bool _busy = false;

  int? get _seed {
    final String raw = widget.controller.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> _test() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '0%';
    });
    // 让进度先渲染一帧（引擎同步推理会阻塞 UI）
    await Future<void>.delayed(const Duration(milliseconds: 60));
    try {
      final Float32List wav = await TtsService.instance.synthesize(
        widget.testText,
        globalSeed: _seed,
        onProgress: (double p) {
          if (!mounted) return;
          setState(() {
            _status = '${(p * 100).round()}%';
          });
        },
      );
      if (!mounted) return;
      setState(() => _status = '播放中…');
      await TtsPlayer.instance.play(wav);
      if (!mounted) return;
      setState(() {
        _status = '';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '';
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: FitText('合成失败：$e')),
      );
    }
  }

  /// 填入随机 seed 并触发 [onChanged]。
  void _randomize() {
    final int seed = math.Random().nextInt(0x7fffffff);
    widget.controller.text = '$seed';
    // 光标移到末尾
    widget.controller.selection =
        TextSelection.collapsed(offset: widget.controller.text.length);
    widget.onChanged?.call('$seed');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: IconButton.outlined(
            onPressed: _busy ? null : _randomize,
            tooltip: '随机 seed',
            icon: const Icon(Icons.casino_outlined),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: _busy ? null : _test,
            style: OutlinedButton.styleFrom(
              foregroundColor: _busy ? cs.primary : null,
            ),
            child: FitText(_busy ? _status : '测试'),
          ),
        ),
      ],
    );
  }
}
