package com.domincipe.common.observability;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.MDC;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Reuses or generates the {@code X-Request-Id} correlation identifier of a request.
 *
 * <p>The identifier is echoed in the response and published in the SLF4J {@link MDC} under
 * {@link #MDC_KEY}, so every log line written while the request is in flight carries it.
 * Reusing the incoming value lets a client or an upstream gateway follow one request across
 * services; generating one keeps that guarantee when nobody supplied it.
 *
 * <p>{@link OncePerRequestFilter} keeps the identifier stable when a request is dispatched
 * more than once (for example, an error dispatch), and the {@code finally} block removes the
 * MDC entry so a pooled thread cannot leak it into the next request.
 */
public class RequestIdFilter extends OncePerRequestFilter {

    /** Header carrying the correlation identifier, on the way in and on the way out. */
    public static final String HEADER_NAME = "X-Request-Id";

    /** MDC key the logging pattern must reference as {@code %X{requestId}}. */
    public static final String MDC_KEY = "requestId";

    @Override
    protected void doFilterInternal(final HttpServletRequest request, final HttpServletResponse response,
            final FilterChain filterChain) throws ServletException, IOException {
        String requestId = resolveRequestId(request);
        response.setHeader(HEADER_NAME, requestId);
        MDC.put(MDC_KEY, requestId);
        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    /**
     * Returns the incoming identifier or a new one.
     *
     * <p>A blank header is treated as absent: a whitespace-only value would produce an empty
     * correlation it cannot be searched by, which defeats the purpose of the identifier.
     *
     * @param request current request
     * @return the identifier to propagate
     */
    private String resolveRequestId(final HttpServletRequest request) {
        String incoming = request.getHeader(HEADER_NAME);
        if (incoming == null || incoming.isBlank()) {
            return UUID.randomUUID().toString();
        }
        return incoming.trim();
    }
}
