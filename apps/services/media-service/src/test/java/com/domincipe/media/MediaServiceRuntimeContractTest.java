package com.domincipe.media;

import com.domincipe.common.test.DomincipeServiceTest;
import com.domincipe.common.test.ServiceRuntimeContractTest;

/**
 * Runs the shared runtime contract against the media-service module: health, probes, metrics and
 * request correlation over real HTTP.
 */
@DomincipeServiceTest
class MediaServiceRuntimeContractTest extends ServiceRuntimeContractTest {
}
