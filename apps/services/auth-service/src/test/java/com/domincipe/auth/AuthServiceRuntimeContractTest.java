package com.domincipe.auth;

import com.domincipe.common.test.DomincipeServiceTest;
import com.domincipe.common.test.ServiceRuntimeContractTest;

/**
 * Runs the shared runtime contract against the auth-service module: health, probes, metrics and
 * request correlation over real HTTP.
 */
@DomincipeServiceTest
class AuthServiceRuntimeContractTest extends ServiceRuntimeContractTest {
}
