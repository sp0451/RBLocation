package com.clocation.location_bridge

/** Tracks each successful mutation so partial setup can be cleaned independently. */
internal class NativeProviderLease(
    private val expectedProviders: List<String>,
    private val add: (String) -> Unit,
    private val enable: (String) -> Unit,
    private val remove: (String) -> Unit,
) {
    private val owned = linkedSetOf<String>()
    val providers: List<String> get() = owned.toList()

    fun acquire() {
        for (provider in expectedProviders) {
            if (provider !in owned) {
                add(provider)
                owned.add(provider)
            }
            enable(provider)
        }
    }

    /** A recovery clear includes known names from a previous process without replaying a set. */
    fun release(recoverPreviousProcess: Boolean = false): List<Exception> {
        val failures = mutableListOf<Exception>()
        val targets = if (recoverPreviousProcess) expectedProviders else providers
        for (provider in targets) {
            try {
                remove(provider)
                owned.remove(provider)
            } catch (failure: Exception) {
                // Keep the failed provider for a subsequent explicit cleanup attempt.
                failures.add(failure)
            }
        }
        return failures
    }
}
