package com.domincipe.common.test;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.http.HttpResponse;
import org.junit.jupiter.api.Test;

/**
 * Contract of a service started with the API documentation switched off.
 *
 * <p>The service-runtime spec requires a single switch to hide both endpoints without touching
 * code and without breaking the rest of the service, so this contract asserts the two 404s and
 * then checks that an operational endpoint still answers.
 */
public abstract class DocsDisabledContractTest extends AbstractServiceHttpTest {

    @Test
    void doesNotPublishTheSpecification() throws Exception {
        assertThat(get("/v3/api-docs").statusCode()).isEqualTo(404);
    }

    @Test
    void doesNotServeTheInteractiveUi() throws Exception {
        assertThat(getFollowingRedirects("/swagger-ui.html").statusCode()).isEqualTo(404);
    }

    @Test
    void keepsTheOperationalEndpointsWorking() throws Exception {
        HttpResponse<String> response = get("/actuator/health");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(textAt(response.body(), "$.status")).isEqualTo("UP");
    }
}
