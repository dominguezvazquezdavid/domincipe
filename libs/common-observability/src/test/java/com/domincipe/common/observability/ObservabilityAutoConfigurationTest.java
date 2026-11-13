package com.domincipe.common.observability;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.context.annotation.ImportCandidates;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class ObservabilityAutoConfigurationTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(ObservabilityAutoConfiguration.class));

    @ParameterizedTest
    @EnumSource(AppEnvironment.class)
    void bindsEveryAcceptedEnvironment(final AppEnvironment environment) {
        runner.withPropertyValues("app.environment=" + environment.name()).run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(AppEnvironmentProperties.class);
            assertThat(context.getBean(AppEnvironmentProperties.class).getEnvironment())
                    .isEqualTo(environment);
        });
    }

    @Test
    void appliesTheSharedOperationalDefaults() {
        runner.withPropertyValues("app.environment=dev").run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(RequestIdFilter.class);
            assertThat(context.getEnvironment()
                    .getProperty("management.endpoints.web.exposure.include"))
                    .isEqualTo("health,prometheus");
            assertThat(context.getEnvironment()
                    .getProperty("management.endpoint.health.probes.enabled")).isEqualTo("true");
            assertThat(context.getEnvironment().getProperty("spring.threads.virtual.enabled"))
                    .isEqualTo("true");
            assertThat(context.getEnvironment().getProperty("server.shutdown")).isEqualTo("graceful");
            assertThat(context.getEnvironment()
                    .getProperty("spring.lifecycle.timeout-per-shutdown-phase")).isEqualTo("30s");
        });
    }

    @Test
    void letsTheServiceOverrideAnyDefault() {
        runner.withPropertyValues("app.environment=local",
                        "management.endpoints.web.exposure.include=health",
                        "spring.threads.virtual.enabled=false")
                .run(context -> {
                    assertThat(context.getEnvironment()
                            .getProperty("management.endpoints.web.exposure.include"))
                            .isEqualTo("health");
                    assertThat(context.getEnvironment().getProperty("spring.threads.virtual.enabled"))
                            .isEqualTo("false");
                });
    }

    @Test
    void backsOffWhenTheServiceDeclaresItsOwnFilter() {
        runner.withBean("customRequestIdFilter", RequestIdFilter.class, RequestIdFilter::new)
                .withPropertyValues("app.environment=local")
                .run(context -> assertThat(context).hasSingleBean(RequestIdFilter.class));
    }

    @Test
    void failsToStartWithoutAppEnvironment() {
        runner.run(context -> {
            assertThat(context).hasFailed();
            assertThat(failureMessages(context.getStartupFailure()))
                    .contains("app.environment", "APP_ENVIRONMENT");
        });
    }

    @Test
    void failsToStartWithAnUnknownEnvironment() {
        runner.withPropertyValues("app.environment=produccion").run(context -> {
            assertThat(context).hasFailed();
            assertThat(failureMessages(context.getStartupFailure()))
                    .contains("app.environment", "local", "dev", "obs");
        });
    }

    @Test
    void failsToStartWithABlankEnvironment() {
        runner.withPropertyValues("app.environment= ").run(context -> {
            assertThat(context).hasFailed();
            assertThat(failureMessages(context.getStartupFailure()))
                    .contains("APP_ENVIRONMENT", "local", "dev", "obs");
        });
    }

    @Test
    void bindsTheEnvironmentIgnoringCaseAndSurroundingSpaces() {
        runner.withPropertyValues("app.environment= DEV ").run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context.getBean(AppEnvironmentProperties.class).getEnvironment())
                    .isEqualTo(AppEnvironment.dev);
        });
    }

    @Test
    void isRegisteredAsAnAutoConfiguration() {
        ImportCandidates candidates = ImportCandidates.load(AutoConfiguration.class,
                getClass().getClassLoader());

        assertThat(candidates.getCandidates())
                .contains(ObservabilityAutoConfiguration.class.getName());
    }

    /**
     * Flattens the message of a failure and of every cause, because the property name and the
     * reason live in different levels of the exception chain.
     *
     * @param failure startup failure reported by the context, never {@code null}
     * @return all messages joined by newlines
     */
    private static String failureMessages(final Throwable failure) {
        StringBuilder messages = new StringBuilder();
        Throwable current = failure;
        while (current != null) {
            messages.append(current.getMessage()).append('\n');
            current = current.getCause();
        }
        return messages.toString();
    }
}
