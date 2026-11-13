package com.domincipe.common.dto;

import java.time.Instant;
import java.util.Objects;

/**
 * Error envelope shared by every Domincipe service.
 *
 * <p>A single shape means a client can handle failures without knowing which service answered.
 * The record is immutable, so the values observed in a log entry cannot change after the fact.
 *
 * <p>{@link #of(int, String, String, String, String)} stamps the current time, which is what an
 * exception handler needs; the canonical constructor is kept public so a caller that already
 * has the timestamp (for example, a rethrow of an upstream error) can preserve it.
 *
 * @param timestamp instant at which the error was created, never {@code null}
 * @param status HTTP status code that classifies the error
 * @param code stable machine-readable error code
 * @param message human-readable description, never {@code null}
 * @param path request path that produced the error, may be {@code null}
 * @param requestId correlation identifier of the request, may be {@code null}
 */
public record ErrorResponse(
        Instant timestamp,
        int status,
        String code,
        String message,
        String path,
        String requestId) {

    /**
     * Validates the envelope so an impossible status or a missing description cannot be
     * published as a contract.
     */
    public ErrorResponse {
        Objects.requireNonNull(timestamp, "timestamp must not be null");
        if (status < 100 || status > 599) {
            throw new IllegalArgumentException("status must be a valid HTTP status code");
        }
        Objects.requireNonNull(code, "code must not be null");
        Objects.requireNonNull(message, "message must not be null");
    }

    /**
     * Builds an error with the current timestamp.
     *
     * @param status HTTP status code that classifies the error
     * @param code stable machine-readable error code
     * @param message human-readable description
     * @param path request path that produced the error
     * @param requestId correlation identifier of the request
     * @return the error envelope stamped by the service
     */
    public static ErrorResponse of(final int status, final String code, final String message,
            final String path, final String requestId) {
        return new ErrorResponse(Instant.now(), status, code, message, path, requestId);
    }
}
