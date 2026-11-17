package com.domincipe.notification;

import com.domincipe.common.test.DomincipeServiceTest;
import com.domincipe.common.test.ServiceRuntimeContractTest;

/**
 * Runs the shared runtime contract against the notification-service module: health, probes,
 * metrics and request correlation over real HTTP.
 */
@DomincipeServiceTest
class NotificationServiceRuntimeContractTest extends ServiceRuntimeContractTest {
}
