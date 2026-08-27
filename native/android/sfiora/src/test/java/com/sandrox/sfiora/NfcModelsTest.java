package com.sandrox.sfiora;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.io.IOException;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

public final class NfcModelsTest {
    @Test
    public void errorCodesExposeStableBridgeValues() {
        assertEquals("WRITE_VERIFICATION_FAILED", NfcErrorCode
                .WRITE_VERIFICATION_FAILED
                .getValue());
        assertEquals("INVALID_OPTIONS", NfcErrorCode.INVALID_OPTIONS.getValue());
    }

    @Test
    @SuppressWarnings("unchecked")
    public void capabilitiesExposeThePublishedFeatureContract() {
        NfcCapabilities capabilities = new NfcCapabilities(false, true);

        assertFalse(capabilities.isSupported());
        assertFalse(capabilities.isEnabled());
        assertFalse(capabilities.isReaderModeSupported());
        assertTrue(capabilities.getFeatures().contains(NfcFeature.NDEF_INITIALIZE));
        assertTrue(
                ((List<?>) capabilities.toMap().get("features"))
                        .contains("readOnlyType2Probe")
        );
        assertThrows(
                UnsupportedOperationException.class,
                () -> capabilities.toMap().put("enabled", true)
        );
        assertThrows(
                UnsupportedOperationException.class,
                () -> ((List<Object>) capabilities.toMap().get("features"))
                        .set(0, "changed")
        );
    }

    @Test
    public void nativeErrorsRemainBridgeFriendlyAndImmutable() {
        NfcError error = new NfcError(
                NfcErrorCode.READ_FAILED,
                "Unable to read tag",
                true,
                new IOException("connection closed")
        );

        Map<String, Object> value = error.toMap();
        assertEquals("READ_FAILED", value.get("code"));
        assertTrue((Boolean) value.get("recoverable"));
        Map<?, ?> nativeError = (Map<?, ?>) value.get("nativeError");
        assertEquals("IOException", nativeError.get("type"));
        assertEquals("connection closed", nativeError.get("message"));
        assertThrows(
                UnsupportedOperationException.class,
                () -> value.put("code", "changed")
        );
    }

    @Test
    public void snapshotDefensivelyCopiesMutableInputs() {
        byte[] identifier = {0x01, 0x02};
        List<NfcTechnology> technologies = new ArrayList<>();
        technologies.add(NfcTechnology.NFC_A);
        NfcTagSnapshot snapshot = new NfcTagSnapshot(
                identifier,
                technologies,
                NfcNdefStatus.NOT_CHECKED,
                null,
                null,
                123L
        );

        identifier[0] = 0x7F;
        technologies.clear();
        byte[] returnedIdentifier = snapshot.getIdentifier();
        returnedIdentifier[1] = 0x7F;

        assertArrayEquals(new byte[] {0x01, 0x02}, snapshot.getIdentifier());
        assertEquals(
                Collections.singletonList(NfcTechnology.NFC_A),
                snapshot.getTechnologies()
        );
        assertEquals("nfcA", snapshot.getTechnologies().get(0).getValue());
        assertEquals("notChecked", snapshot.getNdefStatus().getValue());
        assertThrows(
                UnsupportedOperationException.class,
                () -> snapshot.getTechnologies().add(NfcTechnology.NDEF)
        );
    }

    @Test
    @SuppressWarnings("unchecked")
    public void completeSnapshotMapIsRecursivelyImmutable() {
        List<Object> warnings = new ArrayList<>();
        warnings.add("initial");
        Map<String, Object> nested = new LinkedHashMap<>();
        nested.put("warnings", warnings);
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("nested", nested);

        NfcTagSnapshot snapshot = NfcTagSnapshot.builder()
                .values(values)
                .discoveredAtEpochMillis(1L)
                .build();
        warnings.add("late");
        nested.put("changed", true);

        Map<?, ?> immutableNested = (Map<?, ?>) snapshot.toMap().get("nested");
        assertEquals(Collections.singletonList("initial"), immutableNested.get("warnings"));
        assertEquals(1, immutableNested.size());
        assertThrows(
                UnsupportedOperationException.class,
                () -> snapshot.toMap().put("platform", "changed")
        );
        assertThrows(
                UnsupportedOperationException.class,
                () -> ((List<Object>) immutableNested.get("warnings")).add("changed")
        );
    }

    @Test
    public void externalTypeMatchesOnlyExactExternalRecord() {
        NdefExternalType marker = new NdefExternalType(
                "example.org",
                "credential"
        );
        NdefRecord matching = NdefRecord.external(
                "example.org",
                "credential",
                new byte[] {0x01}
        );
        NdefRecord other = NdefRecord.external(
                "example.org",
                "other",
                new byte[] {0x01}
        );

        assertTrue(marker.matches(matching));
        assertFalse(marker.matches(other));
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefExternalType("Example.org", "credential")
        );
    }

    @Test
    public void initializationResultKeepsPreserveAndWriteDistinct() {
        NdefExternalType marker = new NdefExternalType("example.org", "sample");
        NdefMessage message = new NdefMessage(Collections.singletonList(
                NdefRecord.external(
                        marker.getDomain(),
                        marker.getType(),
                        new byte[] {0x01}
                )
        ));
        NfcTagSnapshot snapshot = new NfcTagSnapshot(
                null,
                Collections.singletonList(NfcTechnology.NDEF),
                NfcNdefStatus.READ_ONLY,
                128,
                message,
                1L
        );

        NfcInitializationResult preserved = NfcInitializationResult.preserved(
                marker,
                snapshot,
                2L
        );
        NfcInitializationResult initialized = NfcInitializationResult.initialized(
                marker,
                snapshot,
                message,
                3L
        );

        assertEquals(NfcInitializationAction.PRESERVED, preserved.getAction());
        assertNull(preserved.getWrittenMessage());
        assertNull(preserved.getWrittenMessageData());
        assertEquals(0, preserved.getRecordCount());
        assertFalse(preserved.isVerified());
        assertEquals(NfcInitializationAction.INITIALIZED, initialized.getAction());
        assertEquals(message, initialized.getWrittenMessage());
        assertArrayEquals(
                message.getSerializedData(),
                initialized.getWrittenMessageData()
        );
        assertEquals(1, initialized.getRecordCount());
        assertTrue(initialized.isVerified());
    }

    @Test
    public void writeResultKeepsTheVerifiedTypedValues() {
        NdefMessage message = new NdefMessage(Collections.singletonList(
                NdefRecord.text("value", "en")
        ));
        NfcTagSnapshot snapshot = new NfcTagSnapshot(
                null,
                Collections.singletonList(NfcTechnology.NDEF),
                NfcNdefStatus.READ_WRITE,
                128,
                message,
                1L
        );
        NfcWriteResult result = new NfcWriteResult(snapshot, message, 2L);

        assertEquals(snapshot, result.getTag());
        assertEquals(snapshot, result.getTagSnapshot());
        assertEquals(message, result.getMessage());
        assertEquals(message.getByteCount(), result.getBytesWritten());
        assertEquals(1, result.getRecordCount());
        assertEquals(2L, result.getCompletedAtEpochMillis());
        assertTrue(result.isVerified());
    }
}
