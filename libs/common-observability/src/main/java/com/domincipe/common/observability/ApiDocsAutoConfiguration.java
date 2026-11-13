package com.domincipe.common.observability;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springdoc.core.customizers.OpenApiCustomizer;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.core.env.Environment;

/**
 * Fills the title and version of the generated OpenAPI document from the module's own
 * configuration.
 *
 * <p>A service that publishes a contract called "OpenAPI definition" and version "v0" is
 * technically valid but useless for whoever reads it, so the service-runtime spec requires both
 * fields. Each module already declares its name in {@code spring.application.name} and its
 * version in {@code spring.application.version}, filled by Maven resource filtering from
 * {@code @project.version@}; this class copies them into the document once for all six services
 * (design D16).
 *
 * <p>It contributes an {@link OpenApiCustomizer} instead of an {@link OpenAPI} bean on purpose:
 * springdoc publishes its own default document, and two auto-configurations competing for the same
 * bean type would make the result depend on auto-configuration ordering. A customizer runs once
 * the document exists, so it can enrich whichever instance springdoc built and still stays out of
 * the way of a service that defines its own.
 */
@AutoConfiguration
@ConditionalOnClass(OpenApiCustomizer.class)
public class ApiDocsAutoConfiguration {

    /** Property holding the service name, already declared by every module. */
    static final String TITLE_PROPERTY = "spring.application.name";

    /** Property holding the module version, filtered from the POM. */
    static final String VERSION_PROPERTY = "spring.application.version";

    /**
     * Name of the customizer, so a service can replace it without fighting an anonymous bean.
     */
    static final String CUSTOMIZER_BEAN_NAME = "domincipeOpenApiCustomizer";

    /**
     * Sets the title and version of every generated document.
     *
     * @param environment configuration of the service that is publishing the contract
     * @return customizer applied by springdoc after building the document
     */
    @Bean
    @ConditionalOnMissingBean(name = CUSTOMIZER_BEAN_NAME)
    OpenApiCustomizer domincipeOpenApiCustomizer(final Environment environment) {
        return openApi -> {
            Info info = openApi.getInfo() == null ? new Info() : openApi.getInfo();
            openApi.setInfo(info
                    .title(environment.getProperty(TITLE_PROPERTY, "domincipe"))
                    .version(environment.getProperty(VERSION_PROPERTY, "unknown")));
        };
    }
}
