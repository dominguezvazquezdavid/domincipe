package com.domincipe.common.observability;

/**
 * Deployment environment a Domincipe service is configured for.
 *
 * <p>The constants are lowercase on purpose: they are the exact values accepted by
 * {@code APP_ENVIRONMENT} ({@code local}, {@code dev}, {@code obs}), so the constant name, the
 * {@link #toString()} used in logs and the documented contract all say the same thing instead of
 * forcing a translation between {@code LOCAL} and {@code local}. Binding is relaxed and still
 * accepts any case.
 */
public enum AppEnvironment {

    /** Developer workstation. */
    local,

    /** Shared development environment. */
    dev,

    /** Observability stack. */
    obs;

    /**
     * Resolves the environment from the raw {@code APP_ENVIRONMENT} value.
     *
     * <p>Boot's default enum conversion rejects an unknown value with a bare
     * {@code No enum constant ...}, which leaves the operator without the accepted values. This
     * conversion names them, as the service-runtime spec requires.
     *
     * @param value raw value, matched case-insensitively after trimming
     * @return the matching environment
     * @throws IllegalArgumentException when the value is missing, blank or unknown
     */
    public static AppEnvironment fromValue(final String value) {
        String candidate = value == null ? "" : value.trim();
        for (AppEnvironment environment : values()) {
            if (environment.name().equalsIgnoreCase(candidate)) {
                return environment;
            }
        }
        throw new IllegalArgumentException(
                "APP_ENVIRONMENT must be one of local, dev, obs (received '" + candidate + "')");
    }
}
