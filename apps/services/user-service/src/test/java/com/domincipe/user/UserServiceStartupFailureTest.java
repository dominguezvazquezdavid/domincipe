package com.domincipe.user;

import static org.assertj.core.api.Assertions.assertThat;

import com.domincipe.common.test.ServiceStartupAssertions;
import org.junit.jupiter.api.Test;

/**
 * Proves that user-service refuses to start without a valid {@code APP_ENVIRONMENT}, as the
 * service-runtime spec requires: no silent default and no bare enum error.
 */
class UserServiceStartupFailureTest {

    @Test
    void failsNamingTheVariableWhenItIsMissing() {
        String failure = ServiceStartupAssertions.failureWithoutEnvironment(UserServiceApplication.class);

        assertThat(failure).contains("APP_ENVIRONMENT");
    }

    @Test
    void failsListingTheAcceptedValuesWhenTheValueIsUnknown() {
        String failure = ServiceStartupAssertions.failureWithEnvironment(UserServiceApplication.class,
                "produccion");

        assertThat(failure).contains("APP_ENVIRONMENT", "local", "dev", "obs");
    }
}
