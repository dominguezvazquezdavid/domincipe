package com.domincipe.common.dto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class PageResponseTest {

    @Test
    void derivesTotalPagesRoundingUp() {
        PageResponse<String> page = PageResponse.of(List.of("a", "b", "c"), 0, 2, 5);

        assertThat(page.content()).containsExactly("a", "b", "c");
        assertThat(page.page()).isZero();
        assertThat(page.size()).isEqualTo(2);
        assertThat(page.totalElements()).isEqualTo(5);
        assertThat(page.totalPages()).isEqualTo(3);
    }

    @Test
    void derivesTotalPagesWhenTheDivisionIsExact() {
        PageResponse<String> page = PageResponse.of(List.of("a", "b", "c"), 0, 3, 9);

        assertThat(page.totalPages()).isEqualTo(3);
    }

    @Test
    void derivesZeroPagesWhenThereAreNoElements() {
        PageResponse<String> page = PageResponse.of(List.of(), 0, 20, 0);

        assertThat(page.content()).isEmpty();
        assertThat(page.totalPages()).isZero();
    }

    @Test
    void acceptsAPageThatMatchesTheDerivedTotal() {
        PageResponse<String> page = new PageResponse<>(List.of("a"), 1, 10, 11, 2);

        assertThat(page.page()).isEqualTo(1);
        assertThat(page.totalPages()).isEqualTo(2);
    }

    @Test
    void copiesTheContentSoLaterChangesToTheSourceDoNotLeakIn() {
        List<String> source = new ArrayList<>(List.of("a"));

        PageResponse<String> page = PageResponse.of(source, 0, 10, 1);
        source.add("b");

        assertThat(page.content()).containsExactly("a");
    }

    @Test
    void exposesAnUnmodifiableContentList() {
        PageResponse<String> page = PageResponse.of(new ArrayList<>(List.of("a")), 0, 10, 1);

        assertThatExceptionOfType(UnsupportedOperationException.class)
                .isThrownBy(() -> page.content().add("b"));
    }

    @Test
    void rejectsMissingContent() {
        assertThatNullPointerException()
                .isThrownBy(() -> PageResponse.of(null, 0, 10, 0))
                .withMessage("content must not be null");
    }

    @Test
    void rejectsNullItems() {
        List<String> content = new ArrayList<>();
        content.add(null);

        assertThatNullPointerException()
                .isThrownBy(() -> PageResponse.of(content, 0, 10, 1));
    }

    @Test
    void rejectsANegativePage() {
        assertThatIllegalArgumentException()
                .isThrownBy(() -> PageResponse.of(List.of(), -1, 10, 0))
                .withMessage("page must not be negative");
    }

    @Test
    void rejectsANonPositiveSize() {
        assertThatIllegalArgumentException()
                .isThrownBy(() -> PageResponse.of(List.of(), 0, 0, 0))
                .withMessage("size must be positive");
        assertThatIllegalArgumentException()
                .isThrownBy(() -> PageResponse.of(List.of(), 0, -1, 0))
                .withMessage("size must be positive");
    }

    @Test
    void rejectsANegativeTotalOfElements() {
        assertThatIllegalArgumentException()
                .isThrownBy(() -> PageResponse.of(List.of(), 0, 10, -1))
                .withMessage("totalElements must not be negative");
    }

    @Test
    void rejectsATotalOfPagesThatDoesNotMatchTheData() {
        assertThatIllegalArgumentException()
                .isThrownBy(() -> new PageResponse<>(List.of("a"), 0, 10, 1, 3))
                .withMessage("totalPages must equal ceil(totalElements / size)");
    }
}
