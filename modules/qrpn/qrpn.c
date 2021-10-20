/* for standalone usage, compile with: cc -Os -Wall -Wextra -Wshadow -march=native qrpn.c -lm -o qrpn */

/* this is very old code and needs to be entirely rewritten but it's too useful to discard */

#define _GNU_SOURCE
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

static unsigned long long gcd(unsigned long long a, unsigned long long b) {
    while (b) {
        const unsigned long long t = b;
        b = a % b;
        a = t;
    }

    return a;
}

static unsigned long long nchoosek(const unsigned long long n, const unsigned long long k) {
    if (1 == k) return n;
    unsigned long long n_choose_k = n * (n - 1) / 2;
    for (size_t kr = 3; kr <= k; kr++)
        n_choose_k *= (n + 1 - kr) / kr;

    return n_choose_k;
}

/* end simple math functions */

struct named_quantity {
    /* ok this is the only other time you will ever catch me using double complex */
    double complex value;
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

static const size_t si_prefix_count = sizeof(si_prefixes) / sizeof(si_prefixes[0]);

static const int8_t units_of_time[BASEUNITS] = { 0, 0, 1, 0, 0, 0, 0 };
static const int8_t dimensionless[BASEUNITS] = { 0, 0, 0, 0, 0, 0, 0 };

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

    { .value = 1.0, .units = { 0, 0, -1, 0, 0, 0, 0 }, .name = "becquerel", .abrv = "Bq" },
    { .value = 1.0, .units = { 2, 0, -2, 0, 0, 0, 0 }, .name = "gray", .abrv = "Gy" },

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
    { .value = 1609.34, .units = { 1, 0, 0, 0, 0, 0, 0 }, .name = "mile" },
    { .value = 1609.34 / 3600, .units = { 1, 0, -1, 0, 0, 0, 0 }, .abrv = "mph" },
    { .value = 86400.0 * 365.242, .units = { 0, 0, 1, 0, 0, 0, 0 }, .name = "year", .abrv = "a" },
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

static void fprintf_value(FILE * fh, const double complex value) {
    if (creal(value) >= 1e6 && !cimag(value))
        fprintf(fh, "%.15g", creal(value));

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
    return fprintf_quantity_si_base(fh, quantity);
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

    return fprintf_quantity_si(fh, quantity);
}

void fprintf_stack(FILE * fh, struct quantity * stack, const size_t S) {
    if (!S)
        fprintf(stdout, "[stack is empty]");
    for (size_t is = 0; is < S; is++) {
        if (S > 1) fprintf(fh, "[");
        fprintf_quantity(fh, stack[is]);
        if (S > 1) fprintf(fh, "]");
        if (is + 1 < S) fprintf(fh, " ");
    }
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
            fprintf(stdout, "warning: %s: ignoring \"%s\"\n", __func__, after);
    }

    return (seconds * 1000000 + microseconds_after_decimal) * 1e-6;
}

char * qrpn_error_string(const int status) {
    if (!status) return "success";
    else if (QRPN_ERROR_NOT_ENOUGH_STACK == status) return "not enough args";
    else if (QRPN_ERROR_INCONSISTENT_UNITS == status) return "inconsistent units";
    else if (QRPN_ERROR_MUST_BE_INTEGER == status) return "arg must be integer";
    else if (QRPN_ERROR_MUST_BE_UNITLESS == status) return "arg must be unitless";
    else if (QRPN_ERROR_TOKEN_UNRECOGNIZED == status) return "unrecognized";
    else if (QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED == status) return "noninteger units";
    else if (QRPN_ERROR_DOMAIN == status) return "domain error";
    else if (QRPN_ERROR_DIMENSION_OVERFLOW == status) return "dimension overflow";
    else return "undefined error";
}

static int qrpn_evaluate_unit(struct quantity ** stack_p, size_t * S_p, const char * const token, const int exponent_sign) {
    const char * slash = strchr(token, '/');

    /* super sketchy */
    if (slash) {
        if (strrchr(token, '/') != slash)
            return QRPN_ERROR_TOKEN_UNRECOGNIZED;

        /* if numerator and denominator both exist, recursively call this function on each of them after adding ^-1 to denominator */
        char * numerator = strdup(token);
        numerator[slash - token] = '\0';
        const int numerator_status = qrpn_evaluate_unit(stack_p, S_p, numerator, exponent_sign);

        free(numerator);

        if (numerator_status != QRPN_WAS_A_UNIT && numerator != QRPN_NOERR) return numerator_status;

        const char * denominator = slash + 1;
        const int denominator_status = qrpn_evaluate_unit(stack_p, S_p, denominator, -exponent_sign);

        if (denominator_status != QRPN_WAS_A_UNIT && denominator_status != QRPN_NOERR) return denominator_status;

        return (numerator_status == QRPN_WAS_A_UNIT) && (denominator_status == QRPN_WAS_A_UNIT) ? QRPN_WAS_A_UNIT : QRPN_NOERR;
    }

    size_t S = *S_p;
    struct quantity * stack = *stack_p;

    const char * const carat = strrchr(token, '^');
    const size_t bytes_before_carat = carat ? (size_t)(carat - token) : (token ? strlen(token) : 0);
    const long long unit_exponent = exponent_sign * (carat ? strtoll(carat + 1, NULL, 10) : 1);

    /* loop over all known units */
    const struct named_quantity * quantity;
    for (quantity = named_quantities; quantity < named_quantities + named_quantity_count; quantity++) {
        int ipass;
        /* loop over [full name, abbreviation, alt spelling] of each unit */
        for (ipass = 0; ipass < 3; ipass++) {
            const char * const unit_name = 2 == ipass ? quantity->alt_spelling : 1 == ipass ? quantity->abrv : quantity->name;
            if (!unit_name) continue;

            /* get number of bytes in unit name because we're gonna need it many times */
            const size_t unit_len = strlen(unit_name);

            /* if number of bytes in input token is enough, and the last portion of the token matches the unit name... */
            if (bytes_before_carat >= unit_len && !memcmp(token + bytes_before_carat - unit_len, unit_name, unit_len)) {
                const size_t bytes_before_unit = bytes_before_carat - unit_len;

                double prefix_scale = 1.0;
                const struct si_prefix * prefix;
                /* loop over known for si prefixes */
                for (prefix = si_prefixes; prefix < si_prefixes + si_prefix_count; prefix++) {
                    /* if looking for SI unit abbreviations, admit SI prefix abbreviations */
                    const char * const prefix_name = 1 == ipass ? prefix->abrv : prefix->name;

                    const size_t prefix_len = prefix_name ? strlen(prefix_name) : 0;
                    if (bytes_before_unit == prefix_len && !memcmp(token, prefix_name, bytes_before_unit)) {
                        prefix_scale = prefix->scale;
                        break;
                    }
                }

                /* if there were bytes before the unit but they didn't match any known prefix, then dont treat as a unit */
                if (bytes_before_unit && prefix == si_prefixes + si_prefix_count)
                    continue;

                if (quantity->flags & FLAG_UNIT_ENTERS_AS_OPERAND) {
                    S++;
                    stack = realloc(stack, sizeof(struct quantity) * S);
                    stack[S - 1] = (struct quantity) { .value = 1 };
                }

                if (!S) return QRPN_ERROR_NOT_ENOUGH_STACK;

                for (size_t iu = 0; iu < BASEUNITS; iu++)
                    if (stack[S - 1].units[iu] + unit_exponent > INT8_MAX ||
                        stack[S - 1].units[iu] + unit_exponent < INT8_MIN)
                        return QRPN_ERROR_DIMENSION_OVERFLOW;

                for (size_t iu = 0; iu < BASEUNITS; iu++)
                    stack[S - 1].units[iu] += unit_exponent * quantity->units[iu];

                stack[S - 1].value *= pow(prefix_scale * quantity->value, unit_exponent);
                stack[S - 1].flags = 0;
                break;
            }
        }
        if (ipass < 3) break;
    }

    *stack_p = stack;
    *S_p = S;

    return (quantity < named_quantities + named_quantity_count ? QRPN_WAS_A_UNIT : QRPN_NOERR);
}

int qrpn_evaluate_token(struct quantity ** stack_p, size_t * S_p, const char * const token) {
    size_t S = *S_p;
    struct quantity * stack = *stack_p;

    if (!strcmp(token, "mul") || !strcmp(token, "*")) {
        /* note we always validate first before mutating the stack */
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

        S--;
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

        S--;
    }

    else if (!strcmp(token, "rcp")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;

        for (size_t iu = 0; iu < BASEUNITS; iu++)
            if (stack[S - 1].units[iu] < -INT8_MAX)
                return QRPN_ERROR_DIMENSION_OVERFLOW;

        stack[S - 1].flags = 0;
        stack[S - 1].value = 1.0 / stack[S - 1].value;
        for (size_t iu = 0; iu < BASEUNITS; iu++) stack[S - 1].units[iu] *= -1;
    }
    else if (!strcmp(token, "chs")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value *= -1;

        /* always choose positive imaginary side of negative real line because [1] [chs] [sqrt] is pretty common */
        if (__imag__ stack[S - 1].value == -0)
            __imag__ stack[S - 1].value = 0;
    }
    else if (!strcmp(token, "idiv")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;

        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        const long long a = llrint(stack[S - 2].value);
        const long long b = llrint(stack[S - 1].value);
        if (!b) return QRPN_ERROR_DOMAIN;
        const long long c = a / b;
        stack[S - 2].value = c;

        S--;
    }
    else if (!strcmp(token, "add") || !strcmp(token, "+") ||
             !strcmp(token, "sub") || !strcmp(token, "-") ||
             !strcmp(token, "mod") || !strcmp(token, "%")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;

        if (!strcmp(token, "add") || !strcmp(token, "+"))
            stack[S - 2].value += stack[S - 1].value;
        else if (!strcmp(token, "sub") || !strcmp(token, "-"))
            stack[S - 2].value -= stack[S - 1].value;
        else if (!strcmp(token, "mod") || !strcmp(token, "%"))
            stack[S - 2].value = fmod(stack[S - 2].value, stack[S - 1].value);

        S--;
    }
    else if (!strcmp(token, "hypot")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        stack[S - 2].flags = 0;
        stack[S - 2].value = hypot(stack[S - 2].value, stack[S - 1].value);

        S--;
    }
    else if (!strcmp(token, "atan2")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;
        stack[S - 2].value = atan2(stack[S - 2].value, stack[S - 1].value);
        memset(stack[S - 2].units, 0, sizeof(int8_t[BASEUNITS]));

        S--;
    }
    else if (!strcmp(token, "choose")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;

        const unsigned long long n = (unsigned long long)llrint(stack[S - 2].value);
        const unsigned long long k = (unsigned long long)llrint(stack[S - 1].value);
        if ((double)n != stack[S - 2].value ||
            (double)k != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;
        stack[S - 2].flags = 0;
        stack[S - 2].value = nchoosek(n, k);

        S--;
    }
    else if (!strcmp(token, "gcd") || !strcmp(token, "lcm")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units) || !units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        const unsigned long long a = (unsigned long long)llrint(stack[S - 2].value);
        const unsigned long long b = (unsigned long long)lrint(stack[S - 1].value);
        if ((double)a != stack[S - 2].value ||
            (double)b != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;
        stack[S - 2].flags = 0;
        if (!strcmp(token, "lcm"))
            stack[S - 2].value = a * b / gcd(a, b);
        else
            stack[S - 2].value = gcd(a, b);

        S--;
    }
    else if (!strcmp(token, "swap")) {
        struct quantity tmp;
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        tmp = stack[S - 1];
        stack[S - 1] = stack[S - 2];
        stack[S - 2] = tmp;
    }
    else if (!strcmp(token, "drop")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        S--;
    }
    else if (!strcmp(token, "dup")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        S++;
        stack = realloc(stack, sizeof(struct quantity) * S);
        stack[S - 1] = stack[S - 2];
    }
    else if (!strcmp(token, "over")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        S++;
        stack = realloc(stack, sizeof(struct quantity) * S);
        stack[S - 1] = stack[S - 3];
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

        S--;
    }
    else if (!strcmp(token, "rot")) {
        struct quantity tmp;
        if (S < 3) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack = realloc(stack, sizeof(struct quantity) * S);
        tmp = stack[S - 3];
        stack[S - 3] = stack[S - 2];
        stack[S - 2] = stack[S - 1];
        stack[S - 1] = tmp;
    }
    else if (!strcmp(token, "pow")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        if (units_are_dimensionless(stack[S - 2].units))
            stack[S - 2].value = cpow(stack[S - 2].value, stack[S - 1].value);
        else {
            const long ipowarg = lrint(stack[S - 1].value);
            if ((double)ipowarg != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;

            long long units_out[BASEUNITS];
            for (size_t iu = 0; iu < BASEUNITS; iu++) {
                units_out[iu] = stack[S - 2].units[iu] * ipowarg;
                if (units_out[iu] > INT8_MAX || units_out[iu] < INT8_MIN) return QRPN_ERROR_DIMENSION_OVERFLOW;
            }

            stack[S - 2].value = cpow(stack[S - 2].value, stack[S - 1].value);
            for (size_t iu = 0; iu < BASEUNITS; iu++)
                stack[S - 2].units[iu] = units_out[iu];
        }
        stack[S - 2].flags = 0;
        S--;
    }
    else if (!strcmp(token, "rpow")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        if (units_are_dimensionless(stack[S - 2].units))
            stack[S - 2].value = cpow(stack[S - 2].value, 1.0 / stack[S - 1].value);
        else {
            const long long ipowarg = llrint(stack[S - 1].value);
            if ((double)ipowarg != stack[S - 1].value) return QRPN_ERROR_MUST_BE_INTEGER;
            for (size_t iu = 0; iu < BASEUNITS; iu++)
                if ((stack[S - 2].units[iu] / ipowarg) * ipowarg != stack[S - 2].units[iu])
                    return QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED;
            stack[S - 2].value = cpow(stack[S - 2].value, 1.0 / stack[S - 1].value);
            for (size_t iu = 0; iu < BASEUNITS; iu++)
                stack[S - 2].units[iu] /= ipowarg;
        }
        stack[S - 2].flags = 0;
        S--;
    }
    else if (!strcmp(token, "gamma")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        stack[S - 1].value = tgamma(stack[S - 1].value);
        stack[S - 1].flags = 0;
    }

    else if (!strcmp(token, "br")) {
        if (S < 4) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (!units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (!units_are_dimensionless(stack[S - 3].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (!units_are_dimensionless(stack[S - 4].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        {
            const double a[2] = { stack[S - 4].value, stack[S - 3].value };
            const double b[2] = { stack[S - 2].value, stack[S - 1].value };
            const double d[2] = { b[0] - a[0], b[1] - a[1] };
            double bearing, range;
            if (0 == d[0] && 0 == d[1]) {
                bearing = 0;
                range = 0;
            } else {
                const double cosa1 = cos(a[1]), cosb1 = cos(b[1]);
                bearing = atan2( sin(d[0]) * cosb1, cosa1 * sin(b[1]) - sin(a[1]) * cosb1 * cos(d[0]) );
                if (bearing < 0.0) bearing += 2.0 * M_PI;
                range = ahav( hav(d[1]) + cosb1 * cosa1 * hav(d[0]) );
            }
            stack[S - 4].value = bearing;
            stack[S - 3].value = range * 6371000.0;
            stack[S - 3].units[0] = 1;
        }

        S -= 2;
    }
    else if (!strcmp(token, "travel")) {
        if (S < 4) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (stack[S - 1].units[0] == 1) {
            stack[S - 1].units[0] = 0;
            stack[S - 1].value /= 6371000.0;
        }

        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (!units_are_dimensionless(stack[S - 2].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (!units_are_dimensionless(stack[S - 3].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        if (!units_are_dimensionless(stack[S - 4].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        {
            const double in[2] = { stack[S - 4].value, stack[S - 3].value };
            const double bearing = stack[S - 2].value, range = stack[S - 1].value;
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
        }

        S -= 2;
    }
    else if (!strcmp(token, "nextafter")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = nextafter(stack[S - 1].value, DBL_MAX);
    }
    else if (!strcmp(token, "nextafterf")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = nextafterf(stack[S - 1].value, FLT_MAX);
    }
    else if (!strcmp(token, "arg")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = cargf(stack[S - 1].value);
    }
    else if (!strcmp(token, "real")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = crealf(stack[S - 1].value);
    }
    else if (!strcmp(token, "imaginary")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = cimagf(stack[S - 1].value);
    }
    else if (!strcmp(token, "cos") ||
             !strcmp(token, "sin") ||
             !strcmp(token, "tan") ||
             !strcmp(token, "tanh") ||
             !strcmp(token, "hav") ||
             !strcmp(token, "crd") ||
             !strcmp(token, "exsec")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        if (!strcmp(token, "cos"))
            stack[S - 1].value = ccos(stack[S - 1].value);
        else if (!strcmp(token, "sin"))
            stack[S - 1].value = csin(stack[S - 1].value);
        else if (!strcmp(token, "tan"))
            stack[S - 1].value = ctan(stack[S - 1].value);
        else if (!strcmp(token, "tanh"))
            stack[S - 1].value = ctanh(stack[S - 1].value);
        else if (!strcmp(token, "hav"))
            stack[S - 1].value = hav(stack[S - 1].value);
        else if (!strcmp(token, "crd"))
            stack[S - 1].value = crd(stack[S - 1].value);
        else if (!strcmp(token, "exsec"))
            stack[S - 1].value = exsecant(stack[S - 1].value);;
    }
    else if (!strcmp(token, "acos") ||
             !strcmp(token, "asin") ||
             !strcmp(token, "atan") ||
             !strcmp(token, "ahav") ||
             !strcmp(token, "acrd") ||
             !strcmp(token, "aexsec")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;

        if (!strcmp(token, "acos"))
            stack[S - 1].value = cacos(stack[S - 1].value);
        else if (!strcmp(token, "asin"))
            stack[S - 1].value = casin(stack[S - 1].value);
        else if (!strcmp(token, "atan"))
            stack[S - 1].value = catan(stack[S - 1].value);
        else if (!strcmp(token, "ahav"))
            stack[S - 1].value = ahav(stack[S - 1].value);
        else if (!strcmp(token, "acrd"))
            stack[S - 1].value = acrd(stack[S - 1].value);
        else if (!strcmp(token, "aexsec"))
            stack[S - 1].value = arcexsecant(stack[S - 1].value);
    }

    else if (!strcmp(token, "exp") ||
             !strcmp(token, "log") ||
             !strcmp(token, "log2") ||
             !strcmp(token, "log10") ||
             !strcmp(token, "tenlog") ||
             !strcmp(token, "itenlog") ||
             !strcmp(token, "floor") ||
             !strcmp(token, "round") ||
             !strcmp(token, "ceil") ||
             !strcmp(token, "erfc")
             ) {

        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_dimensionless(stack[S - 1].units)) return QRPN_ERROR_MUST_BE_UNITLESS;
        stack[S - 1].flags = 0;

        if (!strcmp(token, "exp"))
            stack[S - 1].value = cexp(stack[S - 1].value);
        else if (!strcmp(token, "log"))
            stack[S - 1].value = clog(stack[S - 1].value);
        else if (!strcmp(token, "log2")) {
            if (creal(stack[S - 1].value) < 0) return QRPN_ERROR_DOMAIN;
            stack[S - 1].value = log2(stack[S - 1].value);
        }
        else if (!strcmp(token, "log10")) {
            if (creal(stack[S - 1].value) < 0) return QRPN_ERROR_DOMAIN;
            stack[S - 1].value = log10(stack[S - 1].value);
        }
        else if (!strcmp(token, "tenlog")) {
            if (creal(stack[S - 1].value) < 0 || cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;
            stack[S - 1].value = 10.0 * log10(stack[S - 1].value);
        }
        else if (!strcmp(token, "itenlog")) {
            if (cimag(stack[S - 1].value)) return QRPN_ERROR_DOMAIN;
            stack[S - 1].value = pow(10.0, stack[S - 1].value / 10.0);
        }
        else if (!strcmp(token, "floor"))
            stack[S - 1].value = floor(stack[S - 1].value);
        else if (!strcmp(token, "ceil"))
            stack[S - 1].value = ceil(stack[S - 1].value);
        else if (!strcmp(token, "round"))
            stack[S - 1].value = llrint(stack[S - 1].value);
        else if (!strcmp(token, "erfc"))
            stack[S - 1].value = erfc(stack[S - 1].value);
    }

    else if (!strcmp(token, "square")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;

        for (size_t iu = 0; iu < BASEUNITS; iu++)
            if (stack[S - 1].units[iu] * 2 > INT8_MAX || stack[S - 1].units[iu] * 2 < INT8_MIN)
                return QRPN_ERROR_DIMENSION_OVERFLOW;

        stack[S - 1].flags = 0;
        stack[S - 1].value = stack[S - 1].value * stack[S - 1].value;
        for (size_t iu = 0; iu < BASEUNITS; iu++)
            stack[S - 1].units[iu] *= 2;
    }

    else if (!strcmp(token, "sqrt")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        for (size_t iu = 0; iu < BASEUNITS; iu++)
            if ((stack[S - 1].units[iu] / 2) * 2 != stack[S - 1].units[iu])
                return QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED;

        stack[S - 1].flags = 0;
        stack[S - 1].value = csqrt(stack[S - 1].value);
        for (size_t iu = 0; iu < BASEUNITS; iu++)
            stack[S - 1].units[iu] /= 2;
    }

    else if (!strcmp(token, "date")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        if (!units_are_equivalent(stack[S - 1].units, units_of_time)) return QRPN_ERROR_INCONSISTENT_UNITS;
        /* year, month, day, hour, minute, second */
        time_t unixtime = floor(stack[S - 1].value);
        const double remainder = stack[S - 1].value - unixtime;
        struct tm unixtime_struct;
        gmtime_r(&unixtime, &unixtime_struct);
        S += 5;
        stack = realloc(stack, sizeof(struct quantity) * S);
        memset(stack + S - 6, 0, sizeof(struct quantity) * 6);
        stack[S - 6].value = unixtime_struct.tm_year + 1900;
        stack[S - 5].value = unixtime_struct.tm_mon + 1;
        stack[S - 4].value = unixtime_struct.tm_mday;
        stack[S - 3].value = unixtime_struct.tm_hour;
        stack[S - 2].value = unixtime_struct.tm_min;
        stack[S - 1].value = unixtime_struct.tm_sec + remainder;
    }

    else if (!strcmp(token, "abs")) {
        if (S < 1) return QRPN_ERROR_NOT_ENOUGH_STACK;
        stack[S - 1].value = cabs(stack[S - 1].value);
    }
    else if (!strcmp(token, "sum")) {
        if (S < 2) return QRPN_ERROR_NOT_ENOUGH_STACK;
        while (S > 1) {
            if (!units_are_equivalent(stack[S - 2].units, stack[S - 1].units)) return QRPN_ERROR_INCONSISTENT_UNITS;

            stack[S - 2].value += stack[S - 1].value;
            S--;
        }
    }
    else {
        const int unit_ret = qrpn_evaluate_unit(&stack, &S, token, 1);

        if (QRPN_NOERR != unit_ret && QRPN_WAS_A_UNIT != unit_ret)
            return unit_ret;

        else if (QRPN_NOERR == unit_ret) {
            /* token was not a unit name */
            struct quantity tmp = { 0 };
            double d = 0, m = 0, s = 0;

            if (strpbrk(token + 1, "d°") && sscanf(token, "%lf%*[d°]%lf%*[m']%lf%*[s\"]", &d, &m, &s)) {
                const double leading = strtod(token, NULL);
                tmp.value = copysign(fabs(d) + m / 60.0 + s / 3600.0, leading) * M_PI / 180.0;
            }
            else if (strpbrk(token, "T") && strpbrk(token, "Z")) {
                tmp.value = datestr_to_unix_seconds(token);
                tmp.units[2] = 1;
            }
            else if (!strcmp(token, "pi")) {
                tmp.value = M_PI;
            }
            else if (!strcmp(token, "-pi")) {
                tmp.value = -M_PI;
            }
            else if (!strcmp(token, "i"))
                tmp.value = I;
            else if (!strcmp(token, "-i"))
                tmp.value = -I;
            else {
                char * endptr = NULL;
                tmp.value = strtod(token, &endptr);
                if (!strcmp(endptr, "i"))
                    tmp.value *= I;
                else if (endptr == token)
                    return QRPN_ERROR_TOKEN_UNRECOGNIZED;
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

            S++;
            stack = realloc(stack, sizeof(struct quantity) * S);
            stack[S - 1] = tmp;
        }
    }

    *stack_p = stack;
    *S_p = S;

    return 0;
}

int qrpn_try_token(const struct quantity * const stack, const size_t S, const char * const token) {
    size_t S_copy = S;

    /* ideally we would have a strong guarantee that qrpn_evaluate_token would not mutate the input if it would result in an error */
    struct quantity * stack_copy = malloc(sizeof(struct quantity) * S);
    memcpy(stack_copy, stack, sizeof(struct quantity) * S);

    const int status = qrpn_evaluate_token(&stack_copy, &S_copy, token);
    free(stack_copy);
    return status;
}

#include <unistd.h>

/* if no other main() is linked, this one will be, and provides a simple command line interface */
__attribute((weak)) int main(const int argc, char ** const argv) {
    if (isatty(STDIN_FILENO) && argc < 2) {
        /* never reached */
        fprintf(stdout, "%s: Evaluates an RPN expression with units\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    struct quantity * stack = NULL;
    size_t S = 0;

    for (char ** next_token = argv + 1; next_token < argv + argc; next_token++) {
        const int status = qrpn_evaluate_token(&stack, &S, *next_token);
        if (status) {
            fprintf(stdout, "error: %s\n", qrpn_error_string(status));
            exit(EXIT_FAILURE);
        }
    }

    fprintf_stack(stdout, stack, S);
    fprintf(stdout, "\n");

    free(stack);

    return 0;
}
