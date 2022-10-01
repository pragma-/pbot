/* for standalone usage, compile with: cc -Os -Wall -Wextra -Wshadow -march=native qrpn.c -lm -o qrpn */

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE
#include "qrpn.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <time.h>
#include <float.h>
#include <complex.h>
#include <limits.h>

/* begin simple math functions we want to expose via the interpreter */

static double crd(const double theta) {
    return 2.0 * sin(theta / 2.0);
}

static double hav(const double theta) {
    const double a = sin(theta / 2.0);
    return a * a;
}

static double ahav(const double x) {
    return 2.0 * asin(sqrt(x));
}

static double acrd(const double x) {
    return 2.0 * asin(x * 0.5);
}

static double versine(const double x) {
    return (fabs(x) > M_PI * 0.125) ? (2.0 * sin(x * 0.5)) : (1.0 - cos(x));
}

static double exsecant(const double x) {
    return versine(x) / cos(x);
}

static double arcexsecant(const double x) {
    return atan(sqrt(x * x + x * 2.0));
}

static double tenlog(double x) {
    return 10.0 * log10(x);
}

static double itenlog(double x) {
    return pow(10.0, x * 0.1);
}

static double complex cpow_checked(const double complex a, const double complex b) {
    /* cpow() cannot be trusted to have as much precision as pow() even for integer arguments that fit in 32 bits */

    if (!cimag(a) && !cimag(b)) {
        const double ar = creal(a), br = creal(b);
        if (rint(br) == br) return __builtin_powi(ar, br);
        else return pow(ar, br);
    }
    else return cpow(a, b);
}

static unsigned long long gcd(unsigned long long a, unsigned long long b) {
    while (b) {
        const unsigned long long t = b;
        b = a % b;
        a = t;
    }

    return a;
}

static unsigned long long nchoosek(const unsigned long long n, const unsigned long long k) {
    if (k > n - k) return nchoosek(n, n - k);

    unsigned long long n_choose_k = 1;
    for (size_t kr = 1; kr <= k; kr++)
        n_choose_k = (n_choose_k * (n + 1 - kr)) / kr;

    return n_choose_k;
}

static unsigned long long ceil_isqrt(unsigned long long n) {
    unsigned long long this = n / 2;
    if (!this) return n;

    for (unsigned long long next = this; (next = (this + n / this) / 2) < this; this = next);

    return this * this < n ? this + 1 : this;
}

static int isprime(const unsigned long long n) {
    if (2 == n) return 1;
    else if (1 == n || !(n % 2)) return 0;

    const unsigned long long stop = ceil_isqrt(n);

    for (unsigned long long m = 3; m < stop; m += 2)
        if (!(n % m)) return 0;

    return 1;
}
/* end simple math functions */

struct named_quantity {
    double value;
    int8_t units[BASEUNITS]; /* metre, kilogram, second, ampere, kelvin, candela, mol */
    uint8_t flags;
    char * name;
    char * abrv;
    char * alt_spelling;
};

struct si_prefix {
    double scale;
    char * name;
    char * abrv;
};

static const struct si_prefix si_prefixes[] = {
    { 1e-24, "yocto", "y", },
    { 1e-21, "zepto", "z", },
    { 1e-18, "atto", "a", },
    { 1e-15, "femto", "f", },
    { 1e-12, "pico", "p", },
    { 1e-9, "nano", "n" },
    { 1e-6, "micro", "u" },
    { 1e-3, "milli", "m" },
    { 1e-2, "centi", "c" },
    { 1e-1, "deci", "d" },
    { 1e2, "hecto", "h" },
    { 1e3, "kilo", "k" },
    { 1e6, "mega", "M" },
    { 1e9, "giga", "G" },
    { 1e12, "tera", "T" },
    { 1e15, "peta", "P" },
    { 1e18, "exa", "E" },
    { 1e21, "zetta", "Z" },
    { 1e24, "yotta", "Y" },
    { 1e27, "hella", "H" }
};

static const int8_t units_of_time[BASEUNITS] = { 0, 0, 1, 0, 0, 0, 0 };
static const int8_t dimensionless[BASEUNITS] = { 0, 0, 0, 0, 0, 0, 0 };

#define FLAG_UNIT_ENTERS_AS_OPERAND 1
#define FLAG_SI_BASE_UNIT 4
#define FLAG_SI_DERIVED_UNIT 8

static const struct named_quantity named_quantities[] = {
    /* si base units */
    { .value = 1.0, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "metre", .abrv = "m", .flags = FLAG_SI_BASE_UNIT, .alt_spelling = "meter" },
    { .value = 1.0, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "kilogram", .abrv = "kg", .flags = FLAG_SI_BASE_UNIT },
    { .value = 1.0, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "second", .abrv = "s", .flags = FLAG_SI_BASE_UNIT },
    { .value = 1.0, .units = { 0, 0, 0, 1, 0, 0, 0 }, .name = "ampere", .abrv = "A", .flags = FLAG_SI_BASE_UNIT },
    { .value = 1.0, .units = { 0, 0, 0, 0, 1, 0, 0 }, .name = "kelvin", .abrv = "K", .flags = FLAG_SI_BASE_UNIT },
    { .value = 1.0, .units = { 0, 0, 0, 0, 0, 1, 0 }, .name = "candela", .abrv = "Cd", .flags = FLAG_SI_BASE_UNIT },
    { .value = 1.0, .units = { 0, 0, 0, 0, 0, 0, 1 }, .name = "mole", .abrv = "mol", .flags = FLAG_SI_BASE_UNIT },

    /* si derived units */
    { .value = 1.0, .units = { 0, 0, -1, 0, 0, 0, 0 }, .name = "hertz", .abrv = "Hz", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 1, 1, -2, 0, 0, 0, 0 }, .name = "newton", .abrv = "N", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { -1, 1, -2, 0, 0, 0, 0 }, .name = "pascal", .abrv = "Pa", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 2, 1, -2, 0, 0, 0, 0 }, .name = "joule", .abrv = "J", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 2, 1, -3, 0, 0, 0, 0 }, .name = "watt", .abrv = "W", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 0, 0, 1, 1, 0, 0, 0 }, .name = "coulomb", .abrv = "C", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 2, 1, -3, -1, 0, 0, 0 }, .name = "volt", .abrv = "V", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { -2, -1, 4, 2, 0, 0, 0 }, .name = "farad", .abrv = "F", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 2, 1, -3, -2, 0, 0, 0 }, .name = "ohm", .abrv = "ohm", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { -2, -1, 3, 2, 0, 0, 0 }, .name = "siemens", .abrv = "S", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 2, 1, -2, -1, 0, 0, 0 }, .name = "weber", .abrv = "Wb", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 0, 1, -2, -1, 0, 0, 0 }, .name = "tesla", .abrv = "T", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 2, 1, -2, -2, 0, 0, 0 }, .name = "henry", .abrv = "H", .flags = FLAG_SI_DERIVED_UNIT },
    { .value = 1.0, .units = { 0, 0, -1, 0, 0, 0, 1 }, .name = "katal", .abrv = "kat", .flags = FLAG_SI_DERIVED_UNIT },

    { .value = 1.0, .units = { -2, 1, -1, 0, 0, 0, 0 }, .name = "rayl" },

    /* todo keep the print thing from displaying these */
//    { .value = 1.0, .units = { 0, 0, -1, 0, 0, 0, 0 }, .name = "becquerel", .abrv = "Bq" },
//    { .value = 1.0, .units = { 2, 0, -2, 0, 0, 0, 0 }, .name = "gray", .abrv = "Gy" },

    { .value = 100e3, { -1, 1, -2, 0, 0, 0, 0 }, .name = "bar" },

    { .value = 60.0, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "minute", .abrv = "min" },
    { .value = 3600.0, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "hour", .abrv = "h" },
    { .value = 86400.0, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "day" },
    { .value = 1209600.0, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "fortnight" },

    { .value = 1.0e-15, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "fermi", },
    { .value = 1.0e-6, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "micron", },
    { .value = 1.0e-28, .units = { 2, 0, 0, 0, 0, 0, 0 }, .name = "barn", .abrv = "b", },
    { .value = 1e-3, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "gram", .abrv = "gm" },

    { .value = 1e3, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "tonne", .abrv = "t", .alt_spelling = "ton" },
    { .value = 1e-3, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "litre", .abrv = "L" },
    { .value = 1e-6, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "cc" },
    { .value = 10e3, .units = { 2, 0, 0, 0, 0, 0, 0 }, .name = "hectare", .abrv = "ha" },
    { .value = 3600.0, .units = { 2, 1, -2, 0, 0, 0, 0 }, .abrv = "Wh" },
    { .value = 3600.0, .units = { 0, 0, 1, 1, 0, 0, 0 }, .abrv = "Ah" },
    { .value = 1.0e-2, .units = { 2, 0, -2, 0, 0, 0, 0 }, .name = "rad" },
    { .value = 10e-6, .units = { 1, 1, -2, 0, 0, 0, 0 }, .name = "dyne" },

    { .value = 3.7e10, .units = { 0, 0, -1, 0, 0, 0, 0 }, .name = "curie", .abrv = "Ci" },

    { .value = 4.92892159375e-6, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "teaspoon", .abrv = "tsp" },
    { .value = 14.78676478125e-6, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "tablespoon", .abrv = "Tbsp" },
    { .value = 29.5735295625e-6, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "floz" },
    { .value = 236.5882365e-6, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "cup" },
    { .value = 473.176473e-6, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "pint" },
    { .value = 0.946352946e-3, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "quart" },
    { .value = 3.785411784e-3, .units = { 3, 0, 0, 0, 0, 0, 0 }, .name = "gallon" },

    { .value = 1.60217657e-19, .units = { 2, 1, -2, 0, 0, 0, 0 }, .abrv = "eV" },

    { .value = 4046.8564224, .units = { 2, 0, 0, 0, 0, 0, 0 }, .name = "acre" },
    { .value = 4.184, .units = { 2, 1, -2, 0, 0, 0, 0 }, .name = "calorie", .abrv = "cal" },
    { .value = 4.184e3, .units = { 2, 1, -2, 0, 0, 0, 0 }, .abrv = "Cal" },
    { .value = 4.184e6, .units = { 2, 0, -2, 0, 0, 0, 0 }, .name = "TNT" },
    { .value = 1852.0, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "nmi" },
    { .value = 0.514444444, .units = { 1, 0, -1, 0, 0, 0, 0 }, .name = "knot", .abrv = "kt", },
    { .value = 1609.344, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "mile" },
    { .value = 1609.344 / 3600, .units = { 1, 0, -1, 0, 0, 0, 0 }, .abrv = "mph" },
    { .value = 86400.0 * 365.2425, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "year", .abrv = "a" },
    { .value = 1852.0 * 3, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "league" },
    { .value = 9.8066, .units = { 1, 0, -2, 0, 0, 0, 0 }, .name = "g" },
    { .value = 0.01, .units = { 1, 0, -2, 0, 0, 0, 0 }, .name = "gal", .abrv = "Gal" },

    { .value = 1.3806488e-23, .units = { 2, 1, -2, 0, -1, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "Boltzmann", .abrv = "k" },
    { .value = 6371000, .units = { 1, 0, 0, 0, 0, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "Earth radius", .abrv = "Re" },

    { .value = 6.02214129e23, .units = { 0, 0, 0, 0, 0, 0, -1 }, .name = "avogadro" },

    { .value = 6.6738480e-11, .units = { 3, -1, -2, 0, 0, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "G" },
    { .value = 5.97219e24, .units = { 0, 1, 0, 0, 0, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "Me" },

    { .value = 8.3144621, .units = { 2, 1, -2, 0, -1, 0, -1 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "Rc" },
    { .value = 299792458.0, .units = { 1, 0, -1, 0, 0, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "c", .abrv = "c0" },
    { .value = 1.3806488e-23, .units = { 2, 1, -2, 0, -1, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "Bc" },
    { .value = 8.854187817620e-12, .units = { -3, -1, 4, 2, 0, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "e0" },
    { .value = 4.0e-7 * M_PI, .units = { 1, 1, -2, -2, 0, 0, 0 }, .flags = FLAG_UNIT_ENTERS_AS_OPERAND, .name = "u0" },

    { .value = 20.779e9, .units = { 2, 0, 0, 0, 0, 0, 0 }, .name = "Wales" },

    { .value = 0.0283495, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "ounce", .abrv = "oz" },
    { .value = 0.0311034768, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "troyoz" },
    { .value = 64.79891e-6, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "grain" },
    { .value = 101.325e3, .units = { -1, 1, -2, 0, 0, 0, 0 }, .name = "atmosphere", .abrv = "atm" },
    { .value = 745.699872, .units = { 2, 1, -3, 0, 0, 0, 0 }, .name = "horsepower", .abrv = "hp" },
    { .value = 0.3048 * 6.0, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "fathom" },

    { .value = 0.0254, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "inch", .abrv = "in" },
    { .value = 0.3048, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "foot", .abrv = "ft" },
    { .value = 0.9144, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "yard", .abrv = "yd" },
    { .value = 201.168, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "furlong" },
    { .value = 3.08567758e16, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "parsec", .abrv = "pc" },

    { .value = 0.45359237, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "lbm" },
    { .value = 4.448222, .units = { 1, 1, -2, 0, 0, 0, 0 }, .name = "lbf" },
    { .value = 6.35029318, .units = { 0, 1, 0, 0, 0, 0, 0 }, .name = "stone", .abrv = "st" },
};

static const size_t named_quantity_count = sizeof(named_quantities) / sizeof(named_quantities[0]);

static int units_are_power_of(const struct quantity * const test, const struct named_quantity * const base) {
    int exponent = 0;
    for (size_t iu = 0; iu < BASEUNITS; iu++)
        if (test->units[iu] && base->units[iu]) {
            exponent = test->units[iu] / base->units[iu];
            break;
        }
    if (!exponent) return 0;

    for (size_t iu = 0; iu < BASEUNITS; iu++)
        if (test->units[iu] != base->units[iu] * exponent) return 0;

    return exponent;
}

static int units_are_equivalent(const int8_t a[BASEUNITS], const int8_t b[BASEUNITS]) {
    return !memcmp(a, b, sizeof(int8_t[BASEUNITS]));
}

static int units_are_dimensionless(const int8_t in[BASEUNITS]) {
    return !memcmp(in, dimensionless, sizeof(int8_t[BASEUNITS]));
}

static double datestr_to_unix_seconds(const char * const datestr) {
    int64_t seconds = 0, microseconds_after_decimal = 0;

    if (strchr(datestr, 'T') && strchr(datestr, 'Z')) {
        /* if input is a date string */
        struct tm unixtime_struct = { 0 };

        /* if input has colons and dashes, and a subsecond portion... */
        if (strchr(datestr, '-') && strchr(datestr, ':') && strchr(datestr, '.')) {
            const uint64_t microseconds_remainder_with_integer = strtod(datestr + 18, NULL) * 1000000;
            microseconds_after_decimal = microseconds_remainder_with_integer % 1000000;
            strptime(datestr, "%Y-%m-%dT%H:%M:%S.", &unixtime_struct);
        }
        /* if input has colons and dashes */
        else if (strchr(datestr, '-') && strchr(datestr, ':')) strptime(datestr, "%Y-%m-%dT%H:%M:%SZ", &unixtime_struct);
        /* if input has a subsecond portion */
        else if (strchr(datestr, '.')) {
            const uint64_t microseconds_remainder_with_integer = strtod(datestr + 14, NULL) * 1000000;
            microseconds_after_decimal = microseconds_remainder_with_integer % 1000000;
            strptime(datestr, "%Y%m%dT%H%M%S.", &unixtime_struct);
        }
        else
            strptime(datestr, "%Y%m%dT%H%M%SZ", &unixtime_struct);

        seconds = timegm(&unixtime_struct);
    } else {
        /* otherwise, input is a number */
        char * after = NULL;
        microseconds_after_decimal = llrint(strtod(datestr, &after) * 1000000);
        if (after && *after != '\0')
            fprintf(stderr, "warning: %s: ignoring \"%s\"\n", __func__, after);
    }

    return (seconds * 1000000 + microseconds_after_decimal) * 1e-6;
}

static int evaluate_unit(struct quantity stack[static QRPN_STACK_SIZE_MAX], int S, const char * const token, const int exponent_sign) {
    const char * slash = strchr(token, '/');
    if (slash && exponent_sign < 0) return QRPN_ERROR_TOKEN_UNRECOGNIZED;

    const char * const carat = strrchr(token, '^');
    const size_t bytes_before_carat = carat ? (size_t)(carat - token) : (slash ?  (size_t)(slash - token) : strlen(token));
    const long long unit_exponent = exponent_sign * (carat ? strtoll(carat + 1, NULL, 10) : 1);

    const struct named_quantity * quantity = NULL;
    const struct si_prefix * prefix = NULL;

    /* loop over all known units and prefixes looking for a match */
    for (const struct named_quantity * possible_quantity = named_quantities; !quantity && possible_quantity < named_quantities + named_quantity_count; possible_quantity++)
    /* loop over [full name, abbreviation, alt spelling] of each unit. this is a bit of a mess */
        for (int ipass = 0; !quantity && ipass < 3; ipass++) {
            const char * const unit_name = 2 == ipass ? possible_quantity->alt_spelling : 1 == ipass ? possible_quantity->abrv : possible_quantity->name;
            if (!unit_name) continue;

            /* get number of bytes in unit name because we're gonna need it many times */
            const size_t unit_len = strlen(unit_name);

            if (bytes_before_carat < unit_len || memcmp(token + bytes_before_carat - unit_len, unit_name, unit_len)) continue;

            const size_t bytes_before_unit = bytes_before_carat - unit_len;

            prefix = NULL;

            /* loop over known si prefixes */
            for (const struct si_prefix * possible_prefix = si_prefixes; !prefix && possible_prefix < si_prefixes + sizeof(si_prefixes) / sizeof(si_prefixes[0]); possible_prefix++) {
                /* if looking for SI unit abbreviations, admit SI prefix abbreviations */
                const char * const prefix_name = 1 == ipass ? possible_prefix->abrv : possible_prefix->name;
                const size_t prefix_len = prefix_name ? strlen(prefix_name) : 0;

                if (bytes_before_unit == prefix_len && !memcmp(token, prefix_name, bytes_before_unit))
                    prefix = possible_prefix;
            }

            /* if there were bytes before the unit but they didn't match any known prefix, then dont treat as a unit */
            if (!bytes_before_unit || prefix)
                quantity = possible_quantity;
        }

    /* not finding anything above is only an error if there was both a numerator and denominator */
    if (!quantity) return QRPN_ERROR_TOKEN_UNRECOGNIZED;

    if (quantity->flags & FLAG_UNIT_ENTERS_AS_OPERAND) {
        if (S >= QRPN_STACK_SIZE_MAX) return QRPN_ERROR_TOO_MUCH_STACK;
        S++;
        stack[S - 1] = (struct quantity) { .value = 1 };
    }

    if (!S) return QRPN_ERROR_NOT_ENOUGH_STACK;

    int units_out[BASEUNITS];
    for (size_t iu = 0; iu < BASEUNITS; iu++) {
        units_out[iu] = (int8_t)(stack[S - 1].units[iu] + quantity->units[iu] * unit_exponent);
        if (units_out[iu] > INT8_MAX || units_out[iu] < INT8_MIN) return QRPN_ERROR_DIMENSION_OVERFLOW;
    }

    for (size_t iu = 0; iu < BASEUNITS; iu++)
        stack[S - 1].units[iu] = units_out[iu];

    stack[S - 1].value *= pow(prefix ? prefix->scale * quantity->value : quantity->value, unit_exponent);

    if (slash) return evaluate_unit(stack, S, slash + 1, -exponent_sign);
    else return S;
}

static int evaluate_literal(struct quantity * stack, int S, const char * const token) {
    struct quantity tmp = { 0 };

    char * endptr = NULL;
    const double dv = strtod(token, &endptr);

    /* check for special things or units if endptr doesn't move OR if the first character is not number-like (necessary to differentiate "nan" from "nano*") */
    if (endptr == token || token[0] >= 'A') {
        if (!strcmp(token, "pi"))
            tmp.value = M_PI;
        else if (!strcmp(token, "-pi"))
            tmp.value = -M_PI;
        else if (!strcmp(token, "i"))
            tmp.value = I;
        else if (!strcmp(token, "-i"))
            tmp.value = -I;
        else if (!strcmp(token, "nan"))
            tmp.value = NAN;
        else return evaluate_unit(stack, S, token, 1);
    } else {
        /* otherwise, token was not a unit name, parse it as a simple literal */
        double d = 0, m = 0, s = 0;

        if (strpbrk(token + 1, "d°") && sscanf(token, "%lf%*[d°]%lf%*[m']%lf%*[s\"]", &d, &m, &s))
            tmp.value = copysign(fabs(d) + m / 60.0 + s / 3600.0, d) * M_PI / 180.0;
        else if (strpbrk(token, "T") && strpbrk(token, "Z")) {
            tmp.value = datestr_to_unix_seconds(token);
            tmp.units[2] = 1;
        }
        else {
            tmp.value = dv;

            if (!strcmp(endptr, "i"))
                tmp.value *= I;
            else if (endptr == token)
                return evaluate_unit(stack, S, token, 1);
            else if (endptr[0] != '\0' && endptr[1] == '\0') {
                double prefix_scale = 1.0;
                /* only allow k, M, G to be used in this position */
                if ('k' == endptr[0]) prefix_scale = 1e3;
                else if ('M' == endptr[0]) prefix_scale = 1e6;
                else if ('G' == endptr[0]) prefix_scale = 1e9;

                /* special case: trailing 'f' from floating point literals copied and pasted from C code should be ignored */
                else if ('f' == endptr[0]) prefix_scale = 1.0;
                else return QRPN_ERROR_TOKEN_UNRECOGNIZED;

                tmp.value *= prefix_scale;
            }
        }
    }

    if (S >= QRPN_STACK_SIZE_MAX) return QRPN_ERROR_TOO_MUCH_STACK;
    stack[S] = tmp;
    return S + 1;
}

static int evaluate_one_argument_must_be_unitless(struct quantity * const stack, int S, double complex (* op)(double complex)) {
    if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
    if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

    stack[S - 1].value = op(stack[S - 1].value);
    return S;
}

static int evaluate_one_argument_must_be_unitless_real(struct quantity * const stack, int S, double (* op)(double)) {
    if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
    if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

    stack[S - 1].value = op(creal(stack[S - 1].value));
    return S;
}

static int evaluate_one_argument_must_be_unitless_real_nonnegative(struct quantity * const stack, int S, double (* op)(double)) {
    if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
    if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
    if (cimag(stack[S - 1].value) != 0) return QRPN_ERROR_MUST_BE_REAL;
    if (creal(stack[S - 1].value) < 0) return QRPN_ERROR_MUST_BE_NONNEGATIVE;

    stack[S - 1].value = op(creal(stack[S - 1].value));
    return S;
}

int qrpn_evaluate_token(struct quantity * const stack, int S, const char * const token) {
    if (!strcmp(token, "mul") || !strcmp(token, "*")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        /* calculate and validate output units */
        int units_out[BASEUNITS];
        for (size_t iu = 0; iu < BASEUNITS; iu++) {
            units_out[iu] = stack[S - 2].units[iu] + stack[S - 1].units[iu];
            if (units_out[iu] > INT8_MAX || units_out[iu] < INT8_MIN) return QRPN_ERROR_DIMENSION_OVERFLOW;
        }

        /* note that we perform all possible validation before we mutate any state */
        stack[S - 2].value *= stack[S - 1].value;

        for (size_t iu = 0; iu < BASEUNITS; iu++)
            stack[S - 2].units[iu] = units_out[iu];

        return S - 1;
    }
    else if (!strcmp(token, "div") || !strcmp(token, "/")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        int units_out[BASEUNITS];
        for (size_t iu = 0; iu < BASEUNITS; iu++) {
            units_out[iu] = stack[S - 2].units[iu] - stack[S - 1].units[iu];
            if (units_out[iu] > INT8_MAX || units_out[iu] < INT8_MIN) return QRPN_ERROR_DIMENSION_OVERFLOW;
        }

        stack[S - 2].value /= stack[S - 1].value;

        for (size_t iu = 0; iu < BASEUNITS; iu++)
            stack[S - 2].units[iu] = units_out[iu];

        return S - 1;
    }
    else if (!strcmp(token, "idiv")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;

        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        const long long a = llrint(creal(stack[S - 2].value));
        const long long b = llrint(creal(stack[S - 1].value));
        if (!b) return QRPN_ERROR_DOMAIN;
        const long long c = a / b;
        stack[S - 2].value = c;

        return S - 1;
    }
    else if (!strcmp(token, "add") || !strcmp(token, "+")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        stack[S - 2].value += stack[S - 1].value;
        return S - 1;
    }
    else if (!strcmp(token, "sub") || !strcmp(token, "-")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        stack[S - 2].value -= stack[S - 1].value;
        return S - 1;
    }
    else if (!strcmp(token, "mod") || !strcmp(token, "%")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        if (cimag(stack[S - 2].value) || cimag(stack[S - 1].value) ) return QRPN_ERROR_MUST_BE_REAL;
        stack[S - 2].value = fmod(creal(stack[S - 2].value), creal(stack[S - 1].value));
        return S - 1;
    }
    else if (!strcmp(token, "hypot")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        if (cimag(stack[S - 2].value) || cimag(stack[S - 1].value) ) return QRPN_ERROR_MUST_BE_REAL;

        stack[S - 2].value = hypot(creal(stack[S - 2].value), creal(stack[S - 1].value));
        return S - 1;
    }
    else if (!strcmp(token, "atan2")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        if (cimag(stack[S - 2].value) || cimag(stack[S - 1].value) ) return QRPN_ERROR_MUST_BE_REAL;
        stack[S - 2].value = atan2(creal(stack[S - 2].value), creal(stack[S - 1].value));
        memset(stack[S - 2].units, 0, sizeof(int8_t[BASEUNITS]));
        return S - 1;
    }
    else if (!strcmp(token, "rcp")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;

        for (size_t iu = 0; iu < BASEUNITS; iu++)
            if (stack[S - 1].units[iu] < -INT8_MAX)
                return QRPN_ERROR_DIMENSION_OVERFLOW;

        stack[S - 1].value = 1.0 / stack[S - 1].value;
        for (size_t iu = 0; iu < BASEUNITS; iu++) stack[S - 1].units[iu] *= -1;
        return S;
    }
    else if (!strcmp(token, "chs")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value *= -1;

        /* always choose positive imaginary side of negative real line because [1] [chs] [sqrt] is pretty common */
        if (__imag__ stack[S - 1].value == -0)
            __imag__ stack[S - 1].value = 0;
        return S;
    }
    else if (!strcmp(token, "choose")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        if (cimag(stack[S - 2].value) || cimag(stack[S - 1].value) ) return QRPN_ERROR_MUST_BE_REAL;

        const unsigned long long n = (unsigned long long)llrint(creal(stack[S - 2].value));
        const unsigned long long k = (unsigned long long)llrint(creal(stack[S - 1].value));
        if ((double)n != stack[S - 2].value ||
            (double)k != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;
        stack[S - 2].value = nchoosek(n, k);

        return S - 1;
    }
    else if (!strcmp(token, "gcd")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 2].value) || cimag(stack[S - 1].value) ) return QRPN_ERROR_MUST_BE_REAL;
        if (creal(stack[S - 2].value) < 0 || creal(stack[S - 1].value) < 0 ) return QRPN_ERROR_MUST_BE_NONNEGATIVE;

        const unsigned long long a = (unsigned long long)llrint(creal(stack[S - 2].value));
        const unsigned long long b = (unsigned long long)llrint(creal(stack[S - 1].value));
        if ((double)a != stack[S - 2].value ||
            (double)b != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;
        stack[S - 2].value = gcd(a, b);
        return S - 1;
    }
    else if (!strcmp(token, "lcm")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 2].value) || cimag(stack[S - 1].value) ) return QRPN_ERROR_MUST_BE_REAL;
        if (creal(stack[S - 2].value) < 0 || creal(stack[S - 1].value) < 0 ) return QRPN_ERROR_MUST_BE_NONNEGATIVE;

        const unsigned long long a = (unsigned long long)llrint(creal(stack[S - 2].value));
        const unsigned long long b = (unsigned long long)llrint(creal(stack[S - 1].value));
        if ((double)a != stack[S - 2].value ||
            (double)b != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;

        stack[S - 2].value = a * b / gcd(a, b);
        return S - 1;
    }
    else if (!strcmp(token, "isprime")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (cimag(stack[S - 1].value) != 0) return QRPN_ERROR_MUST_BE_REAL;
        if (creal(stack[S - 1].value) < 0) return QRPN_ERROR_MUST_BE_NONNEGATIVE;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        const unsigned long long x = (unsigned long long)llrint(creal(stack[S - 1].value));
        if (x > 1ULL << 53) return QRPN_ERROR_DOMAIN;
        if ((double)x != (double)creal(stack[S - 1].value)) return QRPN_ERROR_MUST_BE_INTEGER;

        stack[S - 1].value = isprime(x);
        return S;
    }
    else if (!strcmp(token, "swap")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        struct quantity tmp = stack[S - 1];
        stack[S - 1] = stack[S - 2];
        stack[S - 2] = tmp;
        return S;
    }
    else if (!strcmp(token, "drop")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        return S - 1;
    }
    else if (!strcmp(token, "dup")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (S >= QRPN_STACK_SIZE_MAX) return QRPN_ERROR_TOO_MUCH_STACK;
        stack[S] = stack[S - 1];
        return S + 1;
    }
    else if (!strcmp(token, "over")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (S >= QRPN_STACK_SIZE_MAX) return QRPN_ERROR_TOO_MUCH_STACK;
        stack[S] = stack[S - 2];
        return S + 1;
    }
    else if (!strcmp(token, "pick")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_MUST_BE_REAL;
        if (creal(stack[S - 1].value) < 0) return QRPN_ERROR_MUST_BE_NONNEGATIVE;
        const long arg = lrint(creal(stack[S - 1].value));
        if (S < 2 + arg) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1] = stack[S - arg - 2];
        return S;
    }
    else if (!strcmp(token, "roll")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_MUST_BE_REAL;
        if (creal(stack[S - 1].value) < 0) return QRPN_ERROR_MUST_BE_NONNEGATIVE;
        const long arg = lrint(creal(stack[S - 1].value));
        if (S < 2 + arg) return QRPN_ERROR_NOT_ENOUGH_STACK;
        const struct quantity tmp = stack[S - arg - 2];
        memmove(stack + S - arg - 2, stack + S - arg - 1, sizeof(struct quantity) * arg);
        stack[S - 2] = tmp;
        return S - 1;
    }
    else if (!strcmp(token, "and")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        stack[S - 2].value = (!!stack[S - 2].value) && (!!stack[S - 1].value);
        return S - 1;
    }
    else if (!strcmp(token, "or")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        stack[S - 2].value = (!!stack[S - 2].value) || (!!stack[S - 1].value);
        return S - 1;
    }
    else if (!strcmp(token, "not")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        stack[S - 1].value = !stack[S - 1].value;
        return S;
    }
    else if (!strcmp(token, "eq")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;

        stack[S - 2].value = stack[S - 2].value == stack[S - 1].value;
        memset(stack[S - 2].units, 0, sizeof(int8_t[BASEUNITS]));
        return S - 1;
    }
    else if (!strcmp(token, "le") || !strcmp(token, "lt") || !strcmp(token, "ge") || !strcmp(token, "gt")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        if (cimag(stack[S - 1].value) || cimag(stack[S - 2].value) ) return QRPN_ERROR_DOMAIN;

        memset(stack[S - 2].units, 0, sizeof(int8_t[BASEUNITS]));
        if (!strcmp(token, "le")) stack[S - 2].value = creal(stack[S - 2].value) <= creal(stack[S - 1].value);
        else if (!strcmp(token, "lt")) stack[S - 2].value = creal(stack[S - 2].value) < creal(stack[S - 1].value);
        else if (!strcmp(token, "ge")) stack[S - 2].value = creal(stack[S - 2].value) >= creal(stack[S - 1].value);
        else if (!strcmp(token, "gt")) stack[S - 2].value = creal(stack[S - 2].value) > creal(stack[S - 1].value);
        return S - 1;
    }
    else if (!strcmp(token, "quadratic")) {
        if (S < 3) return QRPN_ERROR_NOT_ENOUGH_STACK;

        int units_out[BASEUNITS];
        for (size_t iu = 0; iu < BASEUNITS; iu++) {
            if (stack[S - 1].units[iu] != stack[S - 2].units[iu] * 2 - stack[S - 3].units[iu])
                return QRPN_ERROR_INCONSISTENT_UNITS;
            units_out[iu] = stack[S - 2].units[iu] - stack[S - 3].units[iu];
            if (units_out[iu] > INT8_MAX || units_out[iu] < INT8_MIN) return QRPN_ERROR_DIMENSION_OVERFLOW;
        }

        const double complex a = stack[S - 3].value;
        const double complex b = stack[S - 2].value;
        const double complex c = stack[S - 1].value;
        const double complex discriminant = b * b - 4.0 * a * c;

        const double complex d = 0.5 / a;
        const double complex e = csqrt(discriminant);

        /* well-conditioned floating point method of getting roots, which avoids subtracting two nearly equal magnitude numbers */
        const double complex r1 = __real__ e > 0 ? (-b - e) * d : (-b + e) * d;
        const double complex r0 = c / (r1 * a);
        stack[S - 3].value = r1;
        stack[S - 2].value = r0;

        for (size_t iu = 0; iu < BASEUNITS; iu++) {
            stack[S - 3].units[iu] = units_out[iu];
            stack[S - 2].units[iu] = units_out[iu];
        }

        return S - 1;
    }
    else if (!strcmp(token, "rot")) {
        if (S < 3) return QRPN_ERROR_NOT_ENOUGH_STACK;
        struct quantity tmp = stack[S - 3];
        stack[S - 3] = stack[S - 2];
        stack[S - 2] = stack[S - 1];
        stack[S - 1] = tmp;
        return S;
    }
    else if (!strcmp(token, "pow")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;

        if (units_are_dimensionless(stack[S - 2].units))
            stack[S - 2].value = cpow_checked(stack[S - 2].value, creal(stack[S - 1].value));
        else {
            const long ipowarg = lrint(creal(stack[S - 1].value));
            if ((double)ipowarg != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;

            long long units_out[BASEUNITS];
            for (size_t iu = 0; iu < BASEUNITS; iu++) {
                units_out[iu] = stack[S - 2].units[iu] * ipowarg;
                if (units_out[iu] > INT8_MAX || units_out[iu] < INT8_MIN) return QRPN_ERROR_DIMENSION_OVERFLOW;
            }

            stack[S - 2].value = cpow_checked(stack[S - 2].value, stack[S - 1].value);

            for (size_t iu = 0; iu < BASEUNITS; iu++)
                stack[S - 2].units[iu] = units_out[iu];
        }
        return S - 1;
    }
    else if (!strcmp(token, "rpow")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;

        if (units_are_dimensionless(stack[S - 2].units))
            stack[S - 2].value = cpow_checked(stack[S - 2].value, 1.0 / stack[S - 1].value);
        else {
            const long long ipowarg = llrint(creal(stack[S - 1].value));
            if ((double)ipowarg != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;
            for (size_t iu = 0; iu < BASEUNITS; iu++)
                if ((stack[S - 2].units[iu] / ipowarg) * ipowarg != stack[S - 2].units[iu])
                    return QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED;
            stack[S - 2].value = cpow_checked(stack[S - 2].value, 1.0 / stack[S - 1].value);
            for (size_t iu = 0; iu < BASEUNITS; iu++)
                stack[S - 2].units[iu] /= ipowarg;
        }
        return S - 1;
    }
    else if (!strcmp(token, "gamma")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;
        stack[S - 1].value = tgamma(creal(stack[S - 1].value));
        return S;
    }
    else if (!strcmp(token, "br")) {
        if (S < 4) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units) ||
            !units_are_dimensionless(stack[S - 2].units) ||
            !units_are_dimensionless(stack[S - 3].units) ||
            !units_are_dimensionless(stack[S - 4].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value) ||
            cimag(stack[S - 2].value) ||
            cimag(stack[S - 3].value) ||
            cimag(stack[S - 4].value)) return QRPN_ERROR_DOMAIN;

        const double a[2] = { creal(stack[S - 4].value), creal(stack[S - 3].value) };
        const double b[2] = { creal(stack[S - 2].value), creal(stack[S - 1].value) };
        const double d[2] = { b[0] - a[0], b[1] - a[1] };
        double bearing = 0, range = 0;
        if (d[0] || d[1]) {
            /* todo */
            const double cosa1 = cos(a[1]), cosb1 = cos(b[1]);
            bearing = atan2( sin(d[0]) * cosb1, cosa1 * sin(b[1]) - sin(a[1]) * cosb1 * cos(d[0]) );
            if (bearing < 0.0) bearing += 2.0 * M_PI;
            range = ahav( hav(d[1]) + cosb1 * cosa1 * hav(d[0]) );
        }
        stack[S - 4].value = bearing;
        stack[S - 3].value = range * 6371000.0;
        stack[S - 3].units[0] = 1;
        return S - 2;
    }
    else if (!strcmp(token, "travel")) {
        if (S < 4) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (stack[S - 1].units[0] == 1) {
            /* sketchy */
            stack[S - 1].units[0] = 0;
            stack[S - 1].value /= 6371000.0;
        }

        if (!units_are_dimensionless(stack[S - 1].units) ||
            !units_are_dimensionless(stack[S - 2].units) ||
            !units_are_dimensionless(stack[S - 3].units) ||
            !units_are_dimensionless(stack[S - 4].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (cimag(stack[S - 1].value) ||
            cimag(stack[S - 2].value) ||
            cimag(stack[S - 3].value) ||
            cimag(stack[S - 4].value)) return QRPN_ERROR_DOMAIN;

        /* todo */
        const double in[2] = { creal(stack[S - 4].value), creal(stack[S - 3].value) };
        const double bearing = creal(stack[S - 2].value), range = creal(stack[S - 1].value);
        /* range, bearing, and declination of start point */
        const double a = range, B = bearing, c = M_PI_2 - in[1];
        /* declination of endpoint */
        const double b = ahav( hav(a - c) + sin(a) * sin(c) * hav(B) );
        /* change in longitude */
        const double A = atan2( sin(B) * sin(a) * sin(c), cos(a) - cos(c) * cos(b) );

        /* endpoint longitude is start plus delta */
        stack[S - 4].value = in[0] + A;
        /* endpoint latitude is 90 degrees minus endpoint declination */
        stack[S - 3].value = M_PI_2 - b;

        return S - 2;
    }
    else if (!strcmp(token, "nextafter")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;
        stack[S - 1].value = nextafter(creal(stack[S - 1].value), DBL_MAX);
        return S;
    }
    else if (!strcmp(token, "nextafterf")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;
        stack[S - 1].value = nextafterf(crealf(stack[S - 1].value), FLT_MAX);
        return S;
    }
    else if (!strcmp(token, "arg")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = carg(stack[S - 1].value);
        return S;
    }
    else if (!strcmp(token, "real")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = creal(stack[S - 1].value);
        return S;
    }
    else if (!strcmp(token, "imaginary")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = cimag(stack[S - 1].value);
        return S;
    }
    else if (!strcmp(token, "hav")) return evaluate_one_argument_must_be_unitless_real(stack, S, hav);
    else if (!strcmp(token, "crd")) return evaluate_one_argument_must_be_unitless_real(stack, S, crd);
    else if (!strcmp(token, "exsec")) return evaluate_one_argument_must_be_unitless_real(stack, S, exsecant);
    else if (!strcmp(token, "ahav")) return evaluate_one_argument_must_be_unitless_real(stack, S, ahav);
    else if (!strcmp(token, "acrd")) return evaluate_one_argument_must_be_unitless_real(stack, S, acrd);
    else if (!strcmp(token, "aexsec")) return evaluate_one_argument_must_be_unitless_real(stack, S, arcexsecant);
    else if (!strcmp(token, "floor")) return evaluate_one_argument_must_be_unitless_real(stack, S, floor);
    else if (!strcmp(token, "ceil")) return evaluate_one_argument_must_be_unitless_real(stack, S, ceil);
    else if (!strcmp(token, "round")) return evaluate_one_argument_must_be_unitless_real(stack, S, round);
    else if (!strcmp(token, "erfc")) return evaluate_one_argument_must_be_unitless_real(stack, S, erfc);
    else if (!strcmp(token, "cos")) return evaluate_one_argument_must_be_unitless(stack, S, ccos);
    else if (!strcmp(token, "sin")) return evaluate_one_argument_must_be_unitless(stack, S, csin);
    else if (!strcmp(token, "tan")) return evaluate_one_argument_must_be_unitless(stack, S, ctan);
    else if (!strcmp(token, "tanh")) return evaluate_one_argument_must_be_unitless(stack, S, ctanh);
    else if (!strcmp(token, "acos")) return evaluate_one_argument_must_be_unitless(stack, S, cacos);
    else if (!strcmp(token, "asin")) return evaluate_one_argument_must_be_unitless(stack, S, casin);
    else if (!strcmp(token, "atan")) return evaluate_one_argument_must_be_unitless(stack, S, catan);
    else if (!strcmp(token, "exp")) return evaluate_one_argument_must_be_unitless(stack, S, cexp);
    else if (!strcmp(token, "log")) return evaluate_one_argument_must_be_unitless(stack, S, clog);
    else if (!strcmp(token, "log2")) return evaluate_one_argument_must_be_unitless_real_nonnegative(stack, S, log2);
    else if (!strcmp(token, "log10")) return evaluate_one_argument_must_be_unitless_real_nonnegative(stack, S, log10);
    else if (!strcmp(token, "tenlog")) return evaluate_one_argument_must_be_unitless_real_nonnegative(stack, S, tenlog);
    else if (!strcmp(token, "itenlog")) return evaluate_one_argument_must_be_unitless_real(stack, S, itenlog);
    else if (!strcmp(token, "square")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;

        for (size_t iu = 0; iu < BASEUNITS; iu++)
            if (stack[S - 1].units[iu] * 2 > INT8_MAX || stack[S - 1].units[iu] * 2 < INT8_MIN)
                return QRPN_ERROR_DIMENSION_OVERFLOW;

        stack[S - 1].value = stack[S - 1].value * stack[S - 1].value;
        for (size_t iu = 0; iu < BASEUNITS; iu++)
            stack[S - 1].units[iu] *= 2;
        return S;
    }
    else if (!strcmp(token, "sqrt")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        for (size_t iu = 0; iu < BASEUNITS; iu++)
            if ((stack[S - 1].units[iu] / 2) * 2 != stack[S - 1].units[iu])
                return QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED;

        stack[S - 1].value = csqrt(stack[S - 1].value);
        for (size_t iu = 0; iu < BASEUNITS; iu++)
            stack[S - 1].units[iu] /= 2;
        return S;
    }
    else if (!strcmp(token, "date")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 1].units, units_of_time)) return QRPN_ERROR_INCONSISTENT_UNITS;
        if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;
        /* year, month, day, hour, minute, second */
        time_t unixtime = floor(creal(stack[S - 1].value));
        const double remainder = creal(stack[S - 1].value) - unixtime;
        struct tm unixtime_struct;
        gmtime_r(&unixtime, &unixtime_struct);
        if (S + 5 > QRPN_STACK_SIZE_MAX) return QRPN_ERROR_TOO_MUCH_STACK;
        S += 5;
        memset(stack + S - 6, 0, sizeof(struct quantity) * 6);
        stack[S - 6].value = unixtime_struct.tm_year + 1900;
        stack[S - 5].value = unixtime_struct.tm_mon + 1;
        stack[S - 4].value = unixtime_struct.tm_mday;
        stack[S - 3].value = unixtime_struct.tm_hour;
        stack[S - 2].value = unixtime_struct.tm_min;
        stack[S - 1].value = unixtime_struct.tm_sec + remainder;
        return S;
    }
    else if (!strcmp(token, "abs")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = cabs(stack[S - 1].value);
        return S;
    }
    else if (!strcmp(token, "sum")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        while (S > 1) {
            if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;

            stack[S - 2].value += stack[S - 1].value;
            S--;
        }
        return S;
    }
    else if (!strcmp(token, "print")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        fprintf_quantity(stderr, stack[S - 1]);
        fprintf(stderr, "\n");
        return S;
    }
    else
        return evaluate_literal(stack, S, token);
}

static void fprintf_value(FILE * fh, const double complex value) {
    if (fabs(creal(value)) >= 1e6 && !cimag(value))
        fprintf(fh, "%.16g", creal(value));

    else if ((!creal(value) && cimag(value)) || fabs(creal(value)) * 1e14 < fabs(cimag(value))) {
        if (1.0 == cimag(value))
            fprintf(fh, "i");
        else if (-1.0 == cimag(value))
            fprintf(fh, "-i");
        else
            fprintf(fh, "%gi", cimag(value));
    } else {
        fprintf(fh, "%g", creal(value));

        if (cimag(value) && fabs(cimag(value)) * 1e14 > fabs(creal(value))) {
            fprintf(fh, " %c ", cimag(value) > 0 ? '+' : '-');

            fprintf(fh, "%gi", fabs(cimag(value)));
        }
    }
}

static void fprintf_quantity_si_base(FILE * fh, const struct quantity quantity) {
    /* only use si base units */
    fprintf_value(fh, quantity.value);

    static const char * si_base_unit_abbreviations[BASEUNITS] = { "m", "kg", "s", "A", "K", "Cd", "mol" };

    for (size_t iu = 0; iu < BASEUNITS; iu++) {
        if (quantity.units[iu] > 0)
            fprintf(fh, " %s", si_base_unit_abbreviations[iu]);

        if (quantity.units[iu] > 1)
            fprintf(fh, "^%d", quantity.units[iu]);
    }

    for (size_t iu = 0; iu < BASEUNITS; iu++)
        if (quantity.units[iu] < 0)
            fprintf(fh, " %s^%d", si_base_unit_abbreviations[iu], quantity.units[iu]);
}

static void fprintf_quantity_si(FILE * fh, const struct quantity quantity) {
    /* look for SI-derived units with first positive, then negative exponents */
    for (int sign = 1; sign > -3; sign -= 2)
        for (const struct named_quantity * named = named_quantities; named < named_quantities + named_quantity_count; named++) {
            int exponent;
            /* i hate everything about this and so should you */
            if (named->flags & (FLAG_SI_BASE_UNIT | FLAG_SI_DERIVED_UNIT) && (exponent = units_are_power_of(&quantity, named)) * sign > 0) {
                fprintf_value(fh, quantity.value / named->value);

                fprintf(fh, " %s", named->name ? named->name : named->abrv);
                if (1 != exponent) fprintf(fh, "^%d", exponent);

                return;
            }
        }

    /* if we get here we're just looping through the SI base units */
    fprintf_quantity_si_base(fh, quantity);
}

void fprintf_quantity(FILE * fh, const struct quantity quantity) {
    /* goofy shit that needs work: look for non-SI-base units which roughly match the quantity */
    for (const struct named_quantity * named = named_quantities; named < named_quantities + named_quantity_count; named++)
        if (!(named->flags & (FLAG_SI_BASE_UNIT | FLAG_SI_DERIVED_UNIT)) &&
            units_are_equivalent(quantity.units, named->units) &&
            creal(quantity.value) &&
            /* don't look at it marian */
            cabs(quantity.value / named->value) < 1.000001 &&
            cabs(named->value / quantity.value) < 1.000001) {
            if (!(named->flags & FLAG_UNIT_ENTERS_AS_OPERAND)) {
                fprintf_value(fh, quantity.value / named->value);
                fprintf(fh, " ");
            }
            fprintf(fh, "%s (", named->name ? named->name : named->abrv);
            fprintf_quantity_si(fh, quantity);
            fprintf(fh, ")");
            return;
        }

    fprintf_quantity_si(fh, quantity);
}

void fprintf_stack(FILE * fh, struct quantity * stack, const int S) {
    if (!S) fprintf(fh, "[stack is empty]");
    else for (int is = 0; is < S; is++) {
        fprintf_quantity(fh, stack[is]);
        if (is + 1 < S) fprintf(fh, ", ");
    }
}

char * qrpn_strerror(const int status) {
    if (status >= 0) return "success";
    else if (QRPN_ERROR_TOKEN_UNRECOGNIZED == status) return "unrecognized";
    else if (QRPN_ERROR_NOT_ENOUGH_STACK == status) return "not enough args";
    else if (QRPN_ERROR_INCONSISTENT_UNITS == status) return "inconsistent units";
    else if (QRPN_ERROR_MUST_BE_INTEGER == status) return "arg must be integer";
    else if (QRPN_ERROR_MUST_BE_UNITLESS == status) return "arg must be unitless";
    else if (QRPN_ERROR_MUST_BE_REAL == status) return "arg must be real-valued";
    else if (QRPN_ERROR_MUST_BE_NONNEGATIVE == status) return "arg must be nonnegative";
    else if (QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED == status) return "noninteger units";
    else if (QRPN_ERROR_DOMAIN == status) return "domain error";
    else if (QRPN_ERROR_DIMENSION_OVERFLOW == status) return "dimension overflow";
    else if (QRPN_ERROR_TOO_MUCH_STACK == status) return "insufficient stack space";
    else if (QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT == status) return "unmatched control statement";
    else if (QRPN_ERROR_INEXACT_LITERAL == status) return "unrepresentable literal";
    else return "undefined error";
}

enum control_statement { NONE, ELSE_OR_ENDIF, ENDIF, UNTIL_OR_WHILE, REPEAT };

const char ** find_matching_control_statement(const char ** tp, const enum control_statement looking_for) {
    /* used to skip over branches not taken */
    for (const char * token; (token = *tp); tp++) {
        if (!strcmp(token, "until") || !strcmp(token, "while"))
            return UNTIL_OR_WHILE == looking_for ? tp : NULL;
        else if (!strcmp(token, "repeat"))
            return REPEAT == looking_for ? tp : NULL;
        else if (!strcmp(token, "else") || !strcmp(token, "endif"))
            return ELSE_OR_ENDIF == looking_for || ENDIF == looking_for ? tp : NULL;
        else if (!strcmp(token, "if")) {
            tp = find_matching_control_statement(tp + 1, ELSE_OR_ENDIF);
            if (!tp) return NULL;
            else if (!strcmp(*tp, "else")) {
                tp = find_matching_control_statement(tp + 1, ENDIF);
                if (!tp) return NULL;
            }
        }
        else if (!strcmp(token, "begin")) {
            tp = find_matching_control_statement(tp + 1, UNTIL_OR_WHILE);
            if (!tp) return NULL;
            else if (!strcmp(*tp, "while")) {
                tp = find_matching_control_statement(tp + 1, REPEAT);
                if (!tp) return NULL;
            }
        }
    }
    return NULL;
}

int qrpn_evaluate_tokens(struct quantity * const stack, int S, const char ** const tokens, const size_t nest_level) {
    for (const char ** tp = tokens, * token; (token = *tp); tp++) {
        if (!strcmp(token, "else") || !strcmp(token, "endif") || !strcmp(token, "until") || !strcmp(token, "while") || !strcmp(token, "repeat"))
            return nest_level ? S : QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT;
        else if (!strcmp(token, "begin")) {
            const char ** tp_until_or_while = find_matching_control_statement(tp + 1, UNTIL_OR_WHILE);
            if (!tp_until_or_while) return QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT;
            else if (!strcmp(*tp_until_or_while, "while")) {
                const char ** tp_while = tp_until_or_while;
                const char ** tp_repeat = find_matching_control_statement(tp_while + 1, REPEAT);
                if (!tp_repeat) return QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT;

                while (1) {
                    S = qrpn_evaluate_tokens(stack, S, tp + 1, nest_level + 1);
                    if (S < 0) return S;

                    if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
                    if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

                    S--;
                    if (!stack[S].value) break;

                    S = qrpn_evaluate_tokens(stack, S, tp_while + 1, nest_level + 1);
                }

                tp = tp_repeat;
            }
            else {
                do {
                    S = qrpn_evaluate_tokens(stack, S, tp + 1, nest_level + 1);
                    if (S < 0) return S;

                    if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
                    if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

                    S--;
                } while (!stack[S].value);

                tp = tp_until_or_while;
            }
        }
        else if (!strcmp(token, "if")) {
            if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
            if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

            const char ** tp_else_or_endif = find_matching_control_statement(tp + 1, ELSE_OR_ENDIF);
            const char ** tp_else = NULL, ** tp_endif;

            if (!tp_else_or_endif) return QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT;
            else if (!strcmp(*tp_else_or_endif, "else")) {
                tp_else = tp_else_or_endif;
                tp_endif = find_matching_control_statement(tp_else + 1, ENDIF);
                if (!tp_endif) return QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT;
            }
            else tp_endif = tp_else_or_endif;

            /* choose which branch to take */
            const char ** tp_branch = stack[S - 1].value ? tp : tp_else;
            S--;

            S = qrpn_evaluate_tokens(stack, S, tp_branch + 1, nest_level + 1);

            tp = tp_endif;
        }
        else {
            S = qrpn_evaluate_token(stack, S, token);
            if (S < 0) return S;
        }
    }
    return S;
}

int qrpn_evaluate_string(struct quantity * const stack, int S, const char * string) {
    const char ** tokens = NULL;
    size_t T = 0;

    char * const copy = strdup(string);
    for (char * token, * p = copy; (token = strsep(&p, " ")); ) {
        T++;
        tokens = realloc(tokens, sizeof(char *) * (T + 1));
        tokens[T - 1] = token;
    }

    tokens[T] = NULL;

    S = qrpn_evaluate_tokens(stack, S, tokens, 0);

    free(tokens);
    free(copy);

    return S;
}

int qrpn_try_token(const struct quantity stack[static QRPN_STACK_SIZE_MAX], const int S, const char * const token) {
    /* ideally we would have a strong guarantee that qrpn_evaluate_token would not mutate the input if it would result in an error */
    struct quantity stack_copy[QRPN_STACK_SIZE_MAX];
    memcpy(stack_copy, stack, sizeof(struct quantity) * S);

    return qrpn_evaluate_token(stack_copy, S, token);
}

int qrpn_try_string(const struct quantity stack[static QRPN_STACK_SIZE_MAX], const int S, const char * const string) {
    /* ideally we would have a strong guarantee that qrpn_evaluate_token would not mutate the input if it would result in an error */
    struct quantity stack_copy[QRPN_STACK_SIZE_MAX];
    memcpy(stack_copy, stack, sizeof(struct quantity) * S);

    return qrpn_evaluate_string(stack_copy, S, string);
}

#include <unistd.h>

/* if no other main() is linked, this one will be, and provides a simple command line interface */
__attribute((weak)) int main(const int argc, const char ** const argv) {
    if (isatty(STDIN_FILENO) && argc < 2) {
        /* never reached */
        fprintf(stderr, "%s: Evaluates an RPN expression with units\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    struct quantity stack[QRPN_STACK_SIZE_MAX];

    int S = qrpn_evaluate_tokens(stack, 0, argv + 1, 0);

    if (S < 0) {
        fprintf(stderr, "error: %s\n", qrpn_strerror(S));
        exit(EXIT_FAILURE);
    }

    fprintf_stack(stdout, stack, S);
    fprintf(stdout, "\n");

    return 0;
}
