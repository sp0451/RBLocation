package com.clocation.location_bridge

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

internal class NativeProviderLeaseTest {
    @Test
    fun enableFailureStillReleasesProviderWhoseAddSucceeded() {
        val removed = mutableListOf<String>()
        val lease = NativeProviderLease(listOf("gps", "network"), {},
            { throw SecurityException("permission revoked after add") }, { removed.add(it) })
        assertFailsWith<SecurityException> { lease.acquire() }
        assertEquals(listOf("gps"), lease.providers)
        assertTrue(lease.release().isEmpty())
        assertEquals(listOf("gps"), removed)
        assertTrue(lease.providers.isEmpty())
    }

    @Test
    fun cleanupContinuesAfterFailureAndRetryAcquiresMissingProvider() {
        val removed = mutableListOf<String>()
        val added = mutableListOf<String>()
        var denyGpsRemoval = true
        val lease = NativeProviderLease(listOf("gps", "network"), { added.add(it) }, {}, {
            removed.add(it)
            if (it == "gps" && denyGpsRemoval) throw SecurityException("revoked")
        })
        lease.acquire()
        assertEquals(1, lease.release().size)
        assertEquals(listOf("gps", "network"), removed)
        assertEquals(listOf("gps"), lease.providers)
        lease.acquire()
        assertEquals(listOf("gps", "network", "network"), added)
        assertEquals(listOf("gps", "network"), lease.providers)
        denyGpsRemoval = false
        assertTrue(lease.release().isEmpty())
        assertTrue(lease.providers.isEmpty())
    }

    @Test
    fun freshProcessRecoveryRemovesKnownProvidersWithoutAcquiringThem() {
        val removed = mutableListOf<String>()
        val lease = NativeProviderLease(listOf("gps", "network"),
            { error("Recovery must never install or replay a location") }, {}, { removed.add(it) })
        assertTrue(lease.release(recoverPreviousProcess = true).isEmpty())
        assertEquals(listOf("gps", "network"), removed)
    }

    @Test
    fun uncertainAddIsCleanedEvenWhenCallDidNotReturnToTrackOwnership() {
        val systemProviders = mutableSetOf<String>()
        val lease = NativeProviderLease(listOf("gps", "network"), {
            systemProviders.add(it)
            if (it == "network") throw IllegalStateException("binder reply lost after mutation")
        }, {}, { systemProviders.remove(it) })
        assertFailsWith<IllegalStateException> { lease.acquire() }
        assertEquals(listOf("gps"), lease.providers)
        assertTrue(lease.release(recoverPreviousProcess = true).isEmpty())
        assertTrue(systemProviders.isEmpty())
    }
}
