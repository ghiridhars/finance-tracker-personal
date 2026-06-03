from app.parsers.base_parser import ParseResult


def result_transaction_count(result: ParseResult | None) -> int:
    if result is None or not result.success or result.result is None:
        return 0
    return len(getattr(result.result, "transactions", []))


def select_best_result(results: list[ParseResult]) -> ParseResult | None:
    best_result: ParseResult | None = None
    best_count = -1

    for result in results:
        count = result_transaction_count(result)
        if count > best_count:
            best_result = result
            best_count = count

    return best_result