package com.domincipe.common.observability;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

class RequestIdFilterTest {

    private final AtomicReference<String> requestIdSeenByController = new AtomicReference<>();

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new ProbeController(requestIdSeenByController))
                .addFilters(new RequestIdFilter())
                .build();
    }

    @AfterEach
    void clearMdc() {
        MDC.clear();
    }

    @Test
    void reusesTheIncomingRequestId() throws Exception {
        mockMvc.perform(get("/probe").header(RequestIdFilter.HEADER_NAME, "7d1f-abc"))
                .andExpect(status().isOk())
                .andExpect(header().string(RequestIdFilter.HEADER_NAME, "7d1f-abc"));

        assertThat(requestIdSeenByController.get()).isEqualTo("7d1f-abc");
        assertThat(MDC.get(RequestIdFilter.MDC_KEY)).isNull();
    }

    @Test
    void trimsSurroundingWhitespaceOfTheIncomingRequestId() throws Exception {
        mockMvc.perform(get("/probe").header(RequestIdFilter.HEADER_NAME, "  7d1f-abc  "))
                .andExpect(status().isOk())
                .andExpect(header().string(RequestIdFilter.HEADER_NAME, "7d1f-abc"));

        assertThat(requestIdSeenByController.get()).isEqualTo("7d1f-abc");
    }

    @Test
    void generatesARequestIdWhenTheHeaderIsMissing() throws Exception {
        MvcResult first = mockMvc.perform(get("/probe"))
                .andExpect(status().isOk())
                .andReturn();
        String firstRequestId = first.getResponse().getHeader(RequestIdFilter.HEADER_NAME);
        assertThat(firstRequestId).isNotBlank();
        assertThat(requestIdSeenByController.get()).isEqualTo(firstRequestId);

        MvcResult second = mockMvc.perform(get("/probe"))
                .andExpect(status().isOk())
                .andReturn();
        String secondRequestId = second.getResponse().getHeader(RequestIdFilter.HEADER_NAME);
        assertThat(secondRequestId).isNotBlank();
        assertThat(secondRequestId).isNotEqualTo(firstRequestId);
    }

    @Test
    void generatesARequestIdWhenTheHeaderIsBlank() throws Exception {
        mockMvc.perform(get("/probe").header(RequestIdFilter.HEADER_NAME, "   "))
                .andExpect(status().isOk());

        assertThat(requestIdSeenByController.get()).isNotBlank();
    }

    /**
     * Controller that records the MDC value observed while the request is handled, which is
     * where the logging pattern reads it from.
     */
    @RestController
    private static final class ProbeController {

        private final AtomicReference<String> observed;

        private ProbeController(final AtomicReference<String> observed) {
            this.observed = observed;
        }

        @GetMapping("/probe")
        String probe() {
            observed.set(MDC.get(RequestIdFilter.MDC_KEY));
            return "ok";
        }
    }
}
