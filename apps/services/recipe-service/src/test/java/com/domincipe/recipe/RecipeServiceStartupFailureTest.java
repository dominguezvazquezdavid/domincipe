package com.domincipe.recipe;

import static org.assertj.core.api.Assertions.assertThat;

import com.domincipe.common.test.ServiceStartupAssertions;
import org.junit.jupiter.api.Test;

/**
 * Proves that recipe-service refuses to start without a valid {@code APP_ENVIRONMENT}, as the
 * service-runtime spec requires: no silent default and no bare enum error.
 */
class RecipeServiceStartupFailureTest {

    @Test
    void failsNamingTheVariableWhenItIsMissing() {
        String failure = ServiceStartupAssertions.failureWithoutEnvironment(RecipeServiceApplication.class);

        assertThat(failure).contains("APP_ENVIRONMENT");
    }

    @Test
    void failsListingTheAcceptedValuesWhenTheValueIsUnknown() {
        String failure = ServiceStartupAssertions.failureWithEnvironment(RecipeServiceApplication.class,
                "produccion");

        assertThat(failure).contains("APP_ENVIRONMENT", "local", "dev", "obs");
    }
}
