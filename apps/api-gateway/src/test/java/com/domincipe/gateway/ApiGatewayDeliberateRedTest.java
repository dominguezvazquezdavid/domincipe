package com.domincipe.gateway;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/**
 * Deliberately red test of the end-to-end check of task 9.1.
 *
 * <p>It lives only on the temporary branch {@code test/ci-e2e-pr}: it is the failure the pull
 * request has to carry so that the gate publishes a failing status and the protected branch
 * refuses the merge. The next commit of the branch deletes it, and the pull request is closed
 * without merging, so no version of {@code develop} ever contains this class.
 */
class ApiGatewayDeliberateRedTest {

    @Test
    void deliberateFailure() {
        assertEquals("expected", "deliberate failure of task 9.1", "the gate must turn red here");
    }
}
