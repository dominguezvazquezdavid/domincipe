package com.domincipe.common.test;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.core.annotation.AliasFor;

/**
 * Boots a Domincipe service on a random port with the mandatory environment already set.
 *
 * <p>{@code APP_ENVIRONMENT} has no default value on purpose (service-runtime spec), so every
 * context test has to supply it. Repeating {@code @SpringBootTest(properties = "app.environment=local")}
 * in every service, and again in every new test class, is exactly the duplication PROJECT.md §7
 * forbids: the value is declared here once and shared through {@code common-test-support}
 * (decision D14).
 *
 * <p>{@link #webEnvironment()} and {@link #properties()} mirror their {@code @SpringBootTest}
 * counterparts through {@link AliasFor}, so a test can still open a mock environment or add its
 * own properties without falling back to the raw annotation.
 *
 * <p>It also imports {@link ApiDocsProbeController}, a controller that exists only on the test
 * classpath: that is how the contract proves that springdoc documents a new route without any
 * extra configuration (service-runtime spec). The probe answers on its own path and changes
 * nothing else the services do.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = DomincipeServiceTest.LOCAL_ENVIRONMENT)
@Import(ApiDocsProbeController.class)
public @interface DomincipeServiceTest {

    /** Default property that satisfies the mandatory environment of every service. */
    String LOCAL_ENVIRONMENT = "app.environment=local";

    /** Property that turns the published API documentation off through the single switch. */
    String DOCS_DISABLED = "APP_DOCS_ENABLED=false";

    /**
     * Web environment of the test, random port by default so the runtime contract can speak HTTP.
     *
     * @return aliased {@code @SpringBootTest} web environment
     */
    @AliasFor(annotation = SpringBootTest.class, attribute = "webEnvironment")
    SpringBootTest.WebEnvironment webEnvironment() default SpringBootTest.WebEnvironment.RANDOM_PORT;

    /**
     * Inlined properties of the test context.
     *
     * <p>The default keeps the mandatory environment; a test that adds properties must repeat it,
     * because the alias replaces the meta-annotation value instead of merging with it.
     *
     * @return aliased {@code @SpringBootTest} inlined properties
     */
    @AliasFor(annotation = SpringBootTest.class, attribute = "properties")
    String[] properties() default {LOCAL_ENVIRONMENT};
}
