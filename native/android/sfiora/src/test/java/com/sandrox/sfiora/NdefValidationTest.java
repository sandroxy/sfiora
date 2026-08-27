package com.sandrox.sfiora;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class NdefValidationTest {
    @Test
    public void recordOwnsDefensiveCopiesOfEveryByteArray() {
        byte[] type = {0x58};
        byte[] identifier = {0x01};
        byte[] payload = {0x02};
        NdefRecord record = new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                type,
                identifier,
                payload
        );

        type[0] = 0x00;
        identifier[0] = 0x00;
        payload[0] = 0x00;
        assertArrayEquals(new byte[]{0x58}, record.getType());
        assertArrayEquals(new byte[]{0x01}, record.getIdentifier());
        assertArrayEquals(new byte[]{0x02}, record.getPayload());

        byte[] exposed = record.getPayload();
        exposed[0] = 0x7F;
        assertArrayEquals(new byte[]{0x02}, record.getPayload());
    }

    @Test
    public void messageOwnsAnImmutableRecordListAndSerializedBytes() {
        NdefRecord record = NdefRecord.uri("https://example.com");
        List<NdefRecord> source = new ArrayList<>();
        source.add(record);
        NdefMessage message = new NdefMessage(source);
        source.clear();
        assertEquals(List.of(record), message.getRecords());
        assertThrows(
                UnsupportedOperationException.class,
                () -> message.getRecords().clear()
        );

        byte[] serialized = message.getSerializedData();
        byte original = serialized[0];
        serialized[0] = 0;
        assertEquals(original, message.getSerializedData()[0]);
    }

    @Test
    public void modelEqualityIncludesAllRecordBytes() {
        NdefRecord first = NdefRecord.text("one", "en");
        NdefRecord same = NdefRecord.text("one", "en");
        NdefRecord different = NdefRecord.text("two", "en");
        assertEquals(first, same);
        assertEquals(first.hashCode(), same.hashCode());
        assertNotEquals(first, different);
        assertEquals(
                new NdefMessage(List.of(first)),
                new NdefMessage(List.of(same))
        );
    }

    @Test
    public void invalidRecordShapesAreRejected() {
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefRecord(
                        NdefTypeNameFormat.EMPTY,
                        new byte[0],
                        new byte[]{0x01}
                )
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefRecord(
                        NdefTypeNameFormat.WELL_KNOWN,
                        new byte[0],
                        new byte[0]
                )
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefRecord(
                        NdefTypeNameFormat.UNKNOWN,
                        new byte[]{0x58},
                        new byte[0]
                )
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefRecord(
                        NdefTypeNameFormat.WELL_KNOWN,
                        new byte[256],
                        new byte[0]
                )
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefRecord(
                        NdefTypeNameFormat.WELL_KNOWN,
                        new byte[]{0x58},
                        new byte[256],
                        new byte[0]
                )
        );
    }

    @Test
    public void invalidMessagesAndFactoryInputsAreRejected() {
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefMessage(Collections.emptyList())
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> new NdefMessage(Arrays.asList((NdefRecord) null))
        );
        for (String languageCode : Arrays.asList(
                "",
                "-en",
                "en-",
                "en--US",
                "中文"
        )) {
            assertThrows(
                    languageCode,
                    IllegalArgumentException.class,
                    () -> NdefRecord.text("text", languageCode)
            );
        }
        assertThrows(
                IllegalArgumentException.class,
                () -> NdefRecord.uri("")
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NdefRecord.mime("invalid", new byte[0])
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NdefRecord.external(
                        "Example.org",
                        "sample",
                        new byte[0]
                )
        );
    }

    @Test
    public void malformedConveniencePayloadsDoNotProduceGuessedValues() {
        NdefRecord reservedTextStatus = new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                new byte[]{0x54},
                new byte[]{0x40}
        );
        assertNull(reservedTextStatus.getDecodedText());

        NdefRecord malformedUtf8Text = new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                new byte[]{0x54},
                new byte[]{0x02, 0x65, 0x6E, (byte) 0xC3, 0x28}
        );
        assertNull(malformedUtf8Text.getDecodedText());

        NdefRecord unknownUriPrefix = new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                new byte[]{0x55},
                new byte[]{(byte) 0xFF}
        );
        assertNull(unknownUriPrefix.getDecodedUri());

        NdefRecord invalidMime = new NdefRecord(
                NdefTypeNameFormat.MIME_MEDIA,
                "not a/type".getBytes(StandardCharsets.US_ASCII),
                new byte[0]
        );
        assertNull(invalidMime.getMediaType());
    }

    @Test
    public void decodersPreserveValidNonCanonicalWireValues() {
        NdefRecord textWithoutLanguage = new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                new byte[]{0x54},
                new byte[]{0x00, 0x41}
        );
        assertNotNull(textWithoutLanguage.getDecodedText());
        assertEquals("", textWithoutLanguage.getDecodedText().getLanguageCode());
        assertEquals("A", textWithoutLanguage.getDecodedText().getText());

        NdefRecord mixedCaseExternalType = new NdefRecord(
                NdefTypeNameFormat.EXTERNAL_TYPE,
                "Example.ORG:Member".getBytes(StandardCharsets.US_ASCII),
                new byte[0]
        );
        assertEquals(
                "Example.ORG:Member",
                mixedCaseExternalType.getExternalType()
        );
    }

    @Test
    public void utf16DecoderHonorsAnExplicitByteOrderMark() {
        assertEquals(
                NdefTextEncoding.UTF_16,
                NdefRecord.text("A", "en", NdefTextEncoding.UTF_16)
                        .getDecodedText()
                        .getEncoding()
        );

        NdefRecord littleEndianText = new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                new byte[]{0x54},
                new byte[]{
                        (byte) 0x82,
                        0x65,
                        0x6E,
                        (byte) 0xFF,
                        (byte) 0xFE,
                        0x41,
                        0x00
                }
        );
        NdefText decoded = littleEndianText.getDecodedText();
        assertNotNull(decoded);
        assertEquals("A", decoded.getText());
        assertEquals(NdefTextEncoding.UTF_16, decoded.getEncoding());
    }

    @Test
    public void externalTypesFollowTheNfcForumAsciiShape() {
        NdefRecord valid = NdefRecord.external(
                "example.org",
                "member_status+v1",
                new byte[0]
        );
        assertEquals("example.org:member_status+v1", valid.getExternalType());

        for (String domain : Arrays.asList(
                ".example.org",
                "example..org",
                "-example.org",
                "example-.org"
        )) {
            assertThrows(
                    domain,
                    IllegalArgumentException.class,
                    () -> NdefRecord.external(domain, "member", new byte[0])
            );
        }
        assertThrows(
                IllegalArgumentException.class,
                () -> NdefRecord.external(
                        "example.org",
                        "member:type",
                        new byte[0]
                )
        );
    }
}
