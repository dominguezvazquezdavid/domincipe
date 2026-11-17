package com.domincipe.common.dto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import java.time.Instant;
import org.junit.jupiter.api.Test;

class ErrorResponseTest {

    @Test
    void keepsTheValuesItWasBuiltWith() {
        Instant timestamp = Instant.parse("2026-11-13T10:15:30Z");

        ErrorResponse error = new ErrorResponse(timestamp, 404, "RECIPE_NOT_FOUND", "Recipe not found",
                "/api/v1/recipes/42", "7d1f-abc");

        assertThat(error.timestamp()).isEqualTo(timestamp);
        assertThat(error.status()).isEqualTo(404);
        assertThat(error.code()).isEqualTo("RECIPE_NOT_FOUND");
        assertThat(error.message()).isEqualTo("Recipe not found");
        assertThat(error.path()).isEqualTo("/api/v1/recipes/42");
        assertThat(error.requestId()).isEqualTo("7d1f-abc");
    }

    @Test
    void acceptsAnErrorWithoutPathOrRequestId() {
        Instant timestamp = Instant.parse("2026-11-13T10:15:30Z");

        ErrorResponse error = new ErrorResponse(timestamp, 500, "INTERNAL_ERROR", "Unexpected failure", null, null);

        assertThat(error.path()).isNull();
        assertThat(error.requestId()).isNull();
    }

    @Test
    void stampsTheCurrentTimeInTheFactory() {
        Instant before = Instant.now();

        ErrorResponse error = ErrorResponse.of(400, "VALIDATION_ERROR", "Invalid payload", "/api/v1/recipes", null);

        Instant after = Instant.now();
        assertThat(error.timestamp()).isBetween(before, after);
        assertThat(error.status()).isEqualTo(400);
        assertThat(error.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(error.message()).isEqualTo("Invalid payload");
        assertThat(error.path()).isEqualTo("/api/v1/recipes");
        assertThat(error.requestId()).isNull();
    }

    @Test
    void rejectsAMissingTimestamp() {
        assertThatNullPointerException()
                .isThrownBy(() -> new ErrorResponse(null, 400, "VALIDATION_ERROR", "Invalid payload", null, null))
                .withMessage("timestamp must not be null");
    }

    @Test
    void rejectsAStatusOutsideTheHttpRange() {
        Instant timestamp = Instant.parse("2026-11-13T10:15:30Z");

        assertThatIllegalArgumentException()
                .isThrownBy(() -> new ErrorResponse(timestamp, 99, "INVALID", "Invalid", null, null))
                .withMessage("status must be a valid HTTP status code");
        assertThatIllegalArgumentException()
                .isThrownBy(() -> new ErrorResponse(timestamp, 600, "INVALID", "Invalid", null, null))
                .withMessage("status must be a valid HTTP status code");
    }

    @Test
    void rejectsAMissingCode() {
        Instant timestamp = Instant.parse("2026-11-13T10:15:30Z");

        assertThatNullPointerException()
                .isThrownBy(() -> new ErrorResponse(timestamp, 400, null, "Invalid payload", null, null))
                .withMessage("code must not be null");
    }

    @Test
    void rejectsAMissingMessage() {
        Instant timestamp = Instant.parse("2026-11-13T10:15:30Z");

        assertThatNullPointerException()
                .isThrownBy(() -> new ErrorResponse(timestamp, 400, "VALIDATION_ERROR", null, null, null))
                .withMessage("message must not be null");
    }
}
