class PagedList<T> {
  const PagedList({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  int get pageCount {
    if (pageSize <= 0) {
      return 1;
    }
    return (total + pageSize - 1) ~/ pageSize;
  }

  factory PagedList.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return PagedList(
      items: raw.map((item) => parse(Map<String, dynamic>.from(item as Map))).toList(),
      total: json['total'] as int? ?? raw.length,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? raw.length,
    );
  }
}
