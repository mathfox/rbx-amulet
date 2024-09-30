import type { CleanupCallback } from "./types";

/**
 * Runs the given callback immediately and whenever any atom it depends on changes.
 * Returns a cleanup function that unsubscribes the callback.
 *
 * @param callback The function to run.
 * @returns A function that unsubscribes the callback.
 */
declare function effect(callback: (() => CleanupCallback) | (() => void)): CleanupCallback;

export = effect;
