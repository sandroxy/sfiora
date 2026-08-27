package com.sandrox.sfiora;

import android.content.Context;
import android.nfc.NfcAdapter;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Device-level NFC availability. */
public final class NfcCapabilities {
    private static final List<NfcFeature> FEATURES = Collections.unmodifiableList(
            Arrays.asList(
                    NfcFeature.DISCOVER,
                    NfcFeature.NDEF,
                    NfcFeature.NDEF_WRITE,
                    NfcFeature.NDEF_INITIALIZE,
                    NfcFeature.READ_ONLY_MIFARE_ULTRALIGHT_PROBE,
                    NfcFeature.READ_ONLY_TYPE_2_PROBE,
                    NfcFeature.READ_ONLY_MIFARE_CLASSIC_DEFAULT_KEY_PROBE
            )
    );
    private static final List<String> FEATURE_VALUES = featureValues();

    private final boolean supported;
    private final boolean enabled;

    public NfcCapabilities(boolean supported, boolean enabled) {
        this.supported = supported;
        this.enabled = supported && enabled;
    }

    public boolean isSupported() {
        return supported;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public boolean isReaderModeSupported() {
        return supported;
    }

    public List<NfcFeature> getFeatures() {
        return FEATURES;
    }

    public static NfcCapabilities from(Context context) {
        if (context == null) {
            return new NfcCapabilities(false, false);
        }
        NfcAdapter adapter = NfcAdapter.getDefaultAdapter(
                context.getApplicationContext()
        );
        return new NfcCapabilities(
                adapter != null,
                adapter != null && adapter.isEnabled()
        );
    }

    /** Returns an immutable-shape value suitable for JS bridge conversion. */
    public Map<String, Object> toMap() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("platform", "android");
        result.put("supported", supported);
        result.put("enabled", enabled);
        result.put("readerModeSupported", supported);
        result.put("features", FEATURE_VALUES);
        return Collections.unmodifiableMap(result);
    }

    private static List<String> featureValues() {
        String[] result = new String[FEATURES.size()];
        for (int index = 0; index < FEATURES.size(); index++) {
            result[index] = FEATURES.get(index).getValue();
        }
        return Collections.unmodifiableList(Arrays.asList(result));
    }
}
