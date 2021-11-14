#include <stdint.h>
#include <complex.h>
#include <stdio.h>

/* reasonably large fixed stack size given this is not a turing complete implemetation */
#define QRPN_STACK_SIZE_MAX 32

/* not going to change in this unverse */
#define BASEUNITS 7

struct quantity {
    /* this is the only time you will ever catch me using double complex */
    double complex value;
    int8_t units[BASEUNITS]; /* metre, kilogram, second, ampere, kelvin, candela, mol */
};

/* mutate the stack, initially of size S, according to the current token, and return either the nonnegative new size S or a negative error code,  which can be passed to qrpn_strerror to obtain a pointer to human-readable error string */
int qrpn_evaluate_token(struct quantity * stack, int S, const char * const token);

/* same, but operate on a temporary copy of the input and do not mutate the original */
int qrpn_try_token(const struct quantity stack[static QRPN_STACK_SIZE_MAX], const int S, const char * const token);
int qrpn_try_string(const struct quantity stack[static QRPN_STACK_SIZE_MAX], const int S, const char * const string);

int qrpn_evaluate_string(struct quantity * const stack, int S, const char * string);


/* given the value returned from a function above, return a pointer to a string literal */
char * qrpn_strerror(const int status);

/* utility functions */
void fprintf_stack(FILE * fh, struct quantity * stack, const int S);
void fprintf_quantity(FILE * fh, const struct quantity quantity);

#define QRPN_ERROR_TOKEN_UNRECOGNIZED -1
#define QRPN_ERROR_NOT_ENOUGH_STACK -2
#define QRPN_ERROR_INCONSISTENT_UNITS -3
#define QRPN_ERROR_MUST_BE_INTEGER -4
#define QRPN_ERROR_MUST_BE_UNITLESS -5
#define QRPN_ERROR_MUST_BE_REAL -6
#define QRPN_ERROR_MUST_BE_NONNEGATIVE -7
#define QRPN_ERROR_RATIONAL_NOT_IMPLEMENTED -8
#define QRPN_ERROR_DOMAIN -9
#define QRPN_ERROR_DIMENSION_OVERFLOW -10
#define QRPN_ERROR_TOO_MUCH_STACK -11
#define QRPN_ERROR_UNMATCHED_CONTROL_STATEMENT -12
#define QRPN_ERROR_INEXACT_LITERAL -13
#define QRPN_NOT_A_UNIT -14
