package com.domincipe.common.observability;

import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Runtime configuration every Domincipe service must provide.
 *
 * <p>{@code APP_ENVIRONMENT} deliberately has no default value: a service that started as whatever
 * the fallback was would hide a misconfigured deployment, which is the silent failure the
 * service-runtime spec forbids. Validation therefore runs through {@link Validated} and the
 * message names both the environment variable and the accepted values.
 */
@Validated
@ConfigurationProperties(prefix = "app")
public class AppEnvironmentProperties {

    @NotNull(message = "APP_ENVIRONMENT is required and must be one of local, dev, obs")
    private AppEnvironment environment;

    /**
     * Returns the environment the service is running in.
     *
     * @return configured environment, never {@code null} once the context has started
     */
    public AppEnvironment getEnvironment() {
        return environment;
    }

    /**
     * Sets the environment the service is running in.
     *
     * @param environment bound value of {@code APP_ENVIRONMENT}
     */
    public void setEnvironment(final AppEnvironment environment) {
        this.environment = environment;
    }
}
