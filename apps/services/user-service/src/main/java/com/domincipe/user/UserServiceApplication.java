package com.domincipe.user;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entry point of the user-service.
 *
 * <p>It is the only {@code @SpringBootApplication} of the module, which is what the tests rely
 * on to locate a valid startup configuration (repo-layout spec). The shared operational beans
 * arrive through {@code common-observability}, whose auto-configuration is registered in
 * {@code META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports}.
 */
@SpringBootApplication
public class UserServiceApplication {

    /**
     * Starts the service.
     *
     * @param args command-line arguments passed through to Spring Boot
     */
    public static void main(final String[] args) {
        SpringApplication.run(UserServiceApplication.class, args);
    }
}
