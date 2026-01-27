package com.minishop.order;

import java.util.concurrent.atomic.AtomicLong;

public final class WorkSimulator {
    private static final AtomicLong COUNTER = new AtomicLong();
    private static volatile long SINK = 0;

    private WorkSimulator() {}

    public static void burnCpuMs(long ms) {
        if (ms <= 0) return;

        long end = System.nanoTime() + ms * 1_000_000L;
        long x = 0;
        while (System.nanoTime() < end) {
            x ^= (x << 1) + 0x9e3779b97f4a7c15L;
        }
        SINK = x;
    }

    public static void maybeAddTail(int every, long extraMs) {
        if (every <= 0 || extraMs <= 0) return;

        long n = COUNTER.incrementAndGet();
        if (n % every == 0) {
            burnCpuMs(extraMs);
        }
    }
}
