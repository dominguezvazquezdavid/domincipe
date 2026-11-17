package com.domincipe.user;

import com.domincipe.common.test.DomincipeServiceTest;
import com.domincipe.common.test.ServiceRuntimeContractTest;

/**
 * Runs the shared runtime contract against the user-service module: health, probes, metrics and
 * request correlation over real HTTP.
 */
@DomincipeServiceTest
class UserServiceRuntimeContractTest extends ServiceRuntimeContractTest {
}
