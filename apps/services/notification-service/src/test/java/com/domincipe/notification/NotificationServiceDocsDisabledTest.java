package com.domincipe.notification;

import com.domincipe.common.test.DocsDisabledContractTest;
import com.domincipe.common.test.DomincipeServiceTestWithoutDocs;

/**
 * Proves that notification-service hides the OpenAPI document and Swagger UI with
 * {@code APP_DOCS_ENABLED=false} while the operational endpoints keep working.
 */
@DomincipeServiceTestWithoutDocs
class NotificationServiceDocsDisabledTest extends DocsDisabledContractTest {
}
