import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/search_result.dart';
import '../models/ta.dart';
import '../models/world.dart';
import '../services/search_service.dart';
import '../state/app_controller.dart';
import '../widgets/app_container.dart';
import 'chat_page.dart';
import 'ta_editor_page.dart';
import 'world_editor_page.dart';
import 'package:dna/widgets/fit_text.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<SearchResult> _results = const <SearchResult>[];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = searchGlobal(
          query: value,
          tas: widget.controller.activeTas,
          worlds: widget.controller.activeWorlds,
          conversations: <Conversation>[
            ...widget.controller.activeConversations,
            ...widget.controller.activeGroupConversations,
          ],
        );
      });
    });
  }

  void _open(SearchResult result) {
    switch (result.kind) {
      case SearchResultKind.ta:
        final TA? ta = widget.controller.getTaById(result.taId!);
        if (ta == null) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                TaEditorPage(controller: widget.controller, ta: ta),
          ),
        );
      case SearchResultKind.world:
        final World? world = widget.controller.getWorldById(result.worldId);
        if (world == null) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                WorldEditorPage(controller: widget.controller, world: world),
          ),
        );
      case SearchResultKind.conversation:
      case SearchResultKind.message:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => ChatPage(
              controller: widget.controller,
              conversationId: result.conversationId!,
            ),
          ),
        );
    }
  }

  Widget _leading(SearchResultKind kind) {
    switch (kind) {
      case SearchResultKind.ta:
        return const CircleAvatar(child: Icon(Icons.person_outline));
      case SearchResultKind.world:
        return const CircleAvatar(child: Icon(Icons.public_outlined));
      case SearchResultKind.conversation:
        return const CircleAvatar(child: Icon(Icons.chat_bubble_outline));
      case SearchResultKind.message:
        return const CircleAvatar(child: Icon(Icons.format_quote_outlined));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<SearchResultKind, List<SearchResult>> grouped =
        <SearchResultKind, List<SearchResult>>{};
    for (final SearchResult r in _results) {
      grouped.putIfAbsent(r.kind, () => <SearchResult>[]).add(r);
    }
    final List<SearchResultKind> order = <SearchResultKind>[
      SearchResultKind.ta,
      SearchResultKind.world,
      SearchResultKind.conversation,
      SearchResultKind.message,
    ];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryController,
          focusNode: _focusNode,
          onChanged: _onQueryChanged,
          decoration: const InputDecoration(
            hintText: '搜索角色、世界、会话或消息',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
        ),
        actions: <Widget>[
          if (_queryController.text.isNotEmpty)
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _queryController.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
      body: _results.isEmpty
          ? Center(
              child: FitText(
                _queryController.text.isEmpty ? '输入关键词开始检索' : '没有匹配的结果',
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: order.length,
              itemBuilder: (BuildContext context, int sectionIndex) {
                final SearchResultKind kind = order[sectionIndex];
                final List<SearchResult>? items = grouped[kind];
                if (items == null || items.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _ResultSection(
                  kind: kind,
                  items: items,
                  onTap: _open,
                  leadingBuilder: _leading,
                  controller: widget.controller,
                );
              },
            ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.kind,
    required this.items,
    required this.onTap,
    required this.leadingBuilder,
    required this.controller,
  });

  final SearchResultKind kind;
  final List<SearchResult> items;
  final void Function(SearchResult) onTap;
  final Widget Function(SearchResultKind) leadingBuilder;
  final AppController controller;

  String get _title {
    switch (kind) {
      case SearchResultKind.ta:
        return '角色';
      case SearchResultKind.world:
        return '世界';
      case SearchResultKind.conversation:
        return '会话';
      case SearchResultKind.message:
        return '消息';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: FitText(
            '$_title（${items.length}）',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...items.map((SearchResult item) {
          // 四种结果 → 四种目标页:用带守卫的容器变换。
          // closed 侧 ListTile 保留原有 onTap 守卫(目标不存在则不开),
          // 校验通过后才调 open 起飞。
          return AppContainer<bool>(
            tappable: false,
            closedBuilder: (BuildContext context, VoidCallback open) =>
                ListTile(
                  leading: leadingBuilder(kind),
                  title: FitText(item.title),
                  subtitle: item.snippet != null
                      ? FitText(
                          item.snippet!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : FitText(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () {
                    // 守卫:目标不存在时不开飞行,退回原 push 逻辑给出反馈。
                    final bool exists = switch (item.kind) {
                      SearchResultKind.ta =>
                        controller.getTaById(item.taId ?? '') != null,
                      SearchResultKind.world =>
                        controller.getWorldById(item.worldId) != null,
                      SearchResultKind.conversation ||
                      SearchResultKind.message => item.conversationId != null,
                    };
                    if (!exists) {
                      onTap(item);
                      return;
                    }
                    open();
                  },
                ),
            openBuilder: (BuildContext context, VoidCallback close) {
              switch (item.kind) {
                case SearchResultKind.ta:
                  return TaEditorPage(
                    controller: controller,
                    ta: controller.getTaById(item.taId!)!,
                  );
                case SearchResultKind.world:
                  return WorldEditorPage(
                    controller: controller,
                    world: controller.getWorldById(item.worldId!)!,
                  );
                case SearchResultKind.conversation:
                case SearchResultKind.message:
                  return ChatPage(
                    controller: controller,
                    conversationId: item.conversationId!,
                  );
              }
            },
          );
        }),
        const Divider(),
      ],
    );
  }
}
