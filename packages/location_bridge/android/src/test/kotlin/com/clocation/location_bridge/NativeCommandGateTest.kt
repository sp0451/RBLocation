package com.clocation.location_bridge

import org.junit.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class NativeCommandGateTest {
    @Test
    fun stopInvalidatesInflightSetAndBlocksNewSetUntilCleanup() {
        val gate = NativeCommandGate()
        val old = assertNotNull(gate.beginSet("set-a"))
        gate.beginStop()
        assertFalse(gate.isCurrent(old))
        assertNull(gate.beginSet("during-stop"))
        gate.finishStop()
        val fresh = assertNotNull(gate.beginSet("set-b"))
        assertTrue(gate.isCurrent(fresh))
        assertFalse(gate.isCurrent(old))
    }

    @Test
    fun newestPendingSetWins() {
        val gate = NativeCommandGate()
        val first = assertNotNull(gate.beginSet("first"))
        val second = assertNotNull(gate.beginSet("second"))
        assertFalse(gate.isCurrent(first))
        assertTrue(gate.isCurrent(second))
    }

    @Test
    fun coordinatesRejectNonfiniteAndOutOfRangeValues() {
        assertTrue(isValidCoordinate(-90.0, 180.0))
        assertTrue(isValidCoordinate(0.0, 0.0))
        assertFalse(isValidCoordinate(Double.NaN, 0.0))
        assertFalse(isValidCoordinate(0.0, Double.POSITIVE_INFINITY))
        assertFalse(isValidCoordinate(90.0001, 0.0))
        assertFalse(isValidCoordinate(0.0, -180.0001))
    }
}
