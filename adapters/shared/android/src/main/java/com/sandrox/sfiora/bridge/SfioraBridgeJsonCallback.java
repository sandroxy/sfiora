package com.sandrox.sfiora.bridge;

/** JSON result boundary usable from UTS without DCloud types. */
public interface SfioraBridgeJsonCallback {
    void onResult(String envelopeJson);
}
