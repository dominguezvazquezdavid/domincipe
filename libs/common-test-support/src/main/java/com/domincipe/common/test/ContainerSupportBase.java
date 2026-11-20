package com.domincipe.common.test;

import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.kafka.KafkaContainer;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * The two infrastructure containers every integration test of the tree starts from.
 *
 * <p>The integration level needs a Docker daemon. Until the {@code ci-integration} change the
 * gate of pull requests had none, so a {@code *IT.java} was rejected before Testcontainers
 * could fail inside it. Now the daemon is a container of the CI stack and this class is the one
 * place where the pinned images live, so a version bump of {@code PROJECT.md} §4 moves every
 * integration test at once.
 *
 * <p>Both fields are {@code static} and live in this superclass on purpose: Testcontainers
 * starts them once per class and shares them between the subclasses, which is what keeps a
 * suite of several ITs from paying the startup of PostgreSQL and Kafka more than once per test
 * class. The images are the ones the local environment runs —{@code postgres:16.16-alpine} and
 * {@code apache/kafka:4.4.0}, KRaft and no ZooKeeper— so an IT tests against the same versions
 * the developer has.
 */
public abstract class ContainerSupportBase {

    /** PostgreSQL of {@code PROJECT.md} §4, the same tag {@code docker-compose.base.yml} runs. */
    public static final String POSTGRES_IMAGE = "postgres:16.16-alpine";

    /** Kafka of {@code PROJECT.md} §4, KRaft mode: the image needs no ZooKeeper. */
    public static final String KAFKA_IMAGE = "apache/kafka:4.4.0";

    /** Database the probes use; the default of the module is irrelevant to them. */
    public static final String POSTGRES_DATABASE = "domincipe";

    @Container
    protected static final PostgreSQLContainer POSTGRES =
            new PostgreSQLContainer(DockerImageName.parse(POSTGRES_IMAGE)).withDatabaseName(POSTGRES_DATABASE);

    @Container
    protected static final KafkaContainer KAFKA = new KafkaContainer(DockerImageName.parse(KAFKA_IMAGE));

    /** Utility class: the container fields are started by JUnit, not by an instance. */
    protected ContainerSupportBase() {
    }
}
