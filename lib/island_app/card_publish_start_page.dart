import 'package:flutter/material.dart';

import 'package:dna/island_app/card_publish_page.dart';
import 'package:dna/island_app/card_publish_source.dart';

/// 发布角色卡：页面形态（从「我的角色卡」空态等处 push 进来）。
class CardPublishStartPage extends StatelessWidget {
  const CardPublishStartPage({super.key, this.source, this.publisher});

  final CardPublishSource? source;
  final Future<void> Function(Map<String, dynamic> payload)? publisher;

  @override
  Widget build(BuildContext context) {
    return CardPublishPage(source: source, publisher: publisher);
  }
}

/// 发布入口的纯内容体（无自己的 Scaffold/AppBar）。
///
/// 既被 [CardPublishStartPage] 复用，也被底栏「＋ → 发布角色卡」那一页直接嵌入
/// RootShell 的 Scaffold 中（避免嵌套两层 AppBar）。
class CardPublishStartBody extends StatelessWidget {
  const CardPublishStartBody({super.key, this.source, this.publisher});

  final CardPublishSource? source;
  final Future<void> Function(Map<String, dynamic> payload)? publisher;

  @override
  Widget build(BuildContext context) {
    return CardPublishBody(source: source, publisher: publisher);
  }
}
