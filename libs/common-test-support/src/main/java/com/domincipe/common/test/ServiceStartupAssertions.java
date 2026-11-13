package com.domincipe.common.test;

import org.springframework.boot.Banner;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.mock.env.MockEnvironment;

/**
 * Starts a service expecting it to fail and returns everything it complained about.
 *
 * <p>The service-runtime spec requires a missing or unknown {@code APP_ENVIRONMENT} to abort the
 * startup, and the only honest proof is starting the real application class without the value.
 * The environment is a {@link MockEnvironment} so the result depends on the code under test and
 * not on an {@code APP_ENVIRONMENT} exported in whoever's shell runs the suite.
 *
 * <p>The whole exception chain is flattened because the property name, the reason and the
 * accepted values live in different causes of the failure.
 */
public final class ServiceStartupAssertions {

    private ServiceStartupAssertions() {
    }

    /**
     * Starts the application without {@code APP_ENVIRONMENT}.
     *
     * @param applicationClass the service entry point to start
     * @return failure messages joined by newlines
     */
    public static String failureWithoutEnvironment(final Class<?> applicationClass) {
        return failureOf(applicationClass, new MockEnvironment());
    }

    /**
     * Starts the application with an {@code APP_ENVIRONMENT} value no environment accepts.
     *
     * @param applicationClass the service entry point to start
     * @param value the rejected value
     * @return failure messages joined by newlines
     */
    public static String failureWithEnvironment(final Class<?> applicationClass, final String value) {
        return failureOf(applicationClass, new MockEnvironment(), "--app.environment=" + value);
    }

    /**
     * Runs the application expecting it to fail during the context refresh.
     *
     * <p>The context is only created on success, and that success is what turns into an
     * {@link AssertionError}: a service that starts with a broken environment is the bug these
     * tests exist to catch.
     *
     * @param applicationClass the service entry point to start
     * @param environment environment isolated from the machine running the tests
     * @param arguments command-line arguments passed to the application
     * @return failure messages joined by newlines
     */
    private static String failureOf(final Class<?> applicationClass,
            final MockEnvironment environment, final String... arguments) {
        try (ConfigurableApplicationContext started = new SpringApplicationBuilder(applicationClass)
                .environment(environment)
                .web(WebApplicationType.NONE)
                .bannerMode(Banner.Mode.OFF)
                .run(arguments)) {
            throw new AssertionError(applicationClass.getSimpleName()
                    + " started, but it must fail the startup when APP_ENVIRONMENT is missing or invalid");
        } catch (RuntimeException failure) {
            return messagesOf(failure);
        }
    }

    /**
     * Flattens the message of a failure and of every cause.
     *
     * @param failure startup failure reported by the application
     * @return all messages joined by newlines
     */
    private static String messagesOf(final Throwable failure) {
        StringBuilder messages = new StringBuilder();
        Throwable current = failure;
        while (current != null) {
            messages.append(current.getMessage()).append('\n');
            current = current.getCause();
        }
        return messages.toString();
    }
}
