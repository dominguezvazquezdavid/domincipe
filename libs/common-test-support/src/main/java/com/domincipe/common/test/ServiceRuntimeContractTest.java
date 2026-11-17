package com.domincipe.common.test;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.http.HttpResponse;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;

/**
 * Runtime contract every Domincipe service must honour, exercised over real HTTP.
 *
 * <p>It covers the guarantees of the service-runtime spec that can be observed from outside the
 * process: health and probes, Prometheus metrics, request correlation and the published OpenAPI
 * document.
 *
 * <p>Each service extends this class and annotates the subclass with {@link DomincipeServiceTest};
 * the contract lives here once (PROJECT.md §7, decision D14).
 */
public abstract class ServiceRuntimeContractTest extends AbstractServiceHttpTest {

    @Value("${spring.application.name}")
    private String applicationName;

    @Value("${spring.application.version}")
    private String applicationVersion;

    @Test
    void exposesHealthAsUp() throws Exception {
        HttpResponse<String> response = get("/actuator/health");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(textAt(response.body(), "$.status")).isEqualTo("UP");
    }

    @Test
    void exposesLivenessAndReadinessAsUp() throws Exception {
        HttpResponse<String> liveness = get("/actuator/health/liveness");
        HttpResponse<String> readiness = get("/actuator/health/readiness");

        assertThat(liveness.statusCode()).isEqualTo(200);
        assertThat(textAt(liveness.body(), "$.status")).isEqualTo("UP");
        assertThat(readiness.statusCode()).isEqualTo(200);
        assertThat(textAt(readiness.body(), "$.status")).isEqualTo("UP");
    }

    @Test
    void exposesPrometheusMetricsForTheJvmAndForHttpRequests() throws Exception {
        get("/actuator/health");

        HttpResponse<String> response = get("/actuator/prometheus");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().firstValue("Content-Type").orElse(""))
                .startsWith("text/plain");
        assertThat(response.body()).contains("jvm_");
        assertThat(response.body()).contains("http_server_");
    }

    @Test
    void echoesTheIncomingRequestId() throws Exception {
        HttpResponse<String> response = get("/actuator/health", Map.of("X-Request-Id", "7d1f-abc"));

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().firstValue("X-Request-Id")).contains("7d1f-abc");
    }

    @Test
    void generatesADifferentRequestIdWhenNoneIsSent() throws Exception {
        String first = get("/actuator/health").headers().firstValue("X-Request-Id").orElse(null);
        String second = get("/actuator/health").headers().firstValue("X-Request-Id").orElse(null);

        assertThat(first).isNotBlank();
        assertThat(second).isNotBlank();
        assertThat(second).isNotEqualTo(first);
    }

    @Test
    void publishesTheOpenApiSpecificationWithTitleAndVersion() throws Exception {
        HttpResponse<String> response = get("/v3/api-docs");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(textAt(response.body(), "$.openapi")).startsWith("3.");
        assertThat(textAt(response.body(), "$.info.title")).isEqualTo(applicationName);
        assertThat(textAt(response.body(), "$.info.version")).isEqualTo(applicationVersion);
    }

    @Test
    void documentsANewControllerWithoutExtraConfiguration() throws Exception {
        HttpResponse<String> response = get("/v3/api-docs");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains(ApiDocsProbeController.PATH);
    }

    @Test
    void servesSwaggerUi() throws Exception {
        HttpResponse<String> response = getFollowingRedirects("/swagger-ui.html");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().firstValue("Content-Type").orElse(""))
                .startsWith("text/html");
        assertThat(response.body()).containsIgnoringCase("swagger");
    }
}
