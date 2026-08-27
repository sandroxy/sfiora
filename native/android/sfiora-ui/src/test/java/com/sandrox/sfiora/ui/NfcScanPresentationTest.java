package com.sandrox.sfiora.ui;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

public final class NfcScanPresentationTest {
    @Test
    public void absentPresentationUsesManagedPanel() {
        assertEquals(
                NfcScanPresentation.MANAGED,
                NfcScanPresentation.fromBridgeValue(null)
        );
    }

    @Test
    public void exactBridgeValuesAreParsed() {
        assertEquals(
                NfcScanPresentation.NONE,
                NfcScanPresentation.fromBridgeValue("none")
        );
    }

    @Test
    public void normalizedAndUnknownPresentationsAreRejected() {
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcScanPresentation.fromBridgeValue(" NONE ")
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcScanPresentation.fromBridgeValue("Managed")
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NfcScanPresentation.fromBridgeValue("custom")
        );
    }
}
