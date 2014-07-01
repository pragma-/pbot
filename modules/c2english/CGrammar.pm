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
          { $return = "\nInclude system file $item{filename}.\n"; }
    | 'include' '"' filename '"' <skip: '[ \t]*'> "\n"
          { $return = "\nInclude user file $item{filename}.\n"; }
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
            if(@{$item{declarator}} > 2) {
              $return_type = "$item{declarator}->[2] $declaration_specifiers";
            } else {
              $return_type = $declaration_specifiers;
            }

            if($return_type =~ s/( with.*)$//) {
              my $storage_class_specifier = $1;
              $parameter_list =~ s/function/function$storage_class_specifier/;
            }

            $return = "\nLet $name be a ";
            $return .= $parameter_list;
            $return .= " $return_type.\nTo perform the function, ^L";
            $return .= join('', @{$item{'compound_statement(?)'}});
          } 

compound_statement:
      '{' declaration_list(?) statement_list(?) '}' 
          { 
            my $declaration_list = join('',@{$item{'declaration_list(?)'}}); 
            my $statement_list = join('',@{$item{'statement_list(?)'}}); 

            $return = "Begin new block.\n" if not $arg{context};

            if ($declaration_list) { 
              $return .= $declaration_list; 
            }

            if ($statement_list ) { 
              $return .= $statement_list;   
            } else {
              $return .= "Do nothing.\n";
            } 

            $return .= "End block.\n" if not $arg{context};

            if ($arg{context} 
                and $arg{context} ne 'do loop'
                and $arg{context} ne 'case'
                and $arg{context} ne 'function definition statement' 
                and $arg{context} ne 'function definition') { 
              $return .= "End $arg{context}.\n";
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

            if ($expression) { 
              my $expression  = ::istrue $expression;
              $return .= "For as long as ^L$expression, ^L"; 
            } else {
              $return .= "Repeatedly ^L";
            } 

            $return .= $item{statement} ; 

            if ($increment) { 
              $return =~ s/End for loop.$//;
              $return .= "After each iteration, ^L$increment.\n"; 
            } 
          } 
    | 'while' '(' <commit> expression[context => 'while conditional']  ')' statement[context => 'while loop']  
          { 
            if($item{expression} =~ /(^\d+$)/) {
              if($1 == 0) {
                $return = "Never ^L";
              } else {
                $return = "Repeatedly ^L";
              }
            } else {
              my $expression = ::istrue $item{expression};
              $return = "While ^L$expression, ^L"; 
            }

            if($item{statement}) {
              $return .= $item{statement} . "\n"; 
            } else {
              $return .= "do nothing.\n";
            }
          } 
    | 'do' statement[context => 'do loop'] 'while' '(' expression[context => 'do while conditional'] ')' ';' 
          {
            $item{statement} =~ s/^do nothing/nothing/i;
            $return = "Do the following:^L $item{statement}";
            if($item{expression} =~ /(^\d+$)/) {
              if($1 == 0) {
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
      'if' <commit> '(' expression[context => 'if conditional'] ')' statement[context => 'if statement'] 
          { 
            if($item{expression} =~ /^(\d+)$/) {
              if($1 == 0) {
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
      ('else' statement[context => 'else block']
          { $return = "Otherwise, ^L$item{statement}"; }
      )(?)
          { $return .= join('',@{$item[-1]}); }
    | 'switch'  '(' expression[context => 'switch conditional'] ')'  statement[context => 'switch']  
          { 
            $return = "Given the expression \'^L$item{expression}\',\n^L$item{statement}";
          }

jump_statement: 
      'break' ';'   
          { 
            if($arg{context} eq 'switch' or $arg{context} eq 'case') {
              $return = "Break case.\n";
            } elsif(length $arg{context}) {
              $return = "Break from the $arg{context}.\n";
            } else {
              $return = "Break from the current block.\n";
            }
          } 
    | 'continue' ';'
          { $return = "Return to the top of the current loop.\n"; } 
    | 'return' <commit> expression[context => 'return statement'](?) ';' 
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
            if (!$expression) { 
              if($arg{context} eq 'label'
                  or $arg{context} eq 'for init'
                  or $arg{context} eq 'for conditional') {
                $return = "";
              } else {
                $return = "Do nothing.\n"; 
              }
            } else { 
              $return = $expression;
              $return .= ".\n" unless $arg{context} =~ /^for /;
            } 
          }

labeled_statement:
      identifier ':' statement[context => 'label'] (';')(?)
          { $return = "Let there be a label $item{identifier}.\n$item{statement}"; }
    | 'case' constant_expression ':' statement[context => 'case'] 
          { $return = "When it has the value $item{constant_expression}, ^L$item{statement}"; }
    | 'default' ':' statement 
          { $return = "In the default case, ^L$item{statement}"; } 

expression:
      <leftop: assignment_expression ',' assignment_expression>
          {
            if($arg{context} eq 'for increment statement'
                or $arg{context} eq 'for init') {
              $return = join(', then ', @{$item[-1]});
            } elsif( $arg{context} =~ /conditional/) {
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
            if($item{conditional_ternary_expression}) {
              my $op1 = $item{conditional_ternary_expression}->[0];
              my $op2 = $item{conditional_ternary_expression}->[1];
              my $expression = ::istrue $item{logical_OR_AND_expression};

              if($arg{context} =~ /statement$/) {
                $return = "$op1 if $expression otherwise to $op2";
              } elsif($arg{context} =~ /assignment expression$/) {
                $return = "$op1 if $expression otherwise to be $op2";
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
            if ($arg{context} =~ /statement$/) { 
              $return = ['Assign to^L', 'the value^L' ]; 
            } elsif ($arg{context} eq 'for init') {
              $return = ['assigning to^L', 'the value^L' ];
            } else { 
              $return = 'which is assigned to be^L'; 
            }
          }
    | '+=' 
          {
            if ($arg{context} =~ /statement$/) { 
              $return = ['Increment^L','by^L'];
            } elsif ($arg{context} eq 'for init') { 
              $return = ['incrementing^L','by^L'];
            } else { 
              $return = 'which is incremented by^L'; 
            }
          }
    | '-='
          {
            if ($arg{context} =~ /statement$/) { 
              $return = ['Decrement^L', 'by^L']; 
            } elsif ($arg{context} eq 'for init') { 
              $return = ['decrementing^L' , 'by^L']; 
            } else { 
              $return = 'which is decremented by^L'; 
            }
          }
    | '*='
          {
            if ($arg{context} =~ /statement$/) { 
              $return = ['Multiply^L' , 'by^L'];  
            } elsif ($arg{context} eq 'for init') { 
              $return = ['multiplying^L' , 'by^L'];
            } else { 
              $return = 'which is multiplied by^L'; 
            }
          }
    | '/='
          { 
            if ($arg{context} =~ /statement$/) {  
              $return = ['Divide^L' , 'by^L' ]; 
            } elsif ($arg{context} eq 'for init') {  
              $return = ['dividing^L' , 'by^L' ]; 
            } else { 
              $return = 'which is divided by^L'; 
            }
          }
    | '%=' 
          { 
            if ($arg{context} =~ /statement$/) { 
              $return = ['Reduce^L', 'to modulo ^L'] ;  
            } elsif ($arg{context} eq 'for init') { 
              $return = ['reducing^L', 'to modulo ^L'] ;  
            } else { 
              $return = 'which is reduced to modulo^L'; 
            }
          }
    | '<<='
          { 
            if ($arg{context} =~ /statement$/) { 
              $return = ['Bit-shift^L', 'left by^L'];  
            } elsif ($arg{context} eq 'for init') { 
              $return = ['bit-shifting^L', 'left by^L'];  
            } else { 
              $return = 'which is bit-shifted left by^L'; 
            }
          }
    | '>>='
          { 
            if ($arg{context} =~ /statement$/) { 
              $return = ['Bit-shift^L', 'right by^L'];  
            } elsif ($arg{context} eq 'for init') { 
              $return = ['bit-shifting^L', 'right by^L'];  
            } else { 
              $return = 'which is bit-shifted right by^L'; 
            }
          }
    | '&='
          { 
            if ($arg{context} =~ /statement$/) { 
              $return = ['Bit-wise ANDed^L', 'by^L' ];  
            } elsif ($arg{context} eq 'for init') { 
              $return = ['bit-wise ANDing^L', 'by^L' ];  
            } else { 
              $return = 'which is bit-wise ANDed by^L'; 
            }
          }
    | '^='
          { 
            if ($arg{context} =~ /statement$/) { 
              $return = ['Exclusive-OR^L','by^L'];
            } elsif ($arg{context} eq 'for init') { 
              $return = ['exclusive-ORing^L','by^L'];
            } else { 
              $return = 'which is exclusive-ORed by^L'; 
            }
          }
    | '|='
          { 
            if ($arg{context} =~ /statement$/) { 
              $return = ['Bit-wise ORed^L', 'by^L'];  
            } elsif ($arg{context} eq 'for init') { 
              $return = ['bit-wise ORing^L', 'by^L'];  
            } else { 
              $return = 'which is bit-wise ORed by^L'; 
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
            if (defined $arg{context} and $arg{context} eq 'for conditional') { print STDERR "hmm2\n"; }
            $return = join ('', @{$item[1]});
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
            if($arg{context} =~ /conditional/) {
              $return = ['', ' is false'];
            } else {
              $return = 'the logical negation of ^L';
            }
          }

rel_add_mul_shift_expression:
      cast_expression ...';'
          { $return = $item{cast_expression}; }
    | <leftop: cast_expression rel_mul_add_ex_op cast_expression>
          { $return = join ('' , @{$item[1]}); } 

closure: 
      ',' | ';' | ')' 

cast_expression:
      '(' type_name ')' cast_expression[context => 'recast']
          { $return = "$item{cast_expression} type-casted as $item{type_name}"; }
    | unary_expression 
          { $return = $item{unary_expression}; } 

declaration_list: 
      preproc[context => 'statement'](?) declaration(s) 
          { $return = join('', @{$item{'preproc(?)'}}) . join('', @{$item{'declaration(s)'}}); }

declaration:
      declaration_specifiers init_declarator_list(?) ';'
          {
            my @init_list = defined $item{'init_declarator_list(?)'}->[0] ? @{$item{'init_declarator_list(?)'}->[0]} : ('');
            my $typedef = $item{declaration_specifiers} =~ s/^type definition of //;

            my $inits = 0;
            while(@init_list) {
              $inits++;
              if(not $arg{context} eq 'struct member') {
                if($arg{context} eq 'for init') {
                  $return .= "letting ";
                } else {
                  $return .= "Let ";
                }
              }

              my @args = ::flatten shift @init_list;

              my ($first_qualifier, $first_initializer);
              my $first_identifier = shift @args;

              if(not length $first_identifier) {
                $first_identifier = 'there';
              }

              my @identifiers = ($first_identifier);

              my $next_arg = shift @args;
              if($next_arg =~ m/initialized/) {
                $first_initializer = $next_arg;
                $first_qualifier = shift @args // '';
              } else {
                $first_qualifier = $next_arg;
                $first_initializer = shift @args // '';
              }

              if($first_initializer !~ /^initialized/) {
                $first_qualifier .= " $first_initializer" if $first_initializer;
                $first_initializer = '';
              }

              my $remaining_args = join(' ', @args);

              my @initializers;
              if($first_initializer) {
                push @initializers, [ $first_identifier, $first_initializer ];
              }

              for(my $i = 0; $i < @init_list; $i++) {
                @args = ::flatten $init_list[$i];

                my ($qualifier, $initializer);
                my $identifier = shift @args;

                $next_arg = shift @args;
                if($next_arg =~ m/initialized/) {
                  $initializer = $next_arg;
                  $qualifier = shift @args // '';
                } else {
                  $qualifier = $next_arg;
                  $initializer = shift @args // '';
                }

                next unless $qualifier eq $first_qualifier;

                push @identifiers, $identifier;
                if($initializer) {
                  push @initializers, [ $identifier, $initializer ];
                }

                splice @init_list, $i--, 1;
              }

              if($arg{context} eq 'struct member') {
                if($inits > 1 and not @init_list) {
                  $return .= ' and ';
                } elsif($inits > 1) {
                  $return .= ', ';
                }

                if($first_qualifier) {
                  if($first_qualifier =~ /bit\-field/) {
                    $first_qualifier = "$item{declaration_specifiers} $first_qualifier";
                    $item{declaration_specifiers} = '';
                  }

                  if(@identifiers == 1 and $first_qualifier !~ /^(a|an)\s+/) {
                    $return .= $first_qualifier =~ m/^[aeiouy]/ ? 'an ' : 'a ';
                  } elsif(@identifiers > 1 and not $typedef) {
                    $first_qualifier =~ s/pointer/pointers/;
                    $first_qualifier =~ s/an array/arrays/;
                  }
                  $return .= "$first_qualifier $item{declaration_specifiers} ";
                } else {
                  if(@identifiers == 1 and $item{declaration_specifiers} !~ /^(a|an)\s+/) {
                    $return .= $item{declaration_specifiers} =~ m/^[aeiouy]/ ? 'an ' : 'a ';
                  }
                  $return .= "$item{declaration_specifiers} ";
                }

                my $and = @identifiers > 1 ? ' and ' : '';
                my $comma = '';
                for(my $i = 0; $i < @identifiers; $i++) {
                  if($i == @identifiers - 1) {
                    $return .= "$and$identifiers[$i]";
                  } else {
                    $return .= "$comma$identifiers[$i]";
                    $comma = ', ';
                  }
                }
              } else {
                my $and = @identifiers > 1 ? ' and ' : '';
                my $comma = '';
                for(my $i = 0; $i < @identifiers; $i++) {
                  if($i == @identifiers - 1) {
                    $return .= "$and$identifiers[$i]";
                  } else {
                    $return .= "$comma$identifiers[$i]";
                    $comma = ', ';
                  }
                }

                if($typedef) {
                  $return .= ' each' if @identifiers > 1;
                  $return .= ' be another name for ';
                  push @typedefs, @identifiers;
                } else {
                  $return .= ' be ';
                }

                if($first_qualifier) {
                  if(@identifiers == 1 and $first_qualifier !~ /^(a|an)\s+/) {
                    $return .= $first_qualifier =~ m/^[aeiouy]/ ? 'an ' : 'a ';
                  } elsif(@identifiers > 1 and not $typedef) {
                    $first_qualifier =~ s/pointer/pointers/;
                    $first_qualifier =~ s/an array/arrays/;
                  }
                  $return .= "$first_qualifier ";
                  $return .= "$remaining_args " if $remaining_args;
                  $return .= $item{declaration_specifiers};
                } else {
                  if(@identifiers == 1 and $item{declaration_specifiers} !~ /^(a|an)\s+/) {
                    $return .= $item{declaration_specifiers} =~ m/^[aeiouy]/ ? 'an ' : 'a ';
                  }
                  $return .= "$remaining_args " if $remaining_args;
                  $return .= $item{declaration_specifiers};
                }

                if(@initializers) {
                  if(@identifiers > 1) {
                    $return .= ".\nInitialize ";

                    @initializers = sort { $a->[1] cmp $b->[1] } @initializers;
                    my ($and, $comma);

                    for(my $i = 0; $i < @initializers; $i++) {
                      my ($identifier, $initializer) = @{$initializers[$i]};

                      if($i < @initializers - 1 and $initializer eq $initializers[$i + 1]->[1]) {
                        $return .= "$comma$identifier";
                        $comma = ', ';
                        $and = ' and ';
                      } else {
                        $initializer =~ s/^initialized to \^L//;
                        $return .= "$and$identifier to $initializer";
                        if($i < @initializers - 2) {
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
                $return .= ".\n" unless $arg{context} eq 'for init';
              }
            }
          }

init_declarator_list:
      <leftop: init_declarator ',' init_declarator> 

init_declarator:
      declarator[context => 'init_declarator']
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
      comment(?) assignment_expression comment(?)
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
          { $return = 'the set { ' . $item{'initializer_list'} . ' }'; }

initializer_list:
      <leftop: initializer ',' initializer > 
          {
            my @inits = @{$item[1]};

           if ($#inits >1) { 
              my $init = pop @inits; 
              $return = join(', ',@inits) . ', and ' .$init; 
            } elsif ($#inits == 1) { 
              $return = $inits[0] . ' and ' . $inits[1]; 
            } else { 
              $return = $inits[0]; 
            } 
          }

unary_expression:
      postfix_expression
          { $return = $item{postfix_expression}; }
    | '++' unary_expression
          {
            if ($arg{context} =~ /statement$/ ) {
              $return = "pre-increment $item{unary_expression}"; 
            } else { 
              if($item{unary_expression} =~ s/^the member//) {
                $return = "the pre-incremented member $item{unary_expression}";
              } else {
                $return = "pre-incremented $item{unary_expression}";
              }
            }
          }
    | '--' unary_expression  
          {
            if ($arg{context} =~ /statement$/ ) {
              $return = "Pre-decrement $item{unary_expression}"; 
            } else { 
              if($item{unary_expression} =~ s/^the member//) {
                $return = "the pre-decremented member $item{unary_expression}";
              } else {
                $return = "pre-decremented $item{unary_expression}";
              }
            }
          }
    | unary_operator cast_expression
          { 
            if(ref $item{unary_operator} eq 'ARRAY') {
              $return = $item{unary_operator}->[0] . $item{cast_expression} . $item{unary_operator}->[1];
            } else {
              $return = $item{unary_operator} . $item{cast_expression};
            }
          }
    | 'sizeof' '(' type_name[context => 'sizeof'] ')' 
          { $return = "the size of the type $item{type_name}"; }
    | 'sizeof' '(' assignment_expression[context => 'sizeof'] ')' 
          { $return = "the size of the type of the expression ($item{assignment_expression})"; }
    | 'sizeof' unary_expression[context => 'sizeof'] 
          { $return = "the size of $item{unary_expression}"; }

postfix_productions:
      '(' argument_expression_list(?) ')' postfix_productions[context => 'function call'](?)
          {
            my $postfix = $item[-1]->[0];

            $arg{primary_expression} =~ s/^Evaluate the expression/resulting from the expression/;

            if(not defined $arg{context} or $arg{context} ne 'statement') {
              $return = "the result of the function $arg{primary_expression}";
            } else {
              $return = "Call the function $arg{primary_expression} ";
            }

            # To discriminate between macros and functions. 
            foreach (@macros) { 
              if ($arg{primary_expression} eq $_) { 
                $return =~ s/Call/Insert/;
                $return =~ s/function/macro/; 
              }
            }

            my $arg_exp_list = join('',@{$item{'argument_expression_list(?)'}}); 
            if ($arg_exp_list) { 
              $return .= " with argument$arg_exp_list";
            }

            if($postfix) { 
              $return =~ s/^(Call|Insert)/the result of/;
              $return = "$postfix $return"; 
            }
            1;
          }
    | ('[' expression[context => 'array_address'] ']' 
          { $return = $item{expression}; } 
      )(s) postfix_productions[context => "$arg{context}|array_address"](?)
          {
            my $expression = '';
            if (@{$item[-2]}) { 
              $expression = join(' and ', @{$item[-2]}); 
            }

            my $postfix = $item[-1]->[0];

            if (length $expression) { 
              if($expression =~ /^\d+$/) {
                $expression++;
                my ($last_digit) = $expression =~ /(\d)$/;
                if($last_digit == 1) {
                  if($expression =~ /11$/) {
                    $expression .= 'th';
                  } else {
                    $expression .= 'st'; 
                  }
                } elsif($last_digit == 2) {
                  $expression .= 'nd';
                } elsif($last_digit == 3) {
                  $expression .= 'rd';
                } else {
                  $expression .= 'th';
                }
                if($arg{context} eq 'function call') {
                  $return = "the $expression element of^L";
                } else {
                  $return = "the $expression element of^L";
                  $return .= " $arg{primary_expression}" if $arg{primary_expression};
                }
              } elsif($expression =~ /^-\s*\d+$/) {
                $expression *= -1;
                my $plural = $expression == 1 ? '' : 's';
                $return = "the location $expression element$plural backwards from where ^L$arg{primary_expression} points^L";
              } else {
                $return = "the element of ^L$arg{primary_expression} at location ^L$expression^L";
              }
            }

            if($postfix) {
              $return = "$postfix $return";
            }
          }
    | '.' identifier postfix_productions[context => "$arg{context}|struct access"](?)
          { 
            my $identifier = $item[-2]; 
            my $postfix = $item[-1]->[0];

            if($postfix) {
              if(ref $postfix eq 'ARRAY') {
                $return = "$postfix->[0] the member $identifier $postfix->[1] of";
              } else {
                if($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "$postfix member $identifier of";
                  $return .= " the" unless $arg{context} =~ /array_address/;
                } else {
                  $postfix =~ s/ the(\^L)?$/$1/;
                  $return = "$postfix the member $identifier of";
                  $return .= " the" unless $arg{context} =~ /array_address/;
                }
                if($arg{primary_expression}) { 
                  $return =~ s/ the(\^L)?$/$1/;
                  $return .= " ^L$arg{primary_expression}"
                }
              }
            } else {
              if($arg{context} =~ /array_address/) {
                $return = "the member $identifier of^L";
              } else {
                $return = "the member $identifier of the^L";
                if($arg{primary_expression}) {
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

            if($postfix) {
              if(ref $postfix eq 'ARRAY') {
                $return = "$postfix->[0] the member $identifier $postfix->[1] of the structure pointed to by^L";
              } else {
                if($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "$postfix member $identifier of the structure pointed to by the^L";
                } else {
                  $postfix =~ s/ the(\^L)?$/$1/;
                  $return = "$postfix the member $identifier of the structure pointed to by the^L";
                }
              }
            } else {
              $return = "the member $identifier of the structure pointed to by the^L";
            }
            if($arg{primary_expression}) {
              $return =~ s/ the(\^L)?$/$1/;
              $return .= " $arg{primary_expression}";
            }
            1;
          }
    | ('++')(s)
          {
            my $increment = join('',@{$item[-1]}); 
            if ($increment) {
              if($arg{context} =~ /struct access/) {
                if($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "the post-incremented";
                } else {
                  $return = "post-increment";
                }
              } elsif($arg{context} =~ /statement/) {
                $return = ['increment', 'by one'];
              } else {
                $return = "post-incremented $arg{primary_expression}";
              }
            }
          }
    | ('--')(s)
          {
            my $increment = join('',@{$item[-1]}); 
            if ($increment) {
              if($arg{context} =~ /struct access/) {
                if($arg{context} =~ /conditional/ or $arg{context} =~ /assignment expression/) {
                  $return = "the post-decremented";
                } else {
                  $return = "post-decrement";
                }
              } elsif($arg{context} =~ /statement/) {
                  $return = ['decrement', 'by one'];
              } else {
               $return = "post-decremented $arg{primary_expression}";
             }
            }
          }
    # having done the simplest cases, we go to the catch all for left recursions.
    | primary_expression postfix_suffix(s)
          {
            print STDERR "Untested code!\n"; 
            $return = $item{primary_expression} . "'s " . join('',@{$item{'postfix_suffix(s)'}}); 
          }
    | {""}

postfix_expression:
      primary_expression postfix_productions[primary_expression => $item[1], context => $arg{context}]
          {
            my $postfix_productions = $item{'postfix_productions'};

            if(ref $postfix_productions eq 'ARRAY') {
              $return = "$postfix_productions->[0] $item{primary_expression} $postfix_productions->[1]";
            } elsif(length $postfix_productions) {
              $return = $postfix_productions;
            } elsif(length $item{primary_expression}) {
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
              $return = 's ' . join(', ', @arg_exp_list) . ", and $last";
            } elsif (@arg_exp_list == 2 ) { 
              $return = "s $arg_exp_list[0] and $arg_exp_list[1]";  
            } else {
              if ($arg_exp_list[0]) {
                $return = " $arg_exp_list[0]";
              } else {
                $return = '';
              }
            }
          }

narrow_closure:
      ';' | ',' | '->'

primary_expression:
      '(' expression ')' (...narrow_closure)(?)
          { 
            my $expression = $item{expression} ; 
            my $repeats = 1; 

            if ($expression =~ /^The expression (\(+)/) { 
              $repeats = (length $1) + 1; 
              $expression =~ s/^The expression \(+//;
            }

            $expression .= ')';
            if($arg{context} =~ /statement$/) {
              $return = "Evaluate the expression ";
            } else {
              $return = "The result of the expression ";
            }
            $return .= '(' x $repeats;
            $return .= "^L$expression";
          }
    | constant
    | string 
    | identifier
    | {} # nothing

declarator:
      direct_declarator(s)
          { 
            my @direct_declarator = @{$item{'direct_declarator(s)'}};
            if(@direct_declarator == 1) {
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
            if(@{$item{'array_declarator(s?)'}}) {
              $return = [$item{identifier}, join('', @{$item{'array_declarator(s?)'}})];
            } else {
              $return = $item{identifier};
            }
          }
    | '(' declarator ')' array_declarator(s)
          { 
            push @{$item{declarator}}, join('', @{$item{'array_declarator(s)'}});
            $return = $item{declarator};
          }
    | '(' parameter_type_list ')'
          { $return = "function taking $item{parameter_type_list} and returning"; }
    | '(' declarator array_declarator(s) ')'
          { $return = $item{'declarator'} . join('', @{$item{'array_declarator(s)'}}) }
    | '(' declarator ')' 
          { $return = $item{declarator}; }

array_declarator:
      ( '[' assignment_expression(?) ']'
          {
            if (@{$item{'assignment_expression(?)'}}) { 
              my $size = join('', @{$item{'assignment_expression(?)'}});
              if($size =~ /^(unsigned|long)*\s*1$/) {
                $return = "$size element ";
              } else {
                $return = "$size elements ";
              }
            } else { 
              $return = 'unspecified length ';
            }
          }
      )(s?)
          {
            my @array = @{$item[-1]};  
            if (@array) { 
              $return .= 'an array of ' . join('of an array of ' , @array) . 'of';
            } else {
              undef;
            }
          }

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
            for(my $i = 0; $i < @parameter_list; $i++) {
              $return .= $comma;
              if(ref $parameter_list[$i] eq 'ARRAY') {
                my @list = ::flatten @{$parameter_list[$i]};
                if(@list == 0) {
                  $return = "no parameters";
                } elsif (@list ==  1) {
                  if($list[0] eq 'void') {
                    $return = "no parameters";
                  } else {
                    $return .= $list[0];
                  }
                } else {
                  push @list, shift @list;
                  if($list[0] =~ /^`.*`$/) {
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

              if($i == $#parameter_list - 1) {
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
          { $return = "variadic parameters"; }
    | declaration_specifiers abstract_declarator(?) 
          { $return = [$item{declaration_specifiers}, $item{'abstract_declarator(?)'}]; }
    | ''
          { $return = "unspecified parameters"; }

abstract_declarator: 
      pointer 
    | pointer(?) direct_abstract_declarator(s) 
          { $return = join(' ',@{$item{'pointer(?)'}}) . join(' ', @{$item{'direct_abstract_declarator(s)'}}); }

direct_abstract_declarator:
      '(' abstract_declarator ')'
          { $return = $item{abstract_declarator}; }
    | '[' ']'
          { $return = "array of unspecified length of"; }
    | '[' constant_expression ']' 
          { 
            my $size = $item{constant_expression};
            if($size =~ /^(unsigned|long)*\s*1$/) {
              $return = "array of $size element of";
            } else {
              $return = "array of $size elements of";
            }
          }
    | DAD '[' ']'
    | DAD '[' constant_expression ']'
    | '(' ')'
          { $return = 'function taking unspecified parameters and returning'; }
    | '(' parameter_type_list ')'
          { $return = "function taking $item{parameter_type_list} and returning"; }
    | DAD '(' ')'
    | DAD '(' parameter_type_list ')'

DAD: # macro for direct_abstract_declarator 
      ( '(' abstract_declarator ')' )(s?)
      ( '[' ']' )(s?)
      ( '[' constant_expression ']' )(s?)
      ( '(' ')' )(s?)
      ( '(' parameter_type_list ')' )(s?)

identifier: 
      ...!reserved identifier_word
          {
            if(not grep { $_ eq $item{identifier_word} } @identifiers) {
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


declaration_specifiers:
      comment(?) type_specifier ...identifier
          { $return = join('', @{$item{'comment(?)'}}) . $item{type_specifier}; }
    | comment(?) storage_class_specifier declaration_specifiers(?) 
          {
            my $decl_spec =  join(' ', @{$item{'declaration_specifiers(?)'}});
            $return = join('',@{$item{'comment(?)'}});

            if($item{storage_class_specifier} =~ m/^with/) {
              if ($decl_spec) { $return .=  "$decl_spec "; } 
              $return .= $item{storage_class_specifier};
            } else {
              $return .= $item{storage_class_specifier};
              if ($decl_spec) { $return .=  " $decl_spec"; }
            }
          }
    | comment(?) type_specifier(s) declaration_specifiers(?) 
          {
            my $decl_spec = join(' ', @{$item{'declaration_specifiers(?)'}});
            $return = join('',@{$item{'comment(?)'}});
            $return .= "$decl_spec " if $decl_spec;
            $return .= join(' ', @{$item{'type_specifier(s)'}});
          }
    | comment(?) type_qualifier declaration_specifiers(?) 
          {
            my $decl_spec = join(' ',@{$item{'declaration_specifiers(?)'}});
            $return = join('',@{$item{'comment(?)'}}) . $item{type_qualifier};
            $return .=  " $decl_spec" if $decl_spec;
          }

storage_class_specifier:
      'auto'
          { $return = "with automatic storage-duration"; }
    | 'extern'
          {
            if($arg{context} eq 'function definition') {
              $return = "with external linkage";
            } else {
              $return = "with external linkage, possibly defined elsewhere";
            }
          }
    | 'static' 
          { 
            if($arg{context} eq 'function definition') {
              $return = "with internal linkage";
            } elsif($arg{context} eq 'function definition statement') {
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

type_specifier:
      'void' | 'double' | 'float' | 'char' | 'short' | 'int' | 'long'
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
    | struct_or_union_specifier
    | enum_specifier
    | typedef_name 

typedef_name:
      identifier
          {
            my $answer = 0; 
            foreach (@typedefs) { 
              if ($item{identifier} eq $_) {
                $answer = 1;      
                $return = ($item{identifier} =~ m/^`[aeiouy]/ ? 'an ' : 'a ') . $item{identifier};
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
            my $plural = $item{struct_declaration_list} =~ / and / ? 's' : '';
            $return .= " with member$plural $item{struct_declaration_list}"; 
          }
    | struct_or_union identifier
          {
            $item{struct_or_union} =~ s/^(a|an)//;
            $return = $item{identifier} =~ m/^`[aeiouy]/ ? 'an' : 'a';
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

            if(@enumerator_list == 1) {
              $return .= " comprising $enumerator_list[0]";
            } else {
              my $last = pop @enumerator_list; 
              $return .= ' comprising ' . join(', ', @enumerator_list) . " and $last"; 
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
               $return .= ' marking ' . join('', @{$item[-1]}); 
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
            $return = "\nA comment: \"$return\".\n"; 
          }

comment_cxx:
      m{//(.*?)\n}
          { 
            $return = $item[1]; 
            $return =~ s|^//\s*||;
            $return =~ s/\n*$//;
            $return =~ s/"/\\"/g;
            $return = "\nQuick comment: \"$return\".\n";
          }

constant:
      /-?[0-9]*\.[0-9]*[lf]{0,2}/i
          {
            if ($item[1] =~ s/f$//i) { 
              $return = "the floating point number $item[1]";
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
            $return = "the $return" . "hexadecimal number $item[1]";
          } 
    | /0\d+[lu]{0,3}/i
          {
            $return .= 'unsigned ' if $item[1] =~ s/[Uu]//; 
            $return .= 'long ' while $item[1] =~ s/[Ll]//; 
            $return = "the $return" . "octal number $item[1]";
          }
    | /-?[0-9]+[lu]{0,3}/i # integer constant
          {
            $return .= "unsigned " if $item[-1] =~ s/[Uu]//; 
            $return .= "long " while $item[-1] =~ s/[Ll]//; 
            $return .= $item[-1];
          } 
    | /(?:\'((?:\\\'|(?!\').)*)\')/ # character constant
          {
            my $constant = $item[1];

            if($constant eq q('\n')) {
              $return = 'a newline';
            } elsif($constant eq q('\f')) {
              $return = 'a form-feed character';
            } elsif($constant eq q('\t')) {
              $return = 'a tab';
            } elsif($constant eq q('\v')) {
              $return = 'a vertical tab';
            } elsif($constant eq q('\b')) {
              $return = 'an alert character';
            } elsif($constant eq q('\r')) {
              $return = 'a carriage-return';
            } elsif($constant eq q('\b')) {
              $return = 'a backspace character';
            } elsif($constant eq q('\'')) {
              $return = 'a single-quote';
            } else {
              $return = $constant;
            }
          }
 
integer_constant:
      /[0-9]+/ 

identifier_word:
      /[a-z_\$][a-z0-9_]*/i
          { $return = "`$item[-1]`"; }

string:
      /(?:\"(?:\\\"|(?!\").)*\")/

reserved: 
    /(auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto
       |if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef
       |union|unsigned|void|volatile|while|_Alignas|_Alignof|_Atomic|_Bool|_Complex|_Generic
       |_Imaginary|_Noreturn|_Static_assert|_Thread_local)\b/x

