package com.domincipe.gateway;

import com.domincipe.common.test.DomincipeServiceTest;
import com.domincipe.common.test.ServiceRuntimeContractTest;

/**
 * Runs the shared runtime contract against the api-gateway module: health, probes, metrics and
 * request correlation over real HTTP.
 */
@DomincipeServiceTest
class ApiGatewayRuntimeContractTest extends ServiceRuntimeContractTest {
}
