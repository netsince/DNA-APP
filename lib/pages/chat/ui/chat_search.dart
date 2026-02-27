part of '../../chat_page.dart';

mixin ChatSearchHelpers on ChatStateMixin {
  void _toggleSearch() {
    final bool next = !_searching;
    setState(() {
      _searching = next;
      if (!next) {
        _searchController.clear();
        _searchMatchIndex = -1;
      }
    });
    if (next) {
      _updateSearch(_searchController.text);
    }
  }

  void _updateSearch(String raw) {
    final String query = raw.trim();
    final List<int> matches = _computeSearchMatches(query);
    if (query.isEmpty) {
      setState(() => _searchMatchIndex = -1);
      return;
    }
    setState(() {
      _searchMatchIndex = matches.isEmpty ? -1 : 0;
    });
    if (_searchMatchIndex >= 0) {
      _jumpToMessageIndex(matches[_searchMatchIndex]);
    }
  }

  List<int> _computeSearchMatches(String query) {
    return _chatController.computeSearchMatches(_conversation, query);
  }

  void _navigateMatch(int delta) {
    final String query = _searchController.text.trim();
    final List<int> matches = _computeSearchMatches(query);
    if (matches.isEmpty) {
      setState(() => _searchMatchIndex = -1);
      return;
    }
    final int nextIndex = _searchMatchIndex < 0
        ? 0
        : (((_searchMatchIndex + delta) % matches.length) + matches.length) % matches.length;
    setState(() => _searchMatchIndex = nextIndex);
    _jumpToMessageIndex(matches[nextIndex]);
  }

  void _jumpToMessageIndex(int messageIndex) {
    _chatController.jumpToMessageIndex(
      conversation: _conversation,
      messageKeys: _messageKeys,
      messageIndex: messageIndex,
    );
  }
}
