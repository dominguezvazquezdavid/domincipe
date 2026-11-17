package com.domincipe.common.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Controller that exists only on the test classpath.
 *
 * <p>The service-runtime spec guarantees that a new controller shows up in the OpenAPI document
 * without further configuration, and the only way to prove it is to add one. It is imported by
 * {@link DomincipeServiceTest}, so every contract test boots a service that has this route.
 */
@RestController
public class ApiDocsProbeController {

    /** Path of the probe, asserted to appear in the generated document. */
    public static final String PATH = "/probe/api-docs";

    /**
     * Answers the probe.
     *
     * @return a fixed payload; the contract only cares about the route being documented
     */
    @GetMapping(PATH)
    String probe() {
        return "ok";
    }
}
