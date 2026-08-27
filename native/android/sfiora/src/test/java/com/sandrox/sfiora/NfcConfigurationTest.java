package com.sandrox.sfiora;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

public final class NfcConfigurationTest {
    @Test
    public void readConfigurationUsesStableDefaults() {
        NfcReadConfiguration configuration = NfcReadConfiguration.builder().build();

        assertEquals(NfcReadMode.AUTOMATIC, configuration.getMode());
        assertEquals("automatic", configuration.getMode().getValue());
        assertEquals(30_000L, configuration.getTimeoutMillis());
        assertFalse(configuration.isDeepReadEnabled());
        assertEquals(250, configuration.getPresenceCheckDelayMillis());
    }

    @Test
    public void readOnlyDiagnosticsAreExplicitlyOptIn() {
        NfcReadConfiguration configuration = NfcReadConfiguration.builder()
                .deepReadEnabled(true)
                .build();

        assertTrue(configuration.isDeepReadEnabled());
    }

    @Test
    public void readConfigurationRejectsInvalidBounds() {
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcReadConfiguration.builder().timeoutMillis(999L).build()
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcReadConfiguration.builder()
                        .presenceCheckDelayMillis(5_001)
                        .build()
        );
    }

    @Test
    public void writeConfigurationRejectsInvalidBounds() {
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcWriteConfiguration.builder()
                        .timeoutMillis(60_001L)
                        .build()
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcWriteConfiguration.builder()
                        .presenceCheckDelayMillis(49)
                        .build()
        );
    }
}
