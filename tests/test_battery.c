/*
 * Unit tests for get_battery_percentage().
 *
 * Compiled as plain C (no BPF headers needed) — the function is pure math.
 * Run via: make test
 */
#include <stdio.h>

static const int g733_voltages[]    = {4100, 3950, 3850, 3750, 3650, 3500, 3300, 3150};
static const int g733_percentages[] = {100,  80,   60,   40,   20,   10,   5,    0   };

static int get_battery_percentage(int voltage)
{
    const unsigned int num_points = 8U;

    if (voltage >= g733_voltages[0])
        return 100;
    if (voltage <= g733_voltages[num_points - 1])
        return 0;

    for (unsigned int i = 0U; i < num_points - 1U; i++) {
        int v_high = g733_voltages[i];
        int v_low  = g733_voltages[i + 1U];

        if (voltage >= v_low && voltage <= v_high) {
            unsigned int v_range = (unsigned int)(v_high - v_low);
            if (v_range == 0U)
                return g733_percentages[i];

            int          p_high   = g733_percentages[i];
            int          p_low    = g733_percentages[i + 1U];
            unsigned int p_range  = (unsigned int)(p_high - p_low);
            unsigned int v_offset = (unsigned int)(voltage - v_low);
            return p_low + (int)((v_offset * p_range) / v_range);
        }
    }
    return 0;
}

/* ------------------------------------------------------------------ */

static int failures = 0;

static void check_range(const char *label, int voltage, int lo, int hi)
{
    int result = get_battery_percentage(voltage);
    if (result >= lo && result <= hi) {
        printf("  PASS  %-52s  %dmV → %d%%\n", label, voltage, result);
    } else {
        printf("  FAIL  %-52s  %dmV → %d%% (expected [%d, %d])\n",
               label, voltage, result, lo, hi);
        failures++;
    }
}

static void check(const char *label, int voltage, int expected)
{
    check_range(label, voltage, expected, expected);
}

int main(void)
{
    printf("=== Battery percentage conversion ===\n\n");

    /* Clamping: above and below the calibration range */
    printf("Clamping\n");
    check      ("above max",         4200, 100);
    check      ("exactly max",       4100, 100);
    check      ("exactly min",       3150,   0);
    check      ("below min",         3000,   0);

    /* Exact calibration breakpoints */
    printf("\nCalibration breakpoints\n");
    check      ("3950 mV",           3950,  80);
    check      ("3850 mV",           3850,  60);
    check      ("3750 mV",           3750,  40);
    check      ("3650 mV",           3650,  20);
    check      ("3500 mV",           3500,  10);
    check      ("3300 mV",           3300,   5);

    /* Linear interpolation midpoints (exact integer results) */
    printf("\nLinear interpolation\n");
    /* 4025 mV: segment [3950,4100], v_offset=75, p_range=20, v_range=150 → 80+10=90 */
    check      ("midpoint 4100-3950 → 90%%", 4025,  90);
    /* 3900 mV: segment [3850,3950], v_offset=50, p_range=20, v_range=100 → 60+10=70 */
    check      ("midpoint 3950-3850 → 70%%", 3900,  70);
    /* 3800 mV: segment [3750,3850], v_offset=50, p_range=20, v_range=100 → 40+10=50 */
    check      ("midpoint 3850-3750 → 50%%", 3800,  50);
    /* 3700 mV: segment [3650,3750], v_offset=50, p_range=20, v_range=100 → 20+10=30 */
    check      ("midpoint 3750-3650 → 30%%", 3700,  30);
    /* 3575 mV: segment [3500,3650], v_offset=75, p_range=10, v_range=150 → 10+5=15 */
    check      ("midpoint 3650-3500 → 15%%", 3575,  15);
    /* 3400 mV: segment [3300,3500], v_offset=100, p_range=5, v_range=200 → 5+2=7 */
    check      ("midpoint 3500-3300 → 7%%",  3400,   7);
    /* 3225 mV: segment [3150,3300], v_offset=75, p_range=5, v_range=150 → 0+2=2 */
    check      ("midpoint 3300-3150 → 2%%",  3225,   2);

    /* Near-boundary values (one step inside the range) */
    printf("\nNear-boundary values\n");
    check      ("4099 mV (just below max)",   4099,  99);
    check      ("3151 mV (just above min)",   3151,   0);

    printf("\n%s — %d failure(s)\n",
           failures == 0 ? "ALL PASSED" : "FAILED", failures);
    return failures > 0 ? 1 : 0;
}
