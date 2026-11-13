package com.domincipe.media;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Checks that the module starts as a real Spring Boot application.
 *
 * <p>{@code app.environment} is supplied because it is mandatory and has no default value
 * (service-runtime spec); the early-failure cases are covered by dedicated tests, not here.
 */
@SpringBootTest(properties = "app.environment=local")
class MediaServiceApplicationTest {

    @Test
    void contextLoads() {
    }
}
