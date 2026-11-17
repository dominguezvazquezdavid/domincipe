package com.domincipe.common.test;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Boots a Domincipe service with the API documentation switched off.
 *
 * <p>The disabled-documentation scenario needs a context of its own, because springdoc reads its
 * flags at startup. Declaring the enabling property again here keeps the value in one place
 * instead of copying the pair of properties into six test classes (PROJECT.md §7, decision D14).
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Inherited
@DomincipeServiceTest(properties = {
        DomincipeServiceTest.LOCAL_ENVIRONMENT,
        DomincipeServiceTest.DOCS_DISABLED
})
public @interface DomincipeServiceTestWithoutDocs {
}
