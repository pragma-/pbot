#include <stdint.h>
#include <stddef.h>
#include <complex.h>
#include <stdio.h>

#define BASEUNITS 7

struct quantity {
    /* this is the only time you will ever catch me using double complex */
    double complex value;
    int8_t units[BASEUNITS]; /* metre, kilogram, second, ampere, kelvin, candela, mol */
    uint8_t flags;
};

#define QRPN_NOERR 0
#define QRPN_ERROR_NOT_ENOUGH_STACK 1
#define QRPN_ERROR_INCONSISTENT_UNITS 2
#define QRPN_ERROR_MUST_BE_INTEGER 3
#define QRPN_ERROR_TOKEN_UNRECOGNIZED 4
#define QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED 5
#define QRPN_ERROR_MUST_BE_UNITLESS 6
#define QRPN_ERROR_DOMAIN 7
#define QRPN_ERROR_DIMENSION_OVERFLOW 8
#define QRPN_WAS_A_UNIT 9

#define FLAG_UNIT_ENTERS_AS_OPERAND 1
#define FLAG_SI_BASE_UNIT 4
#define FLAG_SI_DERIVED_UNIT 8

int qrpn_evaluate_token(struct quantity ** stack_p, size_t * S_p, const char * const token);
char * qrpn_error_string(const int status);
void fprintf_stack(FILE * fh, struct quantity * stack, const size_t S);
void fprintf_quantity(FILE * fh, const struct quantity quantity);
int qrpn_try_token(const struct quantity * const stack, const size_t S, const char * const token);
