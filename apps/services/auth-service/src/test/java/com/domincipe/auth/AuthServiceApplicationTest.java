package com.domincipe.auth;

import com.domincipe.common.test.DomincipeServiceTest;
import org.junit.jupiter.api.Test;

/**
 * Checks that the module starts as a real Spring Boot application.
 *
 * <p>The mandatory {@code APP_ENVIRONMENT} and the random port come from
 * {@link DomincipeServiceTest}; requests against the running service are covered by
 * {@link AuthServiceRuntimeContractTest}, and the early-failure cases by dedicated tests.
 */
@DomincipeServiceTest
class AuthServiceApplicationTest {

    @Test
    void contextLoads() {
    }
}
