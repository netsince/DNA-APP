/// 语音输入的文本累加状态机。
///
/// 从 [SpeechToTextService] 里拆出来，只因为它是最容易出错、又最容易被忽略的一段：
/// 识别器断句后要把当前句「提交」到已确认文本，[takeFinal] 才拿得到东西。
/// 漏掉提交这一步，整段实现看起来一切正常，但用户松手后一个字都发不出去 ——
/// 而且没有任何报错。这段逻辑没有任何平台依赖，因此单测能直接守住它。
class SttTranscript {
  String _committed = '';
  String _current = '';

  /// 已断句确认的文本。
  String get committed => _committed;

  /// 当前这句话的中间结果。
  String get current => _current;

  /// 给 UI 显示的内容：已确认 + 当前句。
  String get display => _committed + _current;

  /// 更新当前句（识别器每次 decode 后调用）。
  void updateCurrent(String text) {
    _current = text.trim();
  }

  /// 当前句与上次相同则返回 false，调用方据此跳过重复推送。
  bool updateCurrentIfChanged(String text) {
    final String next = text.trim();
    if (next.isEmpty || next == _current) {
      return false;
    }
    _current = next;
    return true;
  }

  /// 断句提交：把当前句并入已确认文本并清空当前句。
  void commitCurrent() {
    final String text = _current.trim();
    if (text.isNotEmpty) {
      _committed += text;
    }
    _current = '';
  }

  /// 取走整段结果并复位；用于录音结束。
  String takeFinal() {
    commitCurrent();
    final String text = _committed.trim();
    reset();
    return text;
  }

  void reset() {
    _committed = '';
    _current = '';
  }
}
