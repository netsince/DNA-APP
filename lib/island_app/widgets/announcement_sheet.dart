import 'package:material_ui/material_ui.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';

/// 站点公告的底部弹层（可滚动长内容，底部「知道了」关闭）。
///
/// 两个入口共用：启动时由 `root_shell` 弹出、首页「查看公告」由 `home_body` 弹出。
/// 两处原本各写一份 —— root_shell 那份没有链接处理、也没有高度上限，home_body
/// 那份有。合成一份后差异用参数表达，**默认值等于 root_shell 原来的样子**，
/// 所以那边调用点一行不用改。
class AnnouncementSheet extends StatelessWidget {
  const AnnouncementSheet({
    super.key,
    required this.content,
    this.onOpen,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 16),
    this.maxHeightFraction,
  });

  final String content;

  /// 点链接的回调。为空时链接不可点（root_shell 启动弹窗就是这种情况）。
  final void Function(String url)? onOpen;

  final EdgeInsetsGeometry padding;

  /// 占屏高度上限（0~1）。为空时不限制 —— 与 root_shell 原实现一致。
  final double? maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.campaign_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '站点公告',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Html(
              data: content,
              onLinkTap: onOpen == null
                  ? null
                  : (String? href, Map<String, String> _, _) {
                      if (href != null) onOpen!(href);
                    },
              extensions: <HtmlExtension>[TableHtmlExtension()],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
    final double? maxH = maxHeightFraction;
    return SafeArea(
      child: maxH == null
          ? Padding(padding: padding, child: column)
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * maxH,
              ),
              child: Padding(padding: padding, child: column),
            ),
    );
  }
}
