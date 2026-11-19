package com.clocation.location_bridge

/** Used only from the native main queue, including foreground-service callbacks. */
internal class NativeCommandGate {
    data class Ticket(val generation: Long, val operationId: String)

    var generation: Long = 0
        private set
    var isStopping: Boolean = false
        private set
    private var current: Ticket? = null

    fun beginSet(operationId: String): Ticket? {
        if (isStopping) return null
        return Ticket(generation, operationId).also { current = it }
    }

    fun isCurrent(ticket: Ticket): Boolean = !isStopping && current == ticket

    fun beginStop() {
        isStopping = true
        generation += 1
        current = null
    }

    fun finishStop() {
        isStopping = false
    }
}

internal fun isValidCoordinate(latitude: Double, longitude: Double): Boolean =
    latitude.isFinite() && longitude.isFinite() &&
        latitude in -90.0..90.0 && longitude in -180.0..180.0
