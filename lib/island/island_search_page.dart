import 'package:flutter/material.dart';

import 'package:dna/state/app_controller.dart';
import 'package:dna/theme/tokens.dart';
import 'package:dna/widgets/fit_text.dart';

import 'island_api.dart';
import 'island_feed.dart';

/// 岛的角色卡搜索页：一个输入框 + 复用信息流。
class IslandSearchPage extends StatefulWidget {
  const IslandSearchPage({
    super.key,
    required this.controller,
    this.api,
    this.completer,
  });

  final AppController controller;
  final IslandApi? api;
  final Future<String> Function(List<Map<String, String>>)? completer;

  @override
  State<IslandSearchPage> createState() => _IslandSearchPageState();
}

class _IslandSearchPageState extends State<IslandSearchPage> {
  final TextEditingController _input = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() => _query = query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: const InputDecoration(
            hintText: '搜索角色卡…',
            border: InputBorder.none,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '搜索',
            onPressed: () => _submit(_input.text),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: _query.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: FitText(
                  '输入关键词，搜岛上的角色卡。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            )
          : IslandFeedBody(
              // 换关键词就换一整个信息流：用 key 让状态干净重来。
              key: ValueKey<String>(_query),
              controller: widget.controller,
              api: widget.api,
              query: _query,
              completer: widget.completer,
            ),
    );
  }
}
