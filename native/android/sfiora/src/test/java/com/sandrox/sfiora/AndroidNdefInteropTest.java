package com.sandrox.sfiora;

import static org.junit.Assert.*;

import java.nio.charset.StandardCharsets;
import java.io.InputStreamReader;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.util.Arrays;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class AndroidNdefInteropTest {
    @Test public void publicFactoriesAgreeWithAndroidsIndependentCodec() throws Exception {
        NdefMessage sfiora = new NdefMessage(List.of(
                NdefRecord.text("Hello 标签", "zh-Hans"),
                NdefRecord.uri("https://www.example.com/nfc"),
                NdefRecord.mime("application/octet-stream", new byte[] {0, 1, -1}),
                NdefRecord.external("io.sfiora", "value", new byte[] {42})));
        android.nfc.NdefMessage androidMessage = new android.nfc.NdefMessage(new android.nfc.NdefRecord[] {
                android.nfc.NdefRecord.createTextRecord("zh-Hans", "Hello 标签"),
                android.nfc.NdefRecord.createUri("https://www.example.com/nfc"),
                android.nfc.NdefRecord.createMime("application/octet-stream", new byte[] {0, 1, -1}),
                android.nfc.NdefRecord.createExternal("io.sfiora", "value", new byte[] {42})});
        assertArrayEquals(androidMessage.toByteArray(), sfiora.getSerializedData());
        assertEquals(sfiora, AndroidNdefCodec.fromPlatform(new android.nfc.NdefMessage(sfiora.getSerializedData())));
    }

    @Test public void sharedIosAndAndroidVectorsRoundTripThroughAndroidsCodec() throws Exception {
        try (InputStreamReader reader = new InputStreamReader(
                getClass().getResourceAsStream("/ndef-vectors.json"), StandardCharsets.UTF_8)) {
            JsonObject fixture = JsonParser.parseReader(reader).getAsJsonObject();
            for (String group : List.of("records", "messages")) {
                for (JsonElement element : fixture.getAsJsonArray(group)) {
                    JsonObject value = element.getAsJsonObject();
                    JsonObject expected = group.equals("records") ? value.getAsJsonObject("expected") : value;
                    String hex = expected.get("messageHex").getAsString();
                    byte[] bytes = new byte[hex.length() / 2];
                    for (int index = 0; index < bytes.length; index++) {
                        bytes[index] = (byte) Integer.parseInt(hex.substring(index * 2, index * 2 + 2), 16);
                    }
                    android.nfc.NdefMessage decoded = new android.nfc.NdefMessage(bytes);
                    assertArrayEquals(value.get("name").getAsString(), bytes, decoded.toByteArray());
                    assertArrayEquals(bytes, AndroidNdefCodec.fromPlatform(decoded).getSerializedData());
                }
            }
        }
    }

    @Test public void payloadAndIdentifierBoundariesAgreeWithAndroidSerialization() throws Exception {
        for (int size : new int[] {0, 1, 254, 255, 256, 1024}) {
            for (int idSize : new int[] {0, 1, 255}) {
                byte[] payload = new byte[size]; Arrays.fill(payload, (byte) 0xA5);
                byte[] id = new byte[idSize]; Arrays.fill(id, (byte) 0x42);
                byte[] type = "application/octet-stream".getBytes(StandardCharsets.US_ASCII);
                NdefMessage message = new NdefMessage(List.of(new NdefRecord(
                        NdefTypeNameFormat.MIME_MEDIA, type, id, payload)));
                android.nfc.NdefMessage platform = new android.nfc.NdefMessage(new android.nfc.NdefRecord[] {
                        new android.nfc.NdefRecord(android.nfc.NdefRecord.TNF_MIME_MEDIA, type, id, payload)});
                assertArrayEquals(platform.toByteArray(), message.getSerializedData());
                assertEquals(message, AndroidNdefCodec.fromPlatform(new android.nfc.NdefMessage(message.getSerializedData())));
            }
        }
    }
}
