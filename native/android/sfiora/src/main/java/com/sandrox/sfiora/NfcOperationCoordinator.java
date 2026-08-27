package com.sandrox.sfiora;

import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

/** Serializes NFC read and write sessions in the current process. */
final class NfcOperationCoordinator {
    enum Kind {
        READ,
        WRITE
    }

    static final class Lease {
        private final UUID identifier;
        private final Kind kind;

        private Lease(Kind kind) {
            identifier = UUID.randomUUID();
            this.kind = kind;
        }

        Kind getKind() {
            return kind;
        }
    }

    private static final AtomicReference<Lease> ACTIVE =
            new AtomicReference<>();

    private NfcOperationCoordinator() {
    }

    static Lease tryAcquire(Kind kind) {
        Lease lease = new Lease(Objects.requireNonNull(kind, "kind is required"));
        return ACTIVE.compareAndSet(null, lease) ? lease : null;
    }

    static void release(Lease lease) {
        if (lease != null) {
            ACTIVE.compareAndSet(lease, null);
        }
    }
}
