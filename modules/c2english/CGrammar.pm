# C-to-English Grammar
# Pragmatic Software

{
  my ($rule_name, @macros, @typedefs, @identifiers); 
}

startrule: 
      translation_unit 
          { 
            my $output = $item[-1];
            $output =~ s/\^L(\s*.?)/\L$1/g; # lowercase specified characters
            $output =~ s/\^U(\s*.?)/\U$1/g; # uppercase specified characters
            push @$return, $output;
          } 
      startrule(?)
          { push @$return, $item[-1]; }
    
translation_unit:
      comment
    | external_declaration
    | function_definition
    | preproc[matchrule => 'translation_unit']

preproc: 
      '#' (definition 
        | undefinition  
        | inclusion  
        | line 
        | error
        | pragma 
        | preproc_conditional[matchrule => $arg{matchrule}])

definition: 
      macro_definition
    | 'define' identifier token_sequence(?) <skip: '[ \t]*'> "\n"
          {
            my $token_sequence = join('',@{$item{'token_sequence(?)'}});
            $return = "Define the macro $item{identifier}";
            $return .= " to mean $token_sequence" if $token_sequence;
            $return .= ".\n";
          }

macro_definition:
      'define' identifier '(' <leftop: identifier ',' identifier> ')' token_sequence <skip: '[ \t]*'> "\n"
          {
            my @symbols = @{$item[-5]}; 
            my $last; 
            push @macros, $item{identifier}; 
            $return = "Define the macro $item{identifier} "; 
            if ($#symbols > 0) { 
              $last = pop @symbols; 
              $return .= "with the symbols " . join(", ",@symbols) . " and $last "; 
            } else { 
              $return .= "with the symbol $symbols[0] "; 
            } 
            $return .= "to use the token sequence `$item{token_sequence}`.\n"; 
          } 

undefinition:
      'undef' identifier <skip: '[ \t]*'> "\n"
          { 
            @macros = grep { $_ ne $item{identifier} } @macros;
            $return = "\nAnnul the definition of $item{identifier}.\n";
          }

inclusion: 
      'include' '<' filename '>' <skip: '[ \t]*'> "\n"
          { $return = "\nInclude the header $item{filename}.\n"; }
    | 'include' '"' filename '"' <skip: '[ \t]*'> "\n"
          { $return = "\nInclude the source file $item{filename}.\n"; }
    | 'include' token
          { $return = "\nImport code noted by the token $item{token}.\n"; }   

filename: 
      /[_\.\-\w\/]+/ 

line: 
      'line' constant ('"' filename '"'
          { $return = "and filename $item{filename}"; }
      )(?) <skip: '[ \t]*'> "\n"
          { $return = "\nThis is line number $item{constant} " . join('', @{$item[-3]}) . ".\n"; }

error:
      'error' token_sequence(?) <skip: '[ \t]*'> "\n"
          { $return = "Stop compilation with error \"" . join('', @{$item{'token_sequence(?)'}}) . "\".\n"; }

pragma: 
      'pragma' token_sequence(?) <skip: '[ \t]*'> "\n"
          {
            my $pragma = join('',@{$item{'token_sequence(?)'}}); 
            if ($pragma) { $pragma = ' "$pragma"'; }
            $return = "Process a compiler-dependent pragma$pragma.\n";     
          }

preproc_conditional: 
      if_line[matchrule => $arg{matchrule}] 
          { $rule_name = $arg{matchrule}; }
      <matchrule: $rule_name>(s?)
          { $return = $item{if_line} . join('',@{$item[-1]}); }
      (elif_parts[matchrule => $rule_name])(?)
      (else_parts[matchrule => $rule_name])(?)
          { $return .= join('',@{$item[-2]}) .  join('',@{$item[-1]}); }
      '#' 'endif' 
          { $return .= "End preprocessor conditional.\n"; }

if_line:
      'ifdef' identifier <skip: '[ \t]*'> "\n"
          { $return .= "If the macro $item{identifier} is defined, then ^L"; }
    | 'ifndef' identifier <skip: '[ \t]*'> "\n"
          { $return .= "If the macro $item{identifier} is not defined, then ^L"; }
    | 'if' constant_expression <skip: '[ \t]*'> "\n"
          { $return .= "If the preprocessor condition^L $item{constant_expression} is true, then ^L"; }

elif_parts:
      ('#' 'elif' constant_expression 
          { $return .= "Otherwise, if the preprocessor condition $item{constant_expression} is true, then ^L"; }
      (<matchrule: $rule_name> )[matchrule => $arg{matchrule}](s?)
          { $return .=  join('',@{$item[-1]}); }
      )(s) 
          { $return = join('', @{$item[-1]}); }
 
else_parts:
      '#' 'else' 
          { $rule_name = $arg{matchrule}; }
      (<matchrule: $rule_name>)[matchrule => $arg{matchrule}](s?)
          { $return = "Otherwise, ^L" . join('',@{$item[-1]}); }

token_sequence:
      token(s)
          { $return = join(' ', @{$item[1]}); }

token:
      <skip: '[ \t]*'> /\S+/ 
          { $return = $item[-1]; }

external_declaration:
      declaration[context => 'external declaration'] 

function_definition:
      declaration_specifiers[context => 'function definition'](?) declarator[context => 'function definition'] compound_statement[context => 'function definition statement'](?)
          {
            my $declaration_specifiers = join('', @{$item{'declaration_specifiers(?)'}}); 
            my $name = $item{declarator}->[0];
            my $parameter_list = $item{declarator}->[1];

            my $return_type;
            if (@{$item{declarator}} > 2) {
              $return_type = "$item{declarator}->[2] $declaration_specifiers";
            } else {
              $return_type = $declaration_specifiers;
            }

            if ($return_type =~ s/( with.*)$//) {
              my $specifier = $1;
              $parameter_list =~ s/function/function$specifier/;
            }

            if ($return_type =~ s/inline//g) {
              $return_type = join(' ', split(' ', $return_type));
              my $and = $parameter_list =~ s/function with/function/ ? ' and' : '';
              $parameter_list =~ s/function/function with suggestion to be as fast as possible$and/;
            }

            if ($return_type =~ s/_Noreturn//g) {
              $return_type = join(' ', split(' ', $return_type));
              $parameter_list =~ s/ returning$//;
              if ($return_type eq 'void') {
                $return_type = "which doesn't return to its caller";
              } else {
                $return_type = "which shouldn't return to its caller yet does mysteriously return $return_type";
              }
            }

            if (ref $name eq 'ARRAY') {
              my @a = @$name;
              $name = shift @a;
              $parameter_list = join(' ', @a) . " $parameter_list";
            }
            
            $return = "\nLet $name be a $parameter_list $return_type.\n";
            
            my $statements = join('', @{$item{'compound_statement(?)'}});
            $return .= "When called, the function will ^L$statements";
          } 

block_item_list:
      block_item(s)
          { 
            if (@{$item{'block_item(s)'}} == 1) {
              $return = $item{'block_item(s)'}->[0];
            } elsif (@{$item{'block_item(s)'}} == 2) {
              my $first = $item{'block_item(s)'}->[0];
              my $second = $item{'block_item(s)'}->[1];
              $first =~ s/\.?\s*$//;
              $return = "$first and then ^L$second";
            } else {
              my $last = pop @{$item{'block_item(s)'}};
              $return = join('Then ^L', @{$item{'block_item(s)'}}) . "Finally, ^L$last";
            }
          }

block_item:
      declaration
    | statement[context => "$arg{context}|block item"]
    | preproc
    | comment

compound_statement:
      '{' block_item_list(s?) '}' 
          { 
            my $block_items = join('', @{$item{'block_item_list(s?)'}});

            if ($arg{context} =~ /block item/
                and $arg{context} !~ /do loop$/
                and $arg{context} !~ /if statement$/
                and $arg{context} !~ /switch$/
                and $arg{context} !~ /else block$/) {
              $return = "Begin new block.\n";
            }

            if ($block_items) { 
              $return .= $block_items;
            } else {
              $return .= "Do nothing.\n";
            } 

            if ($arg{context} =~ /block item/
                and $arg{context} !~ /do loop$/
                and $arg{context} !~ /if statement$/
                and $arg{context} !~ /switch$/
                and $arg{context} !~ /else block$/) {
              $return .= "End block.\n";
            }

            if ($arg{context} 
                and $arg{context} !~ /do loop$/
                and $arg{context} !~ /if statement$/
                and $arg{context} !~ /else block$/
                and $arg{context} !~ /case$/
                and $arg{context} !~ /function definition statement$/ 
                and $arg{context} !~ /function definition$/) { 
              my @contexts = split /\|/, $arg{context};
              my $context = pop @contexts;
              $return .= "End $context.\n" unless $context eq 'block item';
            } 
            1;
          }

statement_list:
      comment(?) preproc[matchrule => 'statement'](?) statement[context => undef]
               {
                 my $preproc = join('',@{$item{'preproc(?)'}}); 
                 my $comment = join('',@{$item{'comment(?)'}}); 

                 $return = $item{statement};
   
                 if ($comment) { $return = $comment . $return; }  
                 if ($preproc) { $return = $preproc . $return; } 
               } 
        statement_list(?)
               { $return .= join('',@{$item{'statement_list(?)'}}); }

statement: 
      jump_statement
    | compound_statement
    | iteration_statement
    | selection_statement
    | labeled_statement
    | expression_statement

iteration_statement:
      'for' '(' <commit> for_initialization(?) for_expression(?) for_increment(?) ')'    
        statement[context => 'for loop']
          { 
            my $initialization = join('', @{$item{'for_initialization(?)'}}); 
            my $expression = join('',@{$item{'for_expression(?)'}}); 
            my $increment = join('',@{$item{'for_increment(?)'}}); 

            if ($initialization) { 
              $return .= "Prepare a loop by ^L$initialization, then ^L"; 
            }

            if (length $expression) { 
              if ($expression =~ /^(\d+)$/) {
                if($expression == 0) {
                  $return .= "Never repeatedly ^L";
                } else {
                  $return .= "Repeatedly ^L";
                }
              } else {
                my $expression  = ::istrue $expression;
                $return .= "For as long as ^L$expression, ^L"; 
              }
            } else {
              $return .= "Repeatedly ^L";
            } 

            $return .= $item{statement};

            if ($increment) { 
              $return =~ s/End for loop.$//;
              $return .= "After each iteration, ^L$increment.\n"; 
            } 
          } 
    | 'while' '(' <commit> expression[context => 'while conditional']  ')' statement[context => 'while loop']  
          { 
            if ($item{expression} =~ /(^\d+$)/) {
              if ($1 == 0) {
                $return = "Never repeatedly ^L";
              } else {
                $return = "Repeatedly ^L";
              }
            } else {
              my $expression = ::istrue $item{expression};
              $return = "While ^L$expression, ^L"; 
            }

            if ($item{statement}) {
              $return .= $item{statement} . "\n";
            } else {
              $return .= "do nothing.\n";
            }
          } 
    | 'do' statement[context => 'do loop'] 'while' '(' expression[context => 'do while conditional'] ')' ';' 
          {
            $item{statement} =~ s/^do nothing/nothing/i;
            $return = "Do the following:^L $item{statement}";
            if ($item{expression} =~ /(^\d+$)/) {
              if ($1 == 0) {
                $return .= "Do this once.\n";
              } else {
                $return .= "Do this repeatedly.\n";
              }
            } else {
              my $expression = ::istrue $item{expression};
              $return .= "Do this as long as ^L$expression.\n";
            }
          }

for_initialization:
      declaration[context => 'for init']
    | expression_statement[context => 'for init']

for_expression:
      expression_statement[context => 'for conditional']

for_increment:
      expression[context => 'for increment statement'] 

selection_statement:
      'if' <commit> '(' expression[context => 'if conditional'] ')' statement[context => "$arg{context}|if statement"]
          { 
            if ($item{expression} =~ /^(\d+)$/) {
              if ($1 == 0) {
                $return = "Never ";
              } else {
                $return = "Always ";
              }
            } else {
              my $expression = ::istrue $item{expression};
              $return = "If ^L$expression then ";
            }
            $return .= "^L$item{statement}";
          }
      ('else' statement[context => "$arg{context}|else block"]
          { $return = "Otherwise, ^L$item{statement}"; }
      )(?)
          { $return .= join('',@{$item[-1]}); }
    | 'switch'  '(' expression[context => 'switch conditional'] ')'  statement[context => "$arg{context}|switch"]  
          { 
            $return = "When given the expression ^L$item{expression}, ^L$item{statement}";
          }

jump_statement: 
      'break' ';'   
          { 
            if ($arg{context} =~ /switch/ or $arg{context} =~ /case/) {
              $return = "Exit switch block.\n";
            } elsif (length $arg{context}) {
              my ($context) = $arg{context} =~ /([^|]+)/;
              $return = "Break from the $context.\n";
            } else {
              $return = "Break from the current block.\n";
            }
          } 
    | 'continue' ';'
          { $return = "Return to the top of the current loop.\n"; } 
    | 'return' <commit> expression[context => "$arg{context}|return expression"](?) ';' 
          {
            my $expression = join('', @{$item{'expression(?)'}});

            if (length $expression) { 
              $return = "Return ^L$expression.\n";
            } else {
              $return = "Return no value.\n";
            }
          }
    | 'goto' <commit> identifier ';' comment(?)
          { 
            $return = "Go to the label named $item{identifier}.\n";
            $return .= join('', @{$item{'comment(?)'}});
          }

expression_statement:
      expression[context => "$arg{context}|statement"](?) ';'
          { 
            my $expression = join('',@{$item[1]}); 
            if (not length $expression) {
              if ($arg{context} eq 'label'
                  or $arg{context} eq 'for init'
                  or $arg{context} eq 'for conditional') {
                $return = "";
              } else {
                $return = "Do nothing.\n"; 
              }
            } else { 
              $return = $expression;
              $return .= ".\n" unless $arg{context} =~ /for (init|conditional)$/;
            } 
          }

labeled_statement:
      identifier ':' statement[context => 'label'] (';')(?)
          { $return = "Let there be a label $item{identifier}.\n$item{statement}"; }
    | ('case' constant_expression 
          { $return = $item{constant_expression}; } 
        ':')(s)
          { 
            my @items = @{$item[1]};
            if (@items <= 2) {
              $return = join(' or ', @{$item[1]});
            } else {
              my $last = pop @items;
              $return = join(', ', @items) . " or $last";
            }
          }
        (statement[context => "$arg{context}|case"])(s)
          { 
            my $last = pop @{$item[-1]};
            my $statements = join('', @{$item[-1]});
            if (length $statements and $statements !~ /Exit switch block\.\s*$/) {
              $statements .= "Fall through to the next case.\n";
            } elsif (not length $statements and not $last) {
              $statements = "Do nothing.\n";
            }
            $return = "If it has the value $item[-2], ^L$statements$last";
          }
    | 'default' ':' statement 
          { $return = "In the default case, ^L$item{statement}"; } 

expression:
      <leftop: assignment_expression ',' assignment_expression>
          {
            if ($arg{context} eq 'for increment statement'
                or $arg{context} eq 'for init') {
              $return = join(', then ', @{$item[-1]});
            } elsif ( $arg{context} =~ /conditional/) {
              $return = join(' and the result discarded and ', @{$item[-1]});
            } else {
              $return .= "Evaluate " if @{$item[-1]} > 1;
              $return .= join(" and discard the result and then evaluate ^L", @{$item[-1]}); 
            }
          }

assignment_expression:
      unary_expression[context => 'assignment expression'] 
        assignment_operator
        assignment_expression[context => 'assignment expression'] 
          {
            my $assignment_expression = $item{assignment_expression}; 
            my $assignment_operator = $item{assignment_operator};

            if (ref $assignment_operator eq 'ARRAY') {
              $return .= "${$item{assignment_operator}}[0] $item{unary_expression} ";
              ${$item{assignment_operator}}[1] =~ s/the value/the result of the expression/ if $assignment_expression =~ / /;
              $return .= "${$item{assignment_operator}}[1] " if $assignment_expression !~ /the result of/;
              $return .= $assignment_expression;
            } else {
              $return = "$item{unary_expression} $assignment_operator $assignment_expression"; 
            } 
          } 
    | conditional_expression

conditional_expression:
      logical_OR_AND_expression conditional_ternary_expression
          {
            if ($item{conditional_ternary_expression}) {
              my $op1 = $item{conditional_ternary_expression}->[0];
              my $op2 = $item{conditional_ternary_expression}->[1];
              my $expression = ::istrue $item{logical_OR_AND_expression};

              if ($arg{context} =~ /initializer expression$/) {
                $return = "$op1 if $expression otherwise to $op2";
              } elsif ($arg{context} =~ /assignment expression$/) {
                $return = "$op1 if $expression otherwise the value $op2";
              } else {
                $return = "$op1 if $expression otherwise $op2";
              }
            } else {
              $return = $item{logical_OR_AND_expression};
            }
          }

conditional_ternary_expression:
      '?' expression ':' conditional_expression
          { $return = [$item{expression}, $item{conditional_expression}]; } 
    | {""}

assignment_operator:
      '=' 
          {
            if ($arg{context} =~ /for init/) {
              $return = ['assigning to^L', 'the value^L' ];
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Assign to^L', 'the value^L' ]; 
            } else { 
              $return = 'which is assigned to be^L'; 
            }
          }
    | '+=' 
          {
            if ($arg{context} =~ /for init/) { 
              $return = ['incrementing^L','by^L'];
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Increment^L','by^L'];
            } else { 
              $return = 'which is incremented by^L'; 
            }
          }
    | '-='
          {
            if ($arg{context} =~ /for init/) { 
              $return = ['decrementing^L' , 'by^L']; 
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Decrement^L', 'by^L']; 
            } else { 
              $return = 'which is decremented by^L'; 
            }
          }
    | '*='
          {
            if ($arg{context} =~ /for init/) { 
              $return = ['multiplying^L' , 'by^L'];
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Multiply^L' , 'by^L'];  
            } else { 
              $return = 'which is multiplied by^L'; 
            }
          }
    | '/='
          { 
            if ($arg{context} =~ /for init/) {  
              $return = ['dividing^L' , 'by^L' ]; 
            } elsif ($arg{context} =~ /statement$/) {  
              $return = ['Divide^L' , 'by^L' ]; 
            } else { 
              $return = 'which is divided by^L'; 
            }
          }
    | '%=' 
          { 
            if ($arg{context} =~ /for init/) { 
              $return = ['reducing^L', 'to modulo ^L'] ;  
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Reduce^L', 'to modulo ^L'] ;  
            } else { 
              $return = 'which is reduced to modulo^L'; 
            }
          }
    | '<<='
          { 
            if ($arg{context} =~ /for init/) { 
              $return = ['bit-shifting^L', 'left by^L'];  
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Bit-shift^L', 'left by^L'];  
            } else { 
              $return = 'which is bit-shifted left by^L'; 
            }
          }
    | '>>='
          { 
            if ($arg{context} =~ /for init/) { 
              $return = ['bit-shifting^L', 'right by^L'];  
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Bit-shift^L', 'right by^L'];  
            } else { 
              $return = 'which is bit-shifted right by^L'; 
            }
          }
    | '&='
          { 
            if ($arg{context} =~ /for init/) { 
              $return = ['bitwise-ANDing^L', 'by^L' ];  
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Bitwise-AND^L', 'by^L' ];  
            } else { 
              $return = 'which is bitwise-ANDed by^L'; 
            }
          }
    | '^='
          { 
            if ($arg{context} =~ /for init/) { 
              $return = ['exclusive-ORing^L','by^L'];
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Exclusive-OR^L','by^L'];
            } else { 
              $return = 'which is exclusive-ORed by^L'; 
            }
          }
    | '|='
          { 
            if ($arg{context} =~ /for init/) { 
              $return = ['bitwise-ORing^L', 'by^L'];  
            } elsif ($arg{context} =~ /statement$/) { 
              $return = ['Bitwise-OR^L', 'by^L'];  
            } else { 
              $return = 'which is bitwise-ORed by^L'; 
            }
          }

constant_expression:
      conditional_expression

logical_OR_AND_expression:
      <leftop:
        rel_add_mul_shift_expression
        log_OR_AND_bit_or_and_eq
        rel_add_mul_shift_expression[context => 'logical_OR_AND_expression']>
          {
            my $expression = join('', @{$item[1]});
            if($arg{context} =~ /initializer expression$/
                and $expression =~ / /
                and $expression !~ /^the .*? constant \S+$/i
                and $expression !~ /the size of/i
                and $expression !~ /the offset/i
                and $expression !~ /the address of/i
                and $expression !~ /^the result of the/) {
              $return = 'the result of the expression ^L';
            }
            $return .= $expression;
          } 

log_OR_AND_bit_or_and_eq: 
      '||' { $return = ' or ^L'; }
    | '&&' { $return = ' and ^L'; }
    | '|'  { $return = ' bitwise-ORed by ^L'; }
    | '&'  { $return = ' bitwise-ANDed by ^L'; }
    | '^'  { $return = ' bitwise-XORed by ^L';}
    | '==' { $return = ' is equal to ^L'; }
    | '!=' { $return = ' is not equal to ^L'; } 

rel_mul_add_ex_op: 
      '+'  { $return = ' plus ^L'; }
    | '-'  { $return = ' minus ^L'; }
    | '*'  { $return = ' times ^L'; }
    | '/'  { $return = ' divided by ^L'; }
    | '%'  { $return = ' modulo ^L'; }
    | '<<' { $return = ' shifted left by ^L'; }
    | '>>' { $return = ' shifted right by ^L'; }
    | '>=' { $return = ' is greater than or equal to ^L'; }
    | "<=" { $return = ' is less than or equal to ^L'; }
    | '>'  { $return = ' is greater than ^L'; }
    | '<'  { $return = ' is less than ^L'; }

unary_operator: 
      '&' { $return = 'the address of ^L'; }
    | '*' { $return = 'the dereference of ^L'; }
    | '+' { $return = ''; }
    | '-' ...identifier { $return  = 'negative ^L'; }
    | '-' { $return = 'minus ^L'; }
    | '~' { $return = "the one's complement of ^L"; }
    | '!' '!' { $return = 'the normalized boolean value of ^L'; }
    | '!' 
          { 
            if ($arg{context} =~ /conditional/) {
              $return = ['', ' is false'];
            } else {
              $return = 'the logical negation of ^L';
            }
          }

rel_add_mul_shift_expression:
      cast_expression ...';'
          { $return = $item{cast_expression}; }
    | <leftop: cast_expression rel_mul_add_ex_op cast_expression>
          { $return = join('', @{$item[1]}); }

closure: 
      ',' | ';' | ')' 

cast_expression:
      '(' type_name ')' cast_expression[context => 'recast']
          { $return = "$item{cast_expression} converted to $item{type_name}"; }
    | unary_expression 
          { $return = $item{unary_expression}; } 

Static_assert:
      '_Static_assert'
    | 'static_assert'

static_assert_declaration:
      Static_assert '(' constant_expression[context => 'static assert'] ',' string ')' ';'
          {
            my $expression  = ::istrue $item{constant_expression};
            $return = "Halt compilation and produce the diagnostic $item{string} unless $expression.\n";
          }

declaration_list: 
      preproc[context => 'statement'](?) declaration(s) 
          { $return = join('', @{$item{'preproc(?)'}}) . join('', @{$item{'declaration(s)'}}); }

declaration:
      declaration_specifiers init_declarator_list(?) ';'
          {
            my @init_list = defined $item{'init_declarator_list(?)'}->[0] ? @{$item{'init_declarator_list(?)'}->[0]} : ('');
            my $typedef = $item{declaration_specifiers} =~ s/^type definition of //;
            my $noreturn = $item{declaration_specifiers} =~ s/_Noreturn//g;
            $item{declaration_specifiers} = join(' ', split(' ', $item{declaration_specifiers}));

            if ($noreturn) {
              if($item{declaration_specifiers} eq 'void') {
                $item{declaration_specifiers} = "which doesn't return to its caller";
              } else {
                $item{declaration_specifiers} = "which shouldn't return to its caller yet does mysteriously return $item{declaration_specifiers}";
              }
            }

            my $inits = 0;
            while (@init_list) {
              $inits++;
              if (not $arg{context} eq 'struct member') {
                if ($arg{context} eq 'for init') {
                  $return .= "declaring ";
                } else {
                  $return .= "Declare ";
                }
              }

              my @args = ::flatten shift @init_list;

              my ($first_qualifier, $first_initializer);
              my $first_identifier = shift @args;

              my @identifiers = ($first_identifier) unless not length $first_identifier;

              foreach my $arg (@args) {
                if ($arg =~ /initialized/) {
                  $first_initializer .= (length $first_initializer ? ' ' : '') . $arg;
                } else {
                  $first_qualifier .= (length $first_qualifier ? ' ' : '') . $arg;
                }
              }

              my @initializers;
              if ($first_initializer) {
                push @initializers, [ $first_identifier, $first_initializer ];
              }

              for (my $i = 0; $i < @init_list; $i++) {
                @args = ::flatten $init_list[$i];

                my ($qualifier, $initializer);
                my $identifier = shift @args;

                foreach my $arg (@args) {
                  if ($arg =~ /initialized/) {
                    $initializer .= (length $initializer ? ' ' : '') . $arg;
                  } else {
                    $qualifier .= (length $qualifier ? ' ' : '') . $arg;
                  }
                }

                next unless $qualifier eq $first_qualifier;

                push @identifiers, $identifier;
                if ($initializer) {
                  push @initializers, [ $identifier, $initializer ];
                }

                splice @init_list, $i--, 1;
              }

              if ($arg{context} eq 'struct member') {
                if ($inits > 1 and not @init_list) {
                  $return .= ' and ';
                } elsif ($inits > 1) {
                  $return .= ', ';
                }

                my $and = @identifiers > 1 ? ' and ' : '';
                my $comma = '';
                for (my $i = 0; $i < @identifiers; $i++) {
                  if ($i == @identifiers - 1) {
                    $return .= "$and$identifiers[$i]";
                  } else {
                    $return .= "$comma$identifiers[$i]";
                    $comma = ', ';
                  }
                }

                $return .= ' as ' unless not @identifiers;

                if ($first_qualifier) {
                  if ($first_qualifier =~ /bit\-field/) {
                    $first_qualifier = "$item{declaration_specifiers} $first_qualifier";
                    $item{declaration_specifiers} = '';
                  }

                  if (@identifiers == 1 and $first_qualifier !~ /^(an|a)\s+/) {
                    $return .= $first_qualifier =~ m/^[aeiou]/ ? 'an ' : 'a ';
                  } elsif (@identifiers > 1 and not $typedef) {
                    $first_qualifier =~ s/pointer/pointers/;
                    $first_qualifier =~ s/an array/arrays/;
                  }
                  $return .= "$first_qualifier";
                  $return .= " $item{declaration_specifiers}" if $item{declaration_specifiers};
                } else {
                  if (@identifiers == 1 and $item{declaration_specifiers} !~ /^(an|a)\s+/) {
                    $return .= $item{declaration_specifiers} =~ m/^[aeiou]/ ? 'an ' : 'a ';
                  }
                  $return .= $item{declaration_specifiers};
                }
              } else {
                my $and = @identifiers > 1 ? ' and ' : '';
                my $comma = '';
                for (my $i = 0; $i < @identifiers; $i++) {
                  if ($i == @identifiers - 1) {
                    $return .= "$and$identifiers[$i]";
                  } else {
                    $return .= "$comma$identifiers[$i]";
                    $comma = ', ';
                  }
                }

                if ($typedef) {
                  $return .= ' each' if @identifiers > 1;
                  $return .= ' as another name for ';
                  push @typedefs, @identifiers;
                } else {
                  $return .= ' as ' unless not @identifiers;
                }

                if ($first_qualifier) {
                  if ($noreturn) {
                    $first_qualifier =~ s/ returning$//;
                  }

                  if (@identifiers == 1 and $first_qualifier !~ /^(an|a)\s+/) {
                    $return .= $first_qualifier =~ m/^[aeiou]/ ? 'an ' : 'a ';
                  } elsif (@identifiers > 1 and not $typedef) {
                    $first_qualifier =~ s/pointer/pointers/;
                    $first_qualifier =~ s/an array/arrays/;
                  }
                  $return .= "$first_qualifier ";
                  $return .= $item{declaration_specifiers};
                } else {
                  if (@identifiers == 1 and $item{declaration_specifiers} !~ /^(an|a)\s+/) {
                    $return .= $item{declaration_specifiers} =~ m/^[aeiou]/ ? 'an ' : 'a ';
                  }
                  $return .= $item{declaration_specifiers};
                }

                if (@initializers) {
                  if (@identifiers > 1) {
                    $return .= ".\nInitialize ";

                    @initializers = sort { $a->[1] cmp $b->[1] } @initializers;
                    my ($and, $comma);

                    for (my $i = 0; $i < @initializers; $i++) {
                      my ($identifier, $initializer) = @{$initializers[$i]};

                      if ($i < @initializers - 1 and $initializer eq $initializers[$i + 1]->[1]) {
                        $return .= "$comma$identifier";
                        $comma = ', ';
                        $and = ' and ';
                      } else {
                        $initializer =~ s/^initialized to \^L//;
                        $return .= "$and$identifier to $initializer";
                        if ($i < @initializers - 2) {
                          $and = $comma = ', ';
                        } else {
                          $and = ' and ';
                        }
                      }
                    }
                  } else {
                    $return .= " $initializers[0]->[1]";
                  }
                }
                $return =~ s/,$//;
                $return .= ".\n" unless $arg{context} eq 'for init';
              }
            }
          }
    | static_assert_declaration

init_declarator_list:
      <leftop: init_declarator ',' init_declarator> 

init_declarator:
      declarator[context => "$arg{context}|init_declarator"]
          {
            $return = $item{declarator};
          }
      ('=' initializer)(?) 
          {
            my $init = join('',@{$item[-1]});  

            if (length $init) {
              $return = [$item{declarator}, "initialized to ^L$init"]; 
            }
          }

initializer:
      designation initializer
          { $return = "$item[1] $item[2]"; }
    | comment(?) assignment_expression[context => "$arg{context}|initializer expression"] comment(?)
          {
            $return = $item[2]; 

            if (join('',@{$item[1]})) { 
              $return = '['.join('',@{$item[1]}).']' . $return;   
            }

            if (join('',@{$item[1]})) { 
              $return .= join('',@{$item[-1]}); 
            }
          } 
    | '{' comment(?) initializer_list (',' )(?) '}'
          { $return = '{ ' . $item{'initializer_list'} . ' }'; }

initializer_list:
      <leftop: initializer ',' initializer > 
          { $return = join(', ', @{$item[1]}); }

designation:
      designator_list '='
          { $return = $item{designator_list}; }

designator_list:
      designator(s)
          { 
            $return = join(' of ', reverse @{$item{'designator(s)'}});
            $return .= ' set to';
          }

designator:
      '[' constant_expression ']'
          {
            my $expression = $item{constant_expression};
            if ($expression =~ /^\d+$/) {
              $expression++;
              my ($last_digit) = $expression =~ /(\d)$/;
              if ($last_digit == 1) {
                if ($expression =~ /11$/) {
                  $expression .= 'th';
                } else {
                  $expression .= 'st'; 
                }
              } elsif ($last_digit == 2) {
                $expression .= 'nd';
              } elsif ($last_digit == 3) {
                $expression .= 'rd';
              } else {
                $expression .= 'th';
              }
              $expression = "the $expression element";
            } else {
              $expression = "the element at location ^L$expression^L";
            }

            $return = $expression;
          }
    | '.' identifier
          { $return = "the member $item{identifier}"; }

unary_expression:
      postfix_expression
          { $return = $item{postfix_expression}; }
    | '++' unary_expression
          {
            if ($arg{context} =~ /for init/) {
              $return = "pre-incrementing $item{unary_expression}"; 
            } elsif ($arg{context} =~ /(conditional|expression)/) { 
              if ($item{unary_expression} =~ s/^the member//) {
                $return = "the pre-incremented member $item{unary_expression}";
              } elsif ($item{unary_expression} =~ s/^the element//) {
                $return = "the pre-incremented element $item{unary_expression}";
              }else {
                $return = "pre-incremented $item{unary_expression}";
              }
            } else {
              $return = "pre-increment $item{unary_expression}"; 
            }
          }
    | '--' unary_expression  
          {
            if ($arg{context} =~ /for init/) {
              $return = "pre-decrementing $item{unary_expression}"; 
            } elsif ($arg{context} =~ /(conditional|expression)/) { 
              if ($item{unary_expression} =~ s/^the member//) {
                $return = "the pre-decremented member $item{unary_expression}";
              } elsif ($item{unary_expression} =~ s/^the element//) {
                $return = "the pre-decremented element $item{unary_expression}";
              } else {
                $return = "pre-decremented $item{unary_expression}";
              }
            } else {
              $return = "Pre-decrement $item{unary_expression}"; 
            }
          }
    | unary_operator cast_expression
          { 
            if (ref $item{unary_operator} eq 'ARRAY') {
              $return = $item{unary_operator}->[0] . $item{cast_expression} . $item{unary_operator}->[1];
            } else {
              $return = $item{unary_operator} . $item{cast_expression};
            }
          }
    | 'sizeof' unary_expression[context => 'sizeof'] 
          {
            if ($arg{context} =~ /statement$/) {
              $return = "Evaluate and discard the size of ^L$item{unary_expression}";
            } else {
              $return = "the size of ^L$item{unary_expression}";
            }
          }
    | 'sizeof' '(' type_name[context => 'sizeof'] ')' 
          {
            if ($arg{context} =~ /statement$/) {
              $return = "Evaluate and discard the size of the type $item{type_name}";
            } else {
              $return = "the size of the type $item{type_name}";
            }
          }
    | 'sizeof' '(' assignment_expression[context => 'sizeof'] ')' 
          {
            if ($arg{context} =~ /statement$/) {
              $return = "Evaluate and discard the size of the type of the expression (^L$item{assignment_expression})";
            } else {
              $return = "the size of the type of the expression (^L$item{assignment_expression})";
            }
          }
    | Alignof '(' type_name ')'
          { $return = "the alignment of the type $item{type_name}"; }
    | 'offsetof' '(' type_name[context => 'offsetof'] ',' identifier ')'
          {
            $return = "the offset, in bytes, of member $item{identifier} from the beginning of $item{type_name}";
          }

Alignof:
      '_Alignof'
    | 'alignof'

postfix_productions:
      '(' argument_expression_list(?) ')' postfix_productions[context => 'function call'](?)
          {
            my $postfix = $item[-1]->[0];

            $arg{primary_expression} =~ s/^Evaluate the expression/resulting from the expression/;

            if($arg{context} =~ /statement$/) {
              $return = "Call the function $arg{primary_expression}";
            } else {
              $return = "the result of the function $arg{primary_expression}";
            }

            # To discriminate between macros and functions. 
            foreach (@macros) { 
              if ($arg{primary_expression} eq $_) { 
                $return =~ s/Call/Insert/;
                $return =~ s/function/macro/; 
              }
            }

            my $arg_exp_list = join('',@{$item{'argument_expression_list(?)'}}); 
            if (length $arg_exp_list) { 
              $return .= " with argument$arg_exp_list";
            }

            if ($postfix) { 
              $return =~ s/^(Call|Insert)/the result of/;
              $return = "$postfix $return"; 
            }
            1;
          }
    | '[' expression[context => 'array address'] ']' postfix_productions[context => "$arg{context}|array address"](?)
          {
            my $expression = $item[2];
            my $postfix = $item[-1]->[0];

            if (length $expression) { 
              if ($expression =~ /^\d+$/) {
                $expression++;
                my ($last_digit) = $expression =~ /(\d)$/;
                if ($last_digit == 1) {
                  if ($expression =~ /11$/) {
                    $expression .= 'th';
                  } else {
                    $expression .= 'st'; 
                  }
                } elsif ($last_digit == 2) {
                  $expression .= 'nd';
                } elsif ($last_digit == 3) {
                  $expression .= 'rd';
                } else {
                  $expression .= 'th';
                }
                if ($arg{context} eq 'function call') {
                  $return = "the $expression element of^L";
                } else {
                  $return = "the $expression element of^L";
                  $return .= " $arg{primary_expression}" if $arg{primary_expression};
                }
              } elsif ($expression =~ /^-\s*\d+$/) {
                $expression *= -1;
                my $plural = $expression == 1 ? '' : 's';
                $return = "the element $expression element$plural backwards from where ^L$arg{primary_expression} points^L";
              } else {
                $return = "the element at location ^L$expression of^L";
                $return .= " $arg{primary_expression}" if $arg{primary_expression};
              }
            }

            if ($postfix) {
              $return = "$postfix $return";
              $return =~ s/the post-([^ ]+) the/the post-$1/g;
            }
          }
    | '.' identifier postfix_productions[context => "$arg{context}|struct access"](?)
          { 
            my $identifier = $item[-2]; 
            my $postfix = $item[-1]->[0];

            if ($postfix) {
              if (ref $postfix eq 'ARRAY') {
                $return = "$postfix->[0] the member $identifier $postfix->[1] of";
              } else {
                if ($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "$postfix member $identifier of";
                  $return .= " the" unless $arg{context} =~ /array address/;
                } else {
                  $postfix =~ s/ the(\^L)?$/$1/;
                  $return = "$postfix the member $identifier of";
                  $return .= " the" unless $arg{context} =~ /array address/;
                }
                if ($arg{primary_expression}) { 
                  $return =~ s/ the(\^L)?$/$1/;
                  $return .= " ^L$arg{primary_expression}"
                }
              }
            } else {
              if ($arg{context} =~ /array address/) {
                $return = "the member $identifier of^L";
              } else {
                $return = "the member $identifier of the^L";
                if ($arg{primary_expression}) {
                  $return =~ s/ the(\^L)?$/$1/;
                  $return .= " $arg{primary_expression}";
                }
              }
            }
            1;
          } 
    | '->' identifier postfix_productions[context => "$arg{context}|struct access"](?) 
          {
            my $identifier = $item[-2]; 
            my $postfix = $item[-1]->[0];

            if ($postfix) {
              if (ref $postfix eq 'ARRAY') {
                $return = "$postfix->[0] the member $identifier $postfix->[1] of the structure pointed to by^L";
              } else {
                if ($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "$postfix member $identifier of the structure pointed to by the^L";
                } else {
                  $postfix =~ s/ the(\^L)?$/$1/;
                  $return = "$postfix the member $identifier of the structure pointed to by the^L";
                }
              }
            } else {
              $return = "the member $identifier of the structure pointed to by the^L";
            }
            if ($arg{primary_expression}) {
              $return =~ s/ the(\^L)?$/$1/;
              $return .= " $arg{primary_expression}";
            }
            1;
          }
    | ('++')(s)
          {
            my $increment = join('',@{$item[-1]}); 
            if ($increment) {
              if ($arg{context} =~ /(struct access|array address)/) {
                if ($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "the post-incremented";
                } else {
                  $return = "post-increment";
                }
              } elsif ($arg{context} =~ /for init/) {
                $return = ['incrementing', 'by one'];
              } elsif ($arg{context} =~ /(conditional|expression)/) {
                $return = "post-incremented $arg{primary_expression}";
              } else {
                $return = ['increment', 'by one'];
              }
            }
          }
    | ('--')(s)
          {
            my $increment = join('',@{$item[-1]}); 
            if ($increment) {
              if ($arg{context} =~ /(struct access|array address)/) {
                if ($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "the post-decremented";
                } else {
                  $return = "post-decrement";
                }
              } elsif ($arg{context} =~ /for init/) {
                $return = ['decrementing', 'by one'];
              } elsif ($arg{context} =~ /(conditional|expression)/) {
               $return = "post-decremented $arg{primary_expression}";
              } else {
                $return = ['decrement', 'by one'];
              }
            }
          }
    | {""}

postfix_expression:
      '(' type_name ')' '{' initializer_list '}' postfix_productions[context => "$arg{context}|compound literal"](?)
          {
            my $postfix = $item[-1]->[0];
            $return = "A compound-literal of type $item{type_name} initialized to { $item{initializer_list} }";
            $return = "$postfix $return" if $postfix;
          }
    | primary_expression postfix_productions[primary_expression => $item[1], context => $arg{context}]
          {
            my $postfix_productions = $item{'postfix_productions'};

            if (ref $postfix_productions eq 'ARRAY') {
              $return = "$postfix_productions->[0] $item{primary_expression} $postfix_productions->[1]";
            } elsif (length $postfix_productions) {
              $return = $postfix_productions;
            } elsif (length $item{primary_expression}) {
              $return = $item{primary_expression}; 
            } else {
              $return = undef;
            }
          }

postfix_suffix:
      '[' expression ']'
    | '.' identifier
    | '->' identifier
    | '++'
    | '--'

argument_expression_list:
      <leftop: assignment_expression[context => 'function argument'] ',' assignment_expression[context => 'function argument']>
          {
            my @arg_exp_list = @{$item[1]}; 
            my $last = ''; 
            if (@arg_exp_list > 2) {
              $last = pop @arg_exp_list; 
              $return = 's ' . join(', ^L', @arg_exp_list) . ", and ^L$last";
            } elsif (@arg_exp_list == 2 ) { 
              $return = "s ^L$arg_exp_list[0] and ^L$arg_exp_list[1]";  
            } else {
              if (length $arg_exp_list[0]) {
                $return = " ^L$arg_exp_list[0]";
              } else {
                $return = '';
              }
            }
          }

narrow_closure:
      ';' | ',' | '->'

primary_expression:
      '(' expression[context => "$arg{context}|expression"] ')' (...narrow_closure)(?)
          { 
            my $expression = $item{expression} ; 
            my $repeats = 1; 

            if ($expression =~ /^The expression (\(+)/) { 
              $repeats = (length $1) + 1; 
              $expression =~ s/^The expression \(+//;
            }

            $expression .= ')';
            if ($arg{context} =~ /statement$/) {
              $return = "Evaluate the expression ";
            } else {
              #$return = "The result of the expression ";
            }
            $return .= '(' x $repeats;
            $return .= "^L$expression";
          }
    | constant
    | string 
    | identifier
    | generic_selection
    | {} # nothing

generic_selection:
      '_Generic' '(' assignment_expression ',' generic_assoc_list ')'
          { $return = "a generic-selection on $item{assignment_expression} yielding $item{generic_assoc_list}"; }

generic_assoc_list:
      <leftop: generic_association ',' generic_association>
          { 
            if (@{$item[-1]} == 1) {
              $return = $item[-1]->[0];
            } else {
              my $last = pop @{$item[-1]};
              $return = join(', ', @{$item[-1]}) . " and $last";
            }
          }

generic_association:
      type_name ':' assignment_expression
          { $return = "$item{assignment_expression} in the case that it has type $item{type_name}"; }
    | 'default' ':' assignment_expression
          { $return = "$item{assignment_expression} in the default case"; }

Alignas:
      '_Alignas'
    | 'alignas'

alignment_specifier:
      Alignas '(' type_name ')'
          {
            $return = "with alignment of the type $item{type_name}";
          }
    | Alignas '(' constant_expression ')'
          {
            my $plural = $item{constant_expression} != 1 ? 's' : '';
            $return = "with alignment of $item{constant_expression} byte$plural between objects";
          }

declarator:
      direct_declarator(s)
          { 
            my @direct_declarator = @{$item{'direct_declarator(s)'}};
            if (@direct_declarator == 1) {
              $return = $direct_declarator[0]; 
            } else {
              $return = $item{'direct_declarator(s)'};
            }
          }
    | pointer direct_declarator(s)
          { 
            push @{$item{'direct_declarator(s)'}}, $item{pointer};
            $return = $item{'direct_declarator(s)'};
          }

direct_declarator:
      identifier ':' constant
          { 
            my $bits = $item{constant} == 1 ? "$item{constant} bit" : "$item{constant} bits";
            $return = [$item{identifier}, "bit-field of $bits"];
          }
    | identifier[context => 'direct_declarator'] array_declarator(s?)
          { 
            if (@{$item{'array_declarator(s?)'}}) {
              $return = [$item{identifier}, join(' ', @{$item{'array_declarator(s?)'}})];
            } else {
              $return = $item{identifier};
            }
          }
    | '(' declarator ')' array_declarator(s)
          { 
            push @{$item{declarator}}, join(' ', @{$item{'array_declarator(s)'}});
            $return = $item{declarator};
          }
    | '(' parameter_type_list ')'
          { $return = "function taking $item{parameter_type_list} and returning"; }
    | '(' declarator array_declarator(s) ')'
          { $return = $item{'declarator'} . join(' ', @{$item{'array_declarator(s)'}}) }
    | '(' declarator ')' 
          { $return = $item{declarator}; }

array_qualifiers:
      type_qualifier_list array_qualifiers(?)
          { 
            $return = $item{'type_qualifier_list'};
            my $qualifiers = join('', @{$item{'array_qualifiers(?)'}});
            $return .= " $qualifiers" if $qualifiers;
          }
    | 'static' array_qualifiers(?)
          { 
            $return = $item[1];
            my $qualifiers = join('', @{$item{'array_qualifiers(?)'}});
            $return .= " $qualifiers" if $qualifiers;
          }

array_declarator:
      '[' array_qualifiers(?) assignment_expression(?) ']'
          {
            my $size;
            if (@{$item{'assignment_expression(?)'}}) {
              $size = join('', @{$item{'assignment_expression(?)'}});
              if ($size =~ /^(unsigned|long)*\s*1$/) {
                $size = "$size element";
              } else {
                $size = "$size elements";
              }
            } else {
              if ($arg{context} =~ /struct member/) {
                $size = 'flexible length';
              } else {
                $size = 'unspecified length';
              }
            }

            my $qualifiers = join('', @{$item{'array_qualifiers(?)'}});

            if ($qualifiers) {
              if($qualifiers =~ s/static//g) {
                $qualifiers = join(' ', split(' ', $qualifiers));
                if($qualifiers) {
                  $return = "a $qualifiers array ";
                } else {
                  $return = "an array ";
                }
                $return .= "with optimization hint to provide access to the first element of $size of";
              } else {
                $return = "an $qualifiers array of $size of";
              }
            } else {
              $return = "an array of $size of";
            }
          }
    | '[' '*' ']'
          { $return = 'an array of variable length of unspecified size of'; }

identifier_list:
      (identifier ',')(s?) identifier
          {
            my @identifier_list = @{$item[1]}; 
            if ($#identifier_list > 1) {
              $return = join(', ', @identifier_list) . ', and ' . $item{identifier};  
            } elsif ($#identifier_list == 1) { 
              $return = $identifier_list[1] . ' and ' . $item{identifier};  
            } else { 
              $return = $item{identifier};  
            }
          }

parameter_type_list:
      parameter_list

parameter_list:
      <leftop: parameter_declaration ',' parameter_declaration>
          {
            my @parameter_list = @{$item[1]};
            my $comma = '';
            for (my $i = 0; $i < @parameter_list; $i++) {
              $return .= $comma;
              if (ref $parameter_list[$i] eq 'ARRAY') {
                my @list = ::flatten @{$parameter_list[$i]};
                if (@list == 0) {
                  $return = "no arguments";
                } elsif (@list ==  1) {
                  if ($list[0] eq 'void') {
                    $return = "no arguments";
                  } else {
                    $return .= $list[0];
                  }
                } else {
                  push @list, shift @list;
                  if ($list[0] =~ /^`.*`$/) {
                    my $identifier = shift @list;
                    $return .= "$identifier as ";
                    $return .= join(' ', @list);
                  } else {
                    $return .= join(' ', @list);
                  }
                }
              } else {
                $return .= $parameter_list[$i];
              }

              if ($i == $#parameter_list - 1) {
                $comma = ' and ';
              } else {
                $comma = ', ';
              }
            }
          }

parameter_declaration:
      declaration_specifiers declarator 
          { $return = [$item{declaration_specifiers}, $item{declarator}]; }
    | '...'
          { $return = "variadic arguments"; }
    | declaration_specifiers abstract_declarator(?) 
          { $return = [$item{declaration_specifiers}, $item{'abstract_declarator(?)'}]; }
    | ''
          { $return = "unspecified arguments"; }

abstract_declarator: 
      pointer(?) direct_abstract_declarator(s) 
          { 
            my $pointer = join(' ', @{$item{'pointer(?)'}});
            $return = "$pointer " if $pointer;
            $return .= join(' ', @{$item{'direct_abstract_declarator(s)'}});
          }
    | pointer 

direct_abstract_declarator:
      '(' abstract_declarator ')'
          { $return = $item{abstract_declarator}; }
    | '[' ']'
          { $return = 'array of unspecified length of'; }
    | '[' '*' ']'
          { $return = 'array of variable length of unspecified size of'; }
    | '[' array_qualifiers(?) assignment_expression(?) ']'
          {
            my $size;
            if (@{$item{'assignment_expression(?)'}}) {
              $size = join('', @{$item{'assignment_expression(?)'}});
              if ($size =~ /^(unsigned|long)*\s*1$/) {
                $size = "$size element";
              } else {
                $size = "$size elements";
              }
            } else {
              $size = 'unspecified length';
            }

            my $qualifiers = join('', @{$item{'array_qualifiers(?)'}});

            if ($qualifiers) {
              if($qualifiers =~ s/static//g) {
                $qualifiers = join(' ', split(' ', $qualifiers));
                if($qualifiers) {
                  $return = "a $qualifiers array ";
                } else {
                  $return = "an array ";
                }
                $return .= "with optimization hint to provide access to the first element of $size of";
              } else {
                $return = "an $qualifiers array of $size of";
              }
            } else {
              $return = "an array of $size of";
            }
          }
    | DAD '[' ']'
    | DAD '[' array_qualifiers(?) assignment_expression(?) ']'
    | '(' ')'
          { $return = 'function taking unspecified arguments and returning'; }
    | '(' parameter_type_list ')'
          { $return = "function taking $item{parameter_type_list} and returning"; }
    | DAD '(' ')'
    | DAD '(' parameter_type_list ')'

DAD: # macro for direct_abstract_declarator 
      ( '(' abstract_declarator ')' )(s?)
      ( '[' ']' )(s?)
      ( '[' assignment_expression ']' )(s?)
      ( '(' ')' )(s?)
      ( '(' parameter_type_list ')' )(s?)

identifier: 
      ...!reserved identifier_word
          {
            if (not grep { $_ eq $item{identifier_word} } @identifiers) {
              push @identifiers, $item{identifier_word};
            }
            $return = $item{identifier_word};
          }

pointer:
      '*' type_qualifier_list(s) pointer(?) 
          { 
            $return = join('', @{$item{'pointer(?)'}}) if @{$item{'pointer(?)'}};
            $return .= ' ' .  join('', @{$item{'type_qualifier_list(s)'}}) . ' pointer to';
          }
    | '*' pointer(?) 
          { 
            my $pointers = join('', @{$item{'pointer(?)'}});
            $return .= "$pointers " if $pointers;
            $return .= 'pointer to'; 
          } 
 
type_qualifier_list:
      type_qualifier(s) 
          { $return = join(' ', @{$item{'type_qualifier(s)'}}); }

function_specifier:
      'inline'
    | '_Noreturn'
    | 'noreturn'
          { $return = '_Noreturn'; }

declaration_specifiers:
      comment[context => 'declaration_specifiers'] declaration_specifiers(s)
          { $return = "$item{comment} " . join(' ', @{$item{'declaration_specifiers(s)'}}); }
    | type_specifier ...identifier
          { $return = $item{type_specifier}; }
    | storage_class_specifier declaration_specifiers(?) 
          {
            my $decl_spec =  join(' ', @{$item{'declaration_specifiers(?)'}});
            if ($item{storage_class_specifier} =~ m/^with/) {
              if ($decl_spec) { $return .=  "$decl_spec "; } 
              $return .= $item{storage_class_specifier};
            } else {
              $return .= $item{storage_class_specifier};
              if ($decl_spec) { $return .=  " $decl_spec"; }
            }
          }
    | type_specifier(s) declaration_specifiers(?) 
          {
            my $decl_spec = join(' ', @{$item{'declaration_specifiers(?)'}});
            if ($decl_spec =~ s/\s*(with.*)$//) {
              push @{$item{'type_specifier(s)'}}, $1;
            } 
            $return .= "$decl_spec " if $decl_spec;
            $return .= join(' ', @{$item{'type_specifier(s)'}});
          }
    | type_qualifier declaration_specifiers(?) 
          {
            my $decl_spec = join(' ',@{$item{'declaration_specifiers(?)'}});
            $return = $item{type_qualifier};
            $return .=  " $decl_spec" if $decl_spec;
          }
    | function_specifier declaration_specifiers(?)
          {
            my $decl_spec = join(' ',@{$item{'declaration_specifiers(?)'}});
            $return = $item{function_specifier};
            $return .=  " $decl_spec" if $decl_spec;
          }
    | alignment_specifier(s) declaration_specifiers(?)
          {
            my $decl_spec = join(' ',@{$item{'declaration_specifiers(?)'}});
            if ($decl_spec) {
              $return =  "$decl_spec ";
              $return .= 'or ' if $decl_spec =~ /with alignment/;
            }
            $return .= join(' or ', @{$item{'alignment_specifier(s)'}});
            $return .= ', whichever is more strict' if $return =~ /or with alignment/;
          }

storage_class_specifier:
      'auto'
          { $return = "with automatic storage-duration"; }
    | 'extern'
          {
            if ($arg{context} eq 'function definition') {
              $return = "with external linkage";
            } else {
              $return = "with external linkage, possibly defined elsewhere";
            }
          }
    | 'static' 
          { 
            if ($arg{context} eq 'function definition') {
              $return = "with internal linkage";
            } elsif ($arg{context} eq 'function definition statement') {
              $return = "with life-time duration";
            } else {
              $return = "with internal linkage and life-time duration";
            }
          }
    | 'register'
          { $return = "with a suggestion to be as fast as possible"; }
    | 'typedef'
          { $return = 'type definition of'; }

type_qualifier:
      'const'
    | 'volatile' 
    | 'restrict'
    | '_Atomic'
          { $return = 'atomic'; }

atomic_type_specifier:
      '_Atomic' '(' type_name ')'
          { $return = "atomic $item{type_name}"; }

type_specifier:
      <skip:''> /\s*/
        ('void'
          | 'signed' | 'unsigned'
          | 'FILE' | 'fpos_t'
          | 'bool' | '_Bool'
          | '_Complex' | '_Imaginary'
          | 'int_fast8_t'   | 'int_fast16_t'   | 'int_fast24_t'   | 'int_fast32_t'   | 'int_fast64_t'   | 'int_fast128_t'
          | 'uint_fast8_t'  | 'uint_fast16_t'  | 'uint_fast24_t'  | 'uint_fast32_t'  | 'uint_fast64_t'  | 'uint_fast128_t'
          | 'int_least8_t'  | 'int_least16_t'  | 'int_least24_t'  | 'int_least32_t'  | 'int_least64_t'  | 'int_least128_t'
          | 'uint_least8_t' | 'uint_least16_t' | 'uint_least24_t' | 'uint_least32_t' | 'uint_least64_t' | 'uint_least128_t'
          | 'int8_t'   | 'int16_t'  | 'int24_t'  | 'int32_t'  | 'int64_t'  | 'int128_t'
          | 'uint8_t'  | 'uint16_t' | 'uint24_t' | 'uint32_t' | 'uint64_t' | 'uint128_t'
          | 'intmax_t' | 'uintmax_t'
          | 'intptr_t' | 'uintptr_t' | 'ptrdiff_t'
          | 'sig_atomic_t'
          | 'wint_t' | 'wchar_t'
          | 'size_t' | 'rsize_t' | 'max_align_t'
          | 'mbstate_t' | 'char16_t' | 'char32_t'
          | 'fenv_t' | 'fexcept_t'
          | 'div_t' | 'ldiv_t' | 'lldiv_t' | 'imaxdiv_t'
          | 'cnd_t' | 'thrd_t' | 'tss_t' | 'mtx_t' | 'tss_dtor_t' | 'thrd_start_t' | 'once_flag'
          | 'clock_t' | 'time_t'
          | <skip:'[\s]*'> struct_or_union_specifier
          | <skip:'[\s]*'> enum_specifier
          | <skip:'[\s]*'> atomic_type_specifier | typedef_name
          | 'double' | 'float' | 'char' | 'short' | 'int' | 'long'
        ) .../\W/
          { $return = $item[3]; }

typedef_name:
      identifier
          {
            my $answer = 0; 
            foreach (@typedefs) { 
              if ($item{identifier} eq $_) {
                $answer = 1;      
                $return = ($item{identifier} =~ m/^`[aeiou]/ ? 'an ' : 'a ') . $item{identifier};
              } 
            }
            if (!$answer) { undef $answer; } 
            $answer;    
          }

struct_or_union_specifier:
      comment(?) struct_or_union identifier(?) '{' struct_declaration_list '}' 
          {
            my $identifier = join('',@{$item{'identifier(?)'}});
            $return = join('',@{$item{'comment(?)'}}) . $item{struct_or_union};
            if ($identifier) { $return .= " tagged $identifier"; } 
            my $plural = $item{struct_declaration_list} =~ / and (?!returning)/ ? 's' : '';
            $return .= ", with member$plural $item{struct_declaration_list},";
          }
    | struct_or_union identifier
          {
            $item{struct_or_union} =~ s/^(an|a)\s+//;
            $return = $item{identifier} =~ m/^`[aeiou]/ ? 'an' : 'a';
            $return .= " $item{identifier} $item{struct_or_union}";
          }

struct_declaration_list:
      struct_declaration(s)
          {
            my $finaldec;
            my @declarations = @{$item{'struct_declaration(s)'}}; 
            if ($#declarations > 1) { 
              $finaldec = pop @declarations; 
              $return = join(', ', @declarations ) . ', and ' . $finaldec ; 
            } elsif ($#declarations == 1) { 
              $return = join(' and ', @declarations);
            } else { 
              $return = $declarations[0]; 
            }
          } 

struct_declaration:
      comment(s?) declaration[context => 'struct member'] comment(s?)
          { $return = join('', @{$item[1]}) . $item{declaration} . join('', @{$item[-1]}); }

type_name:
        specifier_qualifier_list abstract_declarator(?)
          { 
            my $abstract_declarator = join('',@{$item{'abstract_declarator(?)'}});
            $return = "$abstract_declarator " if $abstract_declarator;
            $return .= $item{specifier_qualifier_list};
          }

specifier_qualifier_list:
      type_specifier specifier_qualifier_list(?) 
          { 
            $return = $item{type_specifier};
            $return .= ' ' . join('', @{$item{'specifier_qualifier_list(?)'}}) if @{$item{'specifier_qualifier_list(?)'}};
          }

struct_or_union:
      comment(?) ('struct' 
          { $return = 'a structure'; }
        | 'union'
          { $return = 'an union'; }
      ) comment(?) 
          {
            shift @item; 
            foreach (@item) { 
              if (ref($_)) { 
                $return .= join('',@{$_}); 
              } else { 
                $return .= $_; 
              }
            }
          }

enum_specifier:
      'enum' identifier(?) '{' enumerator_list '}' 
          {
            $return .= 'an enumeration'; 

            if (@{$item{'identifier(?)'}}){ 
              $return .= ' of ' . join('',@{$item{'identifier(?)'}});
            }

            my @enumerator_list = @{$item{enumerator_list}};

            if (@enumerator_list == 1) {
              $return .= " comprising $enumerator_list[0]";
            } else {
              my $last = pop @enumerator_list; 
              $return .= ' comprising ' . join(', ', @enumerator_list) . ", and $last"; 
            }

          }
    | 'enum' identifier
          { $return = "an enumeration of type $item{identifier}"; }

enumerator_list:
      <leftop:enumerator ',' enumerator>

enumerator:
      identifier ( '=' constant_expression )(?)
          {
            $return = $item[1]; 
             if (@{$item[-1]}) { 
               $return .= ' marking ^L' . join('', @{$item[-1]}); 
             }
           }

comment:
      comment_c 
    | comment_cxx

comment_c:
      m{/\*[^*]*\*+([^/*][^*]*\*+)*/}s
          {
            $return = $item[1];
            $return =~ s|^/\*+\s*||;
            $return =~ s|\s*\*+/$||;
            $return =~ s/"/\\"/g;
            if ($arg{context} =~ /statement/) {
              $return = "\nA comment: \"$return\".\n"; 
            } else {
              $return = "(a comment: \"$return\")"; 
            }
          }

comment_cxx:
      m{//(.*?)\n}
          { 
            $return = $item[1]; 
            $return =~ s|^//\s*||;
            $return =~ s/\n*$//;
            $return =~ s/"/\\"/g;
            $return = "\nA quick comment: \"$return\".\n";
          }

constant:
      /-?[0-9]*\.[0-9]*[lf]{0,2}/i
          {
            if ($item[1] =~ s/f$//i) { 
              $return = "the floating point constant $item[1]";
            } elsif ($item[1] =~ s/l$//i) {
              $return = "long double $item[1]";
            } else {
              $return = $item[1];
            }
            $return .= '0' if $return =~ /\.$/;
          } 
    | /0x[0-9a-f]+[lu]{0,3}/i
          { 
            $return .= 'unsigned ' if $item[1] =~ s/[Uu]//; 
            $return .= 'long ' while $item[1] =~ s/[Ll]//; 
            $return = "the $return" . "hexadecimal constant $item[1]";
          } 
    | /0\d+[lu]{0,3}/i
          {
            $return .= 'unsigned ' if $item[1] =~ s/[Uu]//; 
            $return .= 'long ' while $item[1] =~ s/[Ll]//; 
            $return = "the $return" . "octal constant $item[1]";
          }
    | /-?[0-9]+[lu]{0,3}/i # integer constant
          {
            $return .= "unsigned " if $item[-1] =~ s/[Uu]//; 
            $return .= "long " while $item[-1] =~ s/[Ll]//; 
            $return .= $item[-1];
          } 
    | /[LuU]?(?:\'(?:\\\'|(?!\').)*\')/ # character constant
          {
            my $constant = $item[1];
            my $modifier = "";

            $modifier = 'wide character ' if $constant =~ s/^L//;
            $modifier = '16-bit character ' if $constant =~ s/^u//;
            $modifier = '32-bit character ' if $constant =~ s/^U//;

            if ($constant eq q('\n')) {
              $return = "a $modifier" . 'newline';
            } elsif ($constant eq q('\f')) {
              $return = "a $modifier" . 'form-feed character';
            } elsif ($constant eq q('\t')) {
              $return = "a $modifier" . 'tab';
            } elsif ($constant eq q('\v')) {
              $return = "a $modifier" . 'vertical tab';
            } elsif ($constant eq q('\b')) {
              $return = 'an alert character' if not length $modifier;
              $return = "a $modifier" . 'alert character' if length $modifier;
            } elsif ($constant eq q('\r')) {
              $return = "a $modifier" . 'carriage-return';
            } elsif ($constant eq q('\b')) {
              $return = "a $modifier" . 'backspace character';
            } elsif ($constant eq q('\'')) {
              $return = "a $modifier" . 'single-quote';
            } elsif ($constant eq q(' ')) {
              $return = "a $modifier" . 'space';
            } else {
              $return = $constant if not length $modifier;
              $return = "a $modifier$constant" if length $modifier;
            }
          }
 
identifier_word:
      /[a-z_\$][a-z0-9_]*/i
          { $return = "`$item[-1]`"; }

string:
      (/(u8|u|U|L)?(?:\"(?:\\\"|(?!\").)*\")/)(s)
          {
            my $final_string = "";
            foreach my $string (@{$item[-1]}) {
              my $modifier = "";
              $modifier = 'an UTF-8 string ' if $string =~ s/^u8//;
              $modifier = 'a wide character string ' if $string =~ s/^L//;
              $modifier = 'a 16-bit character string ' if $string =~ s/^u//;
              $modifier = 'a 32-bit character string ' if $string =~ s/^U//;

              if (not length $final_string) {
                $final_string = $modifier;
                $final_string .= '"';
              }

              $string =~ s/^"//;
              $string =~ s/"$//;
              $final_string .= $string;
            }
            $final_string .= '"';
            $return = $final_string;
          }

reserved: 
    /(auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto
       |if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef
       |union|unsigned|void|volatile|while|_Alignas|alignas|_Alignof|alignof|_Atomic|_Bool|_Complex|_Generic
       |_Imaginary|_Noreturn|noreturn|_Static_assert|static_assert|_Thread_local|offsetof)\b/x

