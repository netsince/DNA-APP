import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/server_config.dart';
import 'package:dna/island_app/utils/external_link.dart';
import 'package:dna/island_app/widgets/fade_in_image.dart';

/// 表情包目录：内存缓存 `code → image_url`，从 `/stickers/api` 加载一次。
class StickerCatalog {
  StickerCatalog._();

  static final StickerCatalog instance = StickerCatalog._();

  final Map<String, String> _byCode = <String, String>{};
  final List<Map<String, dynamic>> _series = <Map<String, dynamic>>[];
  bool _loaded = false;
  Future<void>? _loading;

  /// 是否已加载到表情包。
  bool get loaded => _loaded;

  /// 加载（幂等）：同一时刻只发一次请求。
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _doLoad();
  }

  Future<void> _doLoad() async {
    try {
      final series = await ApiClient.instance.getStickers();
      _series
        ..clear()
        ..addAll(series);
      _byCode.clear();
      for (final s in series) {
        final stickers = s['stickers'];
        if (stickers is List) {
          for (final st in stickers) {
            if (st is Map) {
              final code = (st['code'] ?? '').toString();
              final url = (st['image_url'] ?? '').toString();
              if (code.isNotEmpty && url.isNotEmpty) _byCode[code] = url;
            }
          }
        }
      }
      _loaded = true;
    } catch (_) {
      // 加载失败不抛给 UI，渲染时按纯文本回退。
    }
  }

  /// 按 code 取表情图 URL（未加载/不存在返回 null）。
  String? urlFor(String code) => _byCode[code];

  /// 仅供测试：直接注入表情目录数据（code → image_url）。
  @visibleForTesting
  void debugSeed(Map<String, String> data) {
    _byCode
      ..clear()
      ..addAll(data);
    _loaded = true;
  }

  /// 仅供测试：清空目录。
  @visibleForTesting
  void debugClear() {
    _byCode.clear();
    _series.clear();
    _loaded = false;
    _loading = null;
  }

  /// 从文本中提取所有 `[sticker:CODE]` 的 code 列表。
  static List<String> extractCodes(String text) {
    final codes = <String>[];
    final re = RegExp(r'\[sticker:([A-Za-z0-9_\u4e00-\u9fff-]+)\]');
    for (final m in re.allMatches(text)) {
      codes.add(m.group(1)!);
    }
    return codes;
  }
}

/// 把正文里的 `[sticker:CODE]` 替换为内联表情图片。
///
/// 若目录尚未加载完成或找不到该表情，则按纯文本回退显示原标记。
/// [size] 为表情图片的宽高（默认 32）。
class StickerText extends StatelessWidget {
  const StickerText(this.text, {super.key, this.size = 32, this.style, this.maxLines, this.overflow});

  final String text;
  final double size;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final tokens = _split(text);
    final parts0 = tokens.length == 1 ? _urlSplit(tokens.first.text) : null;
    final hasUrl = parts0 == null
        ? true
        : parts0.any((p) => p.url != null);
    if (tokens.length == 1 && !hasUrl) {
      // 无表情、无链接，直接返回文本（保留原样式与截断）。
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    return RichText(
      text: TextSpan(
        children: tokens.expand<InlineSpan>((t) {
          if (t.stickerCode != null) {
            final url = StickerCatalog.instance.urlFor(t.stickerCode!);
            if (url != null) {
              return <InlineSpan>[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: FadeInNetworkImage(
                        url: ServerConfig.resolveUrl(url),
                        fit: BoxFit.contain,
                        placeholder: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ];
            }
            // 目录未加载/无此码：按纯文本（含链接识别）回退显示原标记。
          }
          return _buildTextSpans(context, t.text);
        }).toList(),
      ),
    );
  }

  /// 把纯文本片段拆成「普通文本 + 可点击链接」，链接点击前先弹外链确认。
  List<InlineSpan> _buildTextSpans(BuildContext context, String segment) {
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    final parts = _urlSplit(segment);
    return parts.map<InlineSpan>((p) {
      if (p.url != null) {
        return TextSpan(
          text: p.url,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => confirmOpenBrowser(context, p.url!),
        );
      }
      return TextSpan(text: p.text, style: style);
    }).toList();
  }

  /// 把一段文本按其中的 URL 拆成若干子段（普通文本 / URL）。
  static List<_Part> _urlSplit(String segment) {
    final parts = <_Part>[];
    final re = RegExp(r'https?://[^\s<]+');
    var last = 0;
    for (final m in re.allMatches(segment)) {
      if (m.start > last) parts.add(_Part(segment.substring(last, m.start)));
      parts.add(_Part(null, url: m.group(0)!));
      last = m.end;
    }
    if (last < segment.length) parts.add(_Part(segment.substring(last)));
    if (parts.isEmpty) parts.add(_Part(segment));
    return parts;
  }

  static List<_Token> _split(String text) {
    final tokens = <_Token>[];
    final re = RegExp(r'\[sticker:([A-Za-z0-9_\u4e00-\u9fff-]+)\]');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        tokens.add(_Token(text.substring(last, m.start)));
      }
      tokens.add(_Token(m.group(0)!, stickerCode: m.group(1)));
      last = m.end;
    }
    if (last < text.length) {
      tokens.add(_Token(text.substring(last)));
    }
    if (tokens.isEmpty) tokens.add(_Token(text));
    return tokens;
  }
}

class _Token {
  const _Token(this.text, {this.stickerCode});
  final String text;
  final String? stickerCode;
}

class _Part {
  const _Part(this.text, {this.url});
  final String? text;
  final String? url;
}

/// 表情包选择底部弹层：按系列分组，点击表情把 `[sticker:CODE]` 标记交还给调用方。
///
/// 返回 `[sticker:CODE]` 字符串；用户取消返回 null。
Future<String?> showStickerPicker(BuildContext context) async {
  final catalog = StickerCatalog.instance;
  await catalog.ensureLoaded();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _StickerSheet(),
  );
}

class _StickerSheet extends StatefulWidget {
  const _StickerSheet();

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late List<Map<String, dynamic>> _series;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _series = List<Map<String, dynamic>>.from(StickerCatalog.instance._series);
    _tab = TabController(length: _series.isEmpty ? 1 : _series.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await StickerCatalog.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _series = List<Map<String, dynamic>>.from(StickerCatalog.instance._series);
      _loaded = true;
      if (_series.isNotEmpty && _tab.length != _series.length) {
        _tab.dispose();
        _tab = TabController(length: _series.length, vsync: this);
      }
    });
  }

  void _pick(String code) {
    Navigator.of(context).pop('[sticker:$code]');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.6;
    return SizedBox(
      height: height,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                Text('表情包',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (!_loaded)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_series.isEmpty)
            const Expanded(
              child: Center(child: Text('暂无可用的表情包')),
            )
          else ...<Widget>[
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: scheme.primary,
              tabs: _series
                  .map((s) => Tab(
                        text: (s['name'] ?? '').toString(),
                      ))
                  .toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: _series.map((s) => _StickerGrid(series: s)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({required this.series});

  final Map<String, dynamic> series;

  @override
  Widget build(BuildContext context) {
    final stickers = series['stickers'];
    final list = stickers is List
        ? stickers.whereType<Map>().toList()
        : <Map<String, dynamic>>[];
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 72,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final st = list[i];
        final code = (st['code'] ?? '').toString();
        final url = (st['image_url'] ?? '').toString();
        return InkWell(
          onTap: () => context.findAncestorStateOfType<_StickerSheetState>()!
              ._pick(code),
          borderRadius: BorderRadius.circular(8),
          child: FadeInNetworkImage(
            url: ServerConfig.resolveUrl(url),
            fit: BoxFit.contain,
            placeholder: const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
