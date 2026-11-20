package com.domincipe.gateway;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.matchesPattern;
import static org.hamcrest.Matchers.notNullValue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.MountableFile;

/**
 * End-to-end level of the backend: the gateway artifact the build just produced, running in a
 * container, answering over HTTP.
 *
 * <p>It is not a {@code @SpringBootTest}: the point of the level is the packaged jar and the
 * process around it, so the test takes {@code target/api-gateway-*.jar} —repackaged by
 * spring-boot-maven-plugin earlier in the same build— and starts it on the pinned JRE image. The
 * assertions are the invariants of {@code PROJECT.md} §8 and the {@code service-runtime}
 * capability: the process reports itself ready, and the correlation identifier
 * {@code common-observability} echoes or generates travels in the response.
 *
 * <p>No project image is needed, which is what lets this test run in the same Maven invocation
 * as unit and integration instead of waiting for the image stage.
 */
@Testcontainers
class ApiGatewayE2EIT {

    /** The JRE of {@code PROJECT.md} §4, the same one the runtime images use. */
    private static final String JRE_IMAGE = "eclipse-temurin:21.0.13_9-jre-alpine";

    private static final int HTTP_PORT = 8080;

    /**
     * The repackaged jar of this module. Failsafe runs with the module as working directory and
     * after {@code package}, so the artifact exists by the time the container is created; a
     * missing one fails here with the directory listed instead of starting an empty container.
     */
    private static final Path ARTIFACT = artifact();

    @Container
    private static final GenericContainer<?> GATEWAY = new GenericContainer<>(DockerImageName.parse(JRE_IMAGE))
            .withCopyFileToContainer(MountableFile.forHostPath(ARTIFACT), "/app/app.jar")
            .withEnv("APP_ENVIRONMENT", "local")
            .withExposedPorts(HTTP_PORT)
            .withCommand("java", "-jar", "/app/app.jar")
            .waitingFor(Wait.forHttp("/actuator/health/readiness")
                    .forPort(HTTP_PORT)
                    .forStatusCode(200));

    @Test
    void reportsReadyOverHttp() {
        given()
                .baseUri(baseUri())
                .when()
                .get("/actuator/health")
                .then()
                .statusCode(200)
                .body("status", equalTo("UP"));
    }

    @Test
    void answersWithACorrelationId() {
        given()
                .baseUri(baseUri())
                // A supplied identifier has to come back untouched: reusing it is what lets a
                // caller follow one request across services.
                .header("X-Request-Id", "e2e-correlation-probe")
                .when()
                .get("/actuator/health")
                .then()
                .statusCode(200)
                .header("X-Request-Id", equalTo("e2e-correlation-probe"));

        given()
                .baseUri(baseUri())
                .when()
                .get("/actuator/health")
                .then()
                .statusCode(200)
                // Without one, the gateway generates a UUID: the header is never empty.
                .header("X-Request-Id", notNullValue())
                .header("X-Request-Id", matchesPattern("[0-9a-f-]{36}"));
    }

    /**
     * Provocation of task 5.5, reverted in the next commit: a red {@code *IT.java} has to leave
     * the commit in failure, because failsafe runs inside the same Maven invocation as the unit
     * and slice levels and the Backend stage is what the gate reports. The assertion asks for a
     * status the gateway never returns, so the red comes from the assertion and not from the
     * container failing to start.
     */
    @Test
    void deliberateFailureOfTask55() {
        given()
                .baseUri(baseUri())
                .when()
                .get("/actuator/health")
                .then()
                .statusCode(418);
    }

    private static String baseUri() {
        return "http://" + GATEWAY.getHost() + ":" + GATEWAY.getMappedPort(HTTP_PORT);
    }

    private static Path artifact() {
        Path target = Path.of("target").toAbsolutePath();
        try (Stream<Path> entries = Files.list(target)) {
            List<Path> jars = entries
                    .filter(path -> path.getFileName().toString().endsWith(".jar"))
                    .toList();
            if (jars.size() != 1) {
                throw new IllegalStateException("Expected exactly one jar in " + target
                        + " (the one spring-boot-maven-plugin repackages), found " + jars);
            }
            return jars.get(0);
        } catch (IOException cause) {
            throw new IllegalStateException("Cannot list " + target + ": is the build at package phase?",
                    cause);
        }
    }
}
