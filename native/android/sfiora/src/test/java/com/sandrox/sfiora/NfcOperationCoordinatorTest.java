package com.sandrox.sfiora;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

public final class NfcOperationCoordinatorTest {
    @Test
    public void leaseCannotBeStolenOrReleasedByAnotherLease() {
        NfcOperationCoordinator.Lease read = NfcOperationCoordinator.tryAcquire(
                NfcOperationCoordinator.Kind.READ
        );
        assertNotNull(read);
        assertEquals(NfcOperationCoordinator.Kind.READ, read.getKind());
        assertNull(NfcOperationCoordinator.tryAcquire(
                NfcOperationCoordinator.Kind.WRITE
        ));

        NfcOperationCoordinator.release(read);
        NfcOperationCoordinator.Lease write = NfcOperationCoordinator.tryAcquire(
                NfcOperationCoordinator.Kind.WRITE
        );
        assertNotNull(write);
        NfcOperationCoordinator.release(read);
        assertNull(NfcOperationCoordinator.tryAcquire(
                NfcOperationCoordinator.Kind.READ
        ));
        NfcOperationCoordinator.release(write);
    }
}
