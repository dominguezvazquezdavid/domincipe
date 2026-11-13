package com.domincipe.recipe;

import com.domincipe.common.test.DomincipeServiceTest;
import com.domincipe.common.test.ServiceRuntimeContractTest;

/**
 * Runs the shared runtime contract against the recipe-service module: health, probes, metrics and
 * request correlation over real HTTP.
 */
@DomincipeServiceTest
class RecipeServiceRuntimeContractTest extends ServiceRuntimeContractTest {
}
