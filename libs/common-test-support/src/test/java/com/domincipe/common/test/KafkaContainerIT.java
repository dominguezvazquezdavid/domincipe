package com.domincipe.common.test;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import org.junit.jupiter.api.Test;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Proves that the integration level of the gate can start Kafka and drive it.
 *
 * <p>The probe creates and describes a topic with the {@code kafka-topics.sh} the image ships,
 * so what is verified is a broker that accepts an administrative request, not just a container
 * that reports itself as running. The bootstrap address is the {@code BROKER} listener on 9093:
 * Testcontainers advertises it as the container's own hostname, which a client running inside
 * the container reaches without leaving it, unlike the mapped {@code PLAINTEXT} address meant
 * for the build host.
 */
@Testcontainers
class KafkaContainerIT extends ContainerSupportBase {

    private static final String TOPIC = "integration-probe";
    private static final String BROKER = "localhost:9093";

    @Test
    void kafkaCreatesAndDescribesATopic() throws IOException, InterruptedException {
        assertThat(KAFKA.isRunning()).isTrue();

        var created = KAFKA.execInContainer("/opt/kafka/bin/kafka-topics.sh",
                "--bootstrap-server", BROKER,
                "--create",
                "--topic", TOPIC,
                "--partitions", "1",
                "--replication-factor", "1");

        assertThat(created.getExitCode()).as(created.getStdout() + created.getStderr()).isZero();

        var described = KAFKA.execInContainer("/opt/kafka/bin/kafka-topics.sh",
                "--bootstrap-server", BROKER,
                "--describe",
                "--topic", TOPIC);

        assertThat(described.getExitCode()).as(described.getStderr()).isZero();
        assertThat(described.getStdout()).contains(TOPIC).contains("PartitionCount: 1");
    }
}
