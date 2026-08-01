import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.enabled = true,
    this.maxValue,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String testText;

  /// 文本变化回调（供外部持久化 seed）。
  final ValueChanged<String>? onChanged;

  /// 是否允许编辑。为 false 时输入框锁定、随机按钮禁用（测试仍可用）。
  final bool enabled;

  /// 允许的最大 seed 值（含）。超出会被钳制到该值。
  final int? maxValue;

  @override
  State<SeedInputField> createState() => _SeedInputFieldState();
}

class _SeedInputFieldState extends State<SeedInputField> {
  String _status = ''; // '' 正常；非空时按钮显示此进度文本
  bool _busy = false;
  bool _adjusting = false; // 防止 clamp 回写时递归触发 onChanged

  int? get _seed {
    final String raw = widget.controller.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  /// 处理输入变化：若超过 [widget.maxValue] 则钳制到最大值。
  void _onChanged(String raw) {
    if (_adjusting) return;
    final int? max = widget.maxValue;
    if (max != null) {
      final int? v = int.tryParse(raw.trim());
      if (v != null && v > max) {
        _adjusting = true;
        widget.controller.text = '$max';
        widget.controller.selection =
            TextSelection.collapsed(offset: widget.controller.text.length);
        _adjusting = false;
        widget.onChanged?.call('$max');
        return;
      }
    }
    widget.onChanged?.call(raw);
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
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              if (widget.maxValue != null)
                LengthLimitingTextInputFormatter(
                  widget.maxValue!.toString().length,
                ),
            ],
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: IconButton.outlined(
            onPressed: widget.enabled && !_busy ? _randomize : null,
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
