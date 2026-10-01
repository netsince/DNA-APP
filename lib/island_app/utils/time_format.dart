/// 相对时间：几秒/分钟/小时/天前，超过 30 天显示日期。
String formatRelativeTime(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  final m = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  return '${t.year}-$m-$d';
}

/// 绝对时间：YYYY-MM-DD HH:MM，解析失败返回空串。
String formatDateTime(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final m = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  final h = t.hour.toString().padLeft(2, '0');
  final min = t.minute.toString().padLeft(2, '0');
  return '${t.year}-$m-$d $h:$min';
}
