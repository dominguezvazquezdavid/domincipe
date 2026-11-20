package com.domincipe.common.test;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import org.junit.jupiter.api.Test;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Proves that the integration level of the gate can start PostgreSQL and query it.
 *
 * <p>It asserts infrastructure, not behaviour: the domain suites arrive with the services that
 * own data. What it certifies is the part this change introduces —a daemon reachable from the
 * build, the pinned image running against it, and a JDBC endpoint the services can later use—,
 * so a broken daemon fails here with the container name instead of surfacing as a stranger
 * error inside the first domain IT.
 */
@Testcontainers
class PostgresContainerIT extends ContainerSupportBase {

    @Test
    void postgresAcceptsAQuery() throws IOException, InterruptedException {
        assertThat(POSTGRES.isRunning()).isTrue();

        var result = POSTGRES.execInContainer(
                "psql",
                "--username", POSTGRES.getUsername(),
                "--dbname", POSTGRES.getDatabaseName(),
                "--no-psqlrc",
                "--tuples-only",
                "--no-align",
                "--command", "select 1");

        assertThat(result.getExitCode()).as(result.getStderr()).isZero();
        assertThat(result.getStdout().trim()).isEqualTo("1");
    }
}
