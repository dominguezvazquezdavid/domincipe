package com.domincipe.common.observability;

import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.context.properties.ConfigurationPropertiesBinding;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.PropertySource;
import org.springframework.core.convert.converter.Converter;

/**
 * Shared operational behaviour for every Domincipe service.
 *
 * <p>Registered in {@code META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports},
 * so a service only has to depend on {@code common-observability}: this class then contributes the
 * correlation filter and the defaults every service must run with, instead of six copies of the
 * same {@code application.yml} drifting apart.
 *
 * <p>The defaults live in a property file imported with {@link PropertySource}, which Spring
 * Framework appends at the lowest precedence: a service overrides any of them from its own
 * {@code application.yml}, from a profile or from the environment, and a future upstream default
 * change cannot silently take them away.
 */
@AutoConfiguration
@EnableConfigurationProperties(AppEnvironmentProperties.class)
@PropertySource("classpath:observability-defaults.properties")
public class ObservabilityAutoConfiguration {

    /**
     * Registers the correlation filter, unless the service already declared its own.
     *
     * @return filter that echoes or generates {@code X-Request-Id} and publishes it in the MDC
     */
    @Bean
    @ConditionalOnMissingBean
    RequestIdFilter requestIdFilter() {
        return new RequestIdFilter();
    }

    /**
     * Converts {@code APP_ENVIRONMENT} through the enum so an unknown value fails listing the
     * accepted ones instead of Boot's bare {@code No enum constant} message.
     *
     * <p>{@link ConfigurationPropertiesBinding} is what puts this converter in the conversion
     * service of the configuration-properties binder, before {@link AppEnvironmentProperties} is
     * bound.
     *
     * @return converter from the raw value to the environment
     */
    @Bean
    @ConfigurationPropertiesBinding
    Converter<String, AppEnvironment> appEnvironmentConverter() {
        return AppEnvironment::fromValue;
    }
}
