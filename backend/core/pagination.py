def page_bounds(page: int | None, page_size: int | None, *, default_size: int = 10, max_size: int = 100) -> tuple[int, int]:
    safe_page = page if page is not None and page > 0 else 1
    raw_size = page_size if page_size is not None and page_size > 0 else default_size
    safe_size = min(raw_size, max_size)
    return safe_page, safe_size


def slice_page(items: list, page: int, page_size: int) -> tuple[list, int]:
    total = len(items)
    start = (page - 1) * page_size
    end = start + page_size
    return items[start:end], total
