package com.sandrox.sfiora.bridge;

import java.util.Map;

/** The shared native parser for managed-presentation waits. */
public final class SfioraBridgePresentationOptions {
    private SfioraBridgePresentationOptions() {}

    public static long timeout(Object options) {
        if (!(options instanceof Map)) {
            throw new IllegalArgumentException("waitForPresentationEnd options must be an object");
        }
        Map<?, ?> values = (Map<?, ?>) options;
        for (Object key : values.keySet()) {
            if (!"timeoutMilliseconds".equals(key)) {
                throw new IllegalArgumentException("Unknown presentation wait option: " + key);
            }
        }
        if (!values.containsKey("timeoutMilliseconds")) return 5000;
        Object raw = values.get("timeoutMilliseconds");
        if (!(raw instanceof Number)) {
            throw new IllegalArgumentException("timeoutMilliseconds must be an integer from 1 to 60000");
        }
        double value = ((Number) raw).doubleValue();
        if (!Double.isFinite(value) || value != Math.rint(value) || value < 1 || value > 60000) {
            throw new IllegalArgumentException("timeoutMilliseconds must be an integer from 1 to 60000");
        }
        return (long) value;
    }
}
