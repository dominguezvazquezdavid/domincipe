package com.domincipe.notification;

import static org.assertj.core.api.Assertions.assertThat;

import com.domincipe.common.test.ServiceStartupAssertions;
import org.junit.jupiter.api.Test;

/**
 * Proves that notification-service refuses to start without a valid {@code APP_ENVIRONMENT}, as
 * the service-runtime spec requires: no silent default and no bare enum error.
 */
class NotificationServiceStartupFailureTest {

    @Test
    void failsNamingTheVariableWhenItIsMissing() {
        String failure = ServiceStartupAssertions
                .failureWithoutEnvironment(NotificationServiceApplication.class);

        assertThat(failure).contains("APP_ENVIRONMENT");
    }

    @Test
    void failsListingTheAcceptedValuesWhenTheValueIsUnknown() {
        String failure = ServiceStartupAssertions
                .failureWithEnvironment(NotificationServiceApplication.class, "produccion");

        assertThat(failure).contains("APP_ENVIRONMENT", "local", "dev", "obs");
    }
}
