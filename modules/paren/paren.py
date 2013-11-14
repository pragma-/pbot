#!/usr/bin/env python
from __future__ import print_function

import sys

from pycparser import c_parser, c_generator, c_ast, plyparser
from pycparser.ply import yacc 

with open("paren/stddef") as f:
    STDDEF = f.read()

class CParser(c_parser.CParser):
    def __init__(self, *a, **kw):
        super(CParser, self).__init__(*a, **kw)
        self.p_expression_hack = self._expression_hack
        self.cparser = yacc.yacc(
            module=self,
            start='expression_hack',
            debug=kw.get('yacc_debug', False),
            errorlog=yacc.NullLogger(),
            optimize=kw.get('yacc_optimize', True),
            tabmodule=kw.get('yacctab', 'yacctab'))
    
    def parse(self, text, filename='', debuglevel=0):
        self.clex.filename = filename
        self.clex.reset_lineno()
        self._scope_stack = [dict()]
        self._last_yielded_token = None
        for name in STDDEF.split('\n'):
            if name:
                self._add_typedef_name(name, None)
        return self.cparser.parse(
                input=text,
                lexer=self.clex,
                debug=debuglevel)
    
    def _expression_hack(self, p):
        """ expression_hack   : translation_unit expression
                              | expression
        """
        p[0] = c_ast.ExprList([p[2] if len(p) == 3 else p[1]])


class CGenerator(c_generator.CGenerator):
    def visit_BinaryOp(self, n):
        lval_str = self._parenthesize_if(n.left,
                            lambda d: not self._is_simple_node(d))
        rval_str = self._parenthesize_if(n.right,
                            lambda d: not self._is_simple_node(d))
        return '(%s %s %s)' % (lval_str, n.op, rval_str)
 
    def visit_UnaryOp(self, n):
        # don't parenthesize an operand to sizeof if it's not a type
        if n.op == 'sizeof':
            if isinstance(n.expr, c_ast.Typename):
                return 'sizeof (%s)' % self.visit(n.expr)
            else:
                return 'sizeof %s' % self._parenthesize_unless_simple(n.expr)
        return super(CGenerator, self).visit_UnaryOp(n)

    def _is_simple_node(self, n):
        """ Returns True for nodes that are "simple" - i.e. nodes that always
            have higher precedence than operators.
        """
        return isinstance(n,( c_ast.Constant, c_ast.ID, c_ast.ArrayRef,
                              c_ast.StructRef, c_ast.FuncCall, c_ast.BinaryOp))

def translate_to_c(input):
    parser = CParser(yacc_optimize=False)
    try:
        ast = parser.parse(input, '<input>')
    except plyparser.ParseError as e:
        print(sys.argv[1] + ': ' + "Error: {0}".format(e.args[0]))
        return
    generator = CGenerator()
    print(sys.argv[1] + ': ' + generator.visit(ast))


if __name__ == "__main__":
    if len(sys.argv) > 2:
        translate_to_c(' '.join(sys.argv[2:]))
    else:
      print(sys.argv[1] + ': ' + "Usage: paren <expression>")

