package com.domincipe.user;

import com.domincipe.common.test.DocsDisabledContractTest;
import com.domincipe.common.test.DomincipeServiceTestWithoutDocs;

/**
 * Proves that user-service hides the OpenAPI document and Swagger UI with
 * {@code APP_DOCS_ENABLED=false} while the operational endpoints keep working.
 */
@DomincipeServiceTestWithoutDocs
class UserServiceDocsDisabledTest extends DocsDisabledContractTest {
}
