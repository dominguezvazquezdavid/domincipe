package com.domincipe.common.observability;

import static org.assertj.core.api.Assertions.assertThat;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.junit.jupiter.api.Test;
import org.springdoc.core.customizers.OpenApiCustomizer;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class ApiDocsAutoConfigurationTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(ApiDocsAutoConfiguration.class));

    @Test
    void fillsTheTitleAndVersionFromTheModuleConfiguration() {
        runner.withPropertyValues("spring.application.name=recipe-service",
                        "spring.application.version=0.1.0-SNAPSHOT")
                .run(context -> {
                    assertThat(context).hasNotFailed();

                    OpenAPI document = customized(context.getBean(OpenApiCustomizer.class), new OpenAPI());

                    assertThat(document.getInfo().getTitle()).isEqualTo("recipe-service");
                    assertThat(document.getInfo().getVersion()).isEqualTo("0.1.0-SNAPSHOT");
                });
    }

    @Test
    void keepsTheInformationSpringdocAlreadyPutInTheDocument() {
        runner.withPropertyValues("spring.application.name=media-service",
                        "spring.application.version=1.2.3")
                .run(context -> {
                    OpenAPI document = customized(context.getBean(OpenApiCustomizer.class),
                            new OpenAPI().info(new Info().description("Published by media-service")));

                    assertThat(document.getInfo().getDescription())
                            .isEqualTo("Published by media-service");
                    assertThat(document.getInfo().getTitle()).isEqualTo("media-service");
                });
    }

    @Test
    void fallsBackWhenTheModuleDeclaresNoNameOrVersion() {
        runner.run(context -> {
            OpenAPI document = customized(context.getBean(OpenApiCustomizer.class), new OpenAPI());

            assertThat(document.getInfo().getTitle()).isEqualTo("domincipe");
            assertThat(document.getInfo().getVersion()).isEqualTo("unknown");
        });
    }

    @Test
    void backsOffWhenTheServiceDeclaresItsOwnCustomizer() {
        runner.withBean(ApiDocsAutoConfiguration.CUSTOMIZER_BEAN_NAME, OpenApiCustomizer.class,
                        () -> openApi -> { })
                .run(context -> assertThat(context.getBeansOfType(OpenApiCustomizer.class)).hasSize(1));
    }

    /**
     * Applies the customizer to a document, as springdoc does after building it.
     *
     * @param customizer customizer contributed by the auto-configuration
     * @param document document to customise
     * @return the same document, customised
     */
    private static OpenAPI customized(final OpenApiCustomizer customizer, final OpenAPI document) {
        customizer.customise(document);
        return document;
    }
}
