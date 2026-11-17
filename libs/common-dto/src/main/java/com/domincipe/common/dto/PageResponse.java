package com.domincipe.common.dto;

import java.util.List;
import java.util.Objects;

/**
 * One page of results of a collection endpoint.
 *
 * <p>Every service returns the same envelope, so a client can paginate without knowing which
 * service answered. The record is immutable: the canonical constructor copies {@code content},
 * so mutating the source list after publication cannot change the page.
 *
 * <p>{@link #of(List, int, int, long)} is the intended entry point because it derives
 * {@code totalPages} from the data; the canonical constructor still rejects a page whose count
 * disagrees with {@code totalElements} and {@code size}, so an inconsistent envelope cannot
 * reach the client.
 *
 * @param content items of the current page, never {@code null} and with no {@code null} items
 * @param page zero-based index of the current page
 * @param size maximum number of items per page, always positive
 * @param totalElements total number of items across all pages
 * @param totalPages total number of pages, must equal {@code ceil(totalElements / size)}
 * @param <T> item type
 */
public record PageResponse<T>(
        List<T> content,
        int page,
        int size,
        long totalElements,
        int totalPages) {

    /**
     * Copies the content and validates the values from which the envelope is interpreted.
     */
    public PageResponse {
        content = List.copyOf(Objects.requireNonNull(content, "content must not be null"));
        if (page < 0) {
            throw new IllegalArgumentException("page must not be negative");
        }
        int expectedTotalPages = deriveTotalPages(totalElements, size);
        if (totalPages != expectedTotalPages) {
            throw new IllegalArgumentException("totalPages must equal ceil(totalElements / size)");
        }
    }

    /**
     * Builds a page whose {@code totalPages} is derived from the data.
     *
     * @param content items of the current page
     * @param page zero-based index of the current page
     * @param size maximum number of items per page
     * @param totalElements total number of items across all pages
     * @param <T> item type
     * @return a consistent page envelope
     */
    public static <T> PageResponse<T> of(final List<T> content, final int page, final int size,
            final long totalElements) {
        return new PageResponse<>(content, page, size, totalElements, deriveTotalPages(totalElements, size));
    }

    /**
     * Computes the page count after rejecting the values that make the division meaningless.
     *
     * @param totalElements total number of items across all pages
     * @param size maximum number of items per page
     * @return {@code ceil(totalElements / size)}, never negative
     */
    private static int deriveTotalPages(final long totalElements, final int size) {
        if (size < 1) {
            throw new IllegalArgumentException("size must be positive");
        }
        if (totalElements < 0) {
            throw new IllegalArgumentException("totalElements must not be negative");
        }
        return (int) Math.ceilDiv(totalElements, size);
    }
}
