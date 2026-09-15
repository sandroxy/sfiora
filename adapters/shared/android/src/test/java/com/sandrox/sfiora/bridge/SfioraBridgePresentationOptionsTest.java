package com.sandrox.sfiora.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import java.util.Collections;
import java.util.Map;
import org.junit.Test;

public class SfioraBridgePresentationOptionsTest {
    @Test public void acceptsBoundedIntegerTimeoutsAndDefaults() {
        assertEquals(5000, SfioraBridgePresentationOptions.timeout(Collections.emptyMap()));
        for (Number value : new Number[] {1, 5000.0, 60000L}) {
            assertEquals(value.longValue(), SfioraBridgePresentationOptions.timeout(Map.of("timeoutMilliseconds", value)));
        }
    }

    @Test public void rejectsMalformedValuesAndUnknownFields() {
        assertThrows(IllegalArgumentException.class, () -> SfioraBridgePresentationOptions.timeout(null));
        assertThrows(IllegalArgumentException.class, () -> SfioraBridgePresentationOptions.timeout("5000"));
        assertThrows(IllegalArgumentException.class, () -> SfioraBridgePresentationOptions.timeout(Map.of("unknown", 1)));
        for (Object value : new Object[] {null, "100", true, 0, -1, 1.5, 60001, Double.NaN, Double.POSITIVE_INFINITY}) {
            assertThrows(IllegalArgumentException.class,
                    () -> SfioraBridgePresentationOptions.timeout(Collections.singletonMap("timeoutMilliseconds", value)));
        }
    }
}
