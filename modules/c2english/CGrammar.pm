# C-to-English Grammar
#
# Warning: work-in-progress. Many things are incomplete or non-functional.
#
# todo: 
# 1. the entire syntax for pointers to functions.
# 2. preprocessor directives. (getting there)
# 4. functions to handle the nesting levels (ordinal number generator and CPP stack)
# 6. change returns to prints where appropriate.
# 7. syntax for int *p[10] vs int (*p)[10] vs int *(*p)[10]

{
  my @defined_types = ('`FILE`'); 
  my ($basic, @basics, $rule_name, @macros); 
}

startrule: 
      translation_unit 
          { 
            my $output = $item[-1];
            $output =~ s/\^L(\s*.)/\L$1/g; # lowercase specified characters
            $output =~ s/\^U(\s*.)/\U$1/g; # uppercase specified characters
            print $output;
          } 
      startrule(?)
    
translation_unit:
      comment 
    | external_declaration 
    | function_definition
    | function_prototype 
    | preproc[matchrule => 'translation_unit']

preproc: 
      definition 
    | undefinition  
    | inclusion  
    | line 
    | error
    | pragma 
    | preproc_conditional[matchrule => $arg{matchrule}]

definition: 
      macro_definition
    | '#' 'define' identifier token_sequence(?) <skip: '[ \t]*'> "\n"
          {
            my $token_sequence = join('',@{$item{'token_sequence(?)'}});
            $return = "Define the macro $item{identifier}";
            $return .= " to mean $token_sequence" if $token_sequence;
            $return .= ".\n";
          }

macro_definition:
      '#' 'define' identifier '(' <leftop: identifier ',' identifier> ')' token_sequence <skip: '[ \t]*'> "\n"
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
      '#' 'undef' identifier <skip: '[ \t]*'> "\n"
          { 
            @macros = grep { $_ ne $item{identifier} } @macros;
            $return = "\nAnnul the definition of $item{identifier}.\n";
          }

inclusion: 
      '#' 'include' '<' filename '>' <skip: '[ \t]*'> "\n"
          { $return = "\nInclude system file $item{filename}.\n"; }
    | '#' 'include' '"' filename '"' <skip: '[ \t]*'> "\n"
          { $return = "\nInclude user file $item{filename}.\n"; }
    | '#' 'include' token
          { $return = "\nImport code noted by the token $item{token}.\n"; }   

filename: 
      /[_\.\-\w\/]+/ 

line: 
      '#' 'line' constant ('"' filename '"'
          { $return = "and filename $item{filename}"; }
      )(?) <skip: '[ \t]*'> "\n"
          { $return = "\nThis is line number $item{constant} " . join('', @{$item[-3]}) . ".\n"; }

error:
      '#' 'error' token_sequence(?) <skip: '[ \t]*'> "\n"
          { $return = "Stop compilation with error \"" . join('', @{$item{'token_sequence(?)'}}) . "\".\n"; }

pragma: 
      '#' 'pragma' token_sequence(?) <skip: '[ \t]*'> "\n"
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
      '#' 'ifdef' identifier <skip: '[ \t]*'> "\n"
          { $return .= "If the macro $item{identifier} is defined, then ^L"; }
    | '#' 'ifndef' identifier <skip: '[ \t]*'> "\n"
          { $return .= "If the macro $item{identifier} is not defined, then ^L"; }
    | '#' 'if' constant_expression <skip: '[ \t]*'> "\n"
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
      declaration 

function_definition:
      <skip: '\s*'> declaration_specifiers(?) declarator[context => 'function_definition']
        '(' parameter_type_list(?) ')' '{' declaration_list(?) statement_list(?) '}' 
          {
            my $declaration_specifiers = join('', @{$item{'declaration_specifiers(?)'}}); 
            my $parameter_list = join('', @{$item{'parameter_type_list(?)'}}); 
            my $declaration_list = join('',@{$item{'declaration_list(?)'}}); 
            my $statement_list = join('',@{$item{'statement_list(?)'}}); 

            my $return_type = $item{declarator}; 
            my $name = $item{declarator}; 

            $name =~ s/^.*?`/`/; 
            $return_type =~ s/`.*`//;

            if ($return_type =~ /\w/ ) { 
              $return_type .= "to a ";
              $return_type .= $declaration_specifiers;
            } else { 
              $return_type = $declaration_specifiers;
            }

            $return = "\nLet $name be a function";

            if ($parameter_list) { 
              $return .= " taking $parameter_list"; 
            }

            $return .= " and returning $return_type.\nTo perform the function, ^L";

            if ($declaration_list) { 
              $return .= $declaration_list; 
            }

            if ($statement_list ) { 
              $return .= $statement_list; 
            } else {
              $return .= "Do nothing.\n";
            }

            # $return .= "End of function $name.\n";
            # $return .= $item{compound_statement}; 
            1;
          } 

function_prototype:
      declaration_specifiers(?) declarator[context => 'function_prototype']
        '(' parameter_type_list(?) ')' ';'
          {
            my $declaration_specifiers = join('', @{$item{'declaration_specifiers(?)'}}); 
            my $parameter_list = join('', @{$item{'parameter_type_list(?)'}}); 

            my $return_type = $item{declarator}; 
            my $name = $item{declarator}; 

            $name =~ s/\|.*$//; 
            $return_type =~ s/`.*`\|?//;

            if($return_type) {
              $return_type .= ' ';
            }

            $return_type .= $declaration_specifiers;

            $return = "Let $name be a function prototype"; 

            if ($parameter_list) { 
              $return .= " taking $parameter_list";
            }

            $return .= " and returning $return_type.\n"; 
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
              $return .= "Do nothing and ^L";
            } 

            $return .= "End block.\n" if not $arg{context};

            if ($arg{context}) { 
              $return .= "End $arg{context}.\n" unless $arg{context} eq 'do loop'; 
            } 
            1;
          }

statement_list:
      comment(?) preproc[matchrule => 'statement'](?) statement
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
          { $return = $item{jump_statement}; }
    | compound_statement[context => $arg{context}, name => $arg{context} ]
    | iteration_statement
    | selection_statement
    | labeled_statement
    | expression_statement

iteration_statement:
      'for' '(' <commit> for_initialization(?) ';' for_expression(?) ';' for_increment(?) ')'    
        statement[context => 'for loop']
          { 
            my $initialization = join('', @{$item{'for_initialization(?)'}}); 
            my $item_expression = join('',@{$item{'for_expression(?)'}}); 
            my $increment = join('',@{$item{'for_increment(?)'}}); 

            if ($initialization) { 
              $return .= "Prepare a loop by ^L$initialization, then ^L"; 
            }

            if ($item_expression) { 
              $return .= "For as long as $item_expression, ^L"; 
            } else {
              $return .= "Repeatedly ^L";
            } 

            $return .= $item{statement} ; 

            if ($increment) { 
              $return .= "After each iteration, ^L$increment.\n"; 
            } 
          } 
    | 'while' '(' <commit> expression  ')' statement[context => 'while loop']  
          { 
            if($item{expression} =~ /(^\d+$)/) {
              if($1 == 0) {
                $return = "Never ^L";
              } else {
                $return = "Repeatedly ^L";
              }
            } else {
              $return = "While $item{expression}, ^L"; 
            }

            if($item{statement}) {
              $return .= $item{statement} . "\n"; 
            } else {
              $return .= "do nothing.\n";
            }
          } 
    | 'do' statement[context => 'do loop'] 'while' '(' expression ')' ';' 
          { $return = "Do the following:^L $item{statement}\nDo this as long as $item{expression}.\n"; }

for_initialization:
      expression[context => 'for loop']

for_expression:
      expression[context => 'for_expression']

for_increment:
      expression[context => 'statement'] 

selection_statement:
      'if' <commit> '(' expression[context => 'if block'] ')' statement[context => 'if block'] 
          { $return = "If $item{expression}, then ^L$item{statement}"; }
      ('else' statement[context => 'else block']
          { $return = "Otherwise, ^L$item{statement}"; }
      )(?)
          { $return .= join('',@{$item[-1]}); }
    | 'switch'  '(' expression ')'  statement[context => 'switch']  
          { $return = "This section is controlled by a switch based on the expression \'$item{expression}\':\n$item{statement}"; }
 

jump_statement: 
      <skip:'\s*'> 'break' ';'   
          { $return = "Break from the current block.\n"; } 
    | 'continue' ';'
          { $return = "Return to the top of the current loop and continue it.\n"; } 
    | 'return' <commit> expression[context => 'return'](?) ';' 
          {
            my $item_expression = join('', @{$item{'expression(?)'}});

            if (length $item_expression) { 
              $return = "Return ^L$item_expression.\n";
            } else {
              $return = "Return no value.\n";
            }
          }
    | 'goto' <commit> identifier ';' comment(?)
          { 
            $return = "Go to the label named $item{identifier}.\n";
            if ($item{comment}) { 
              $return .= $item{comment};
            }
          }

expression_statement:
      expression[context => 'statement'](?) ';'
          { 
            my $item_expression = join('',@{$item[1]}); 
            if (!$item_expression) { 
              $return = "Do nothing.\n"; 
            } else { 
              $return = $item_expression.".\n" ; 
            } 
          }

labeled_statement:
      identifier ':' statement
          { $return = "The following statement is preceded by the label $item{identifier}.\n$item{statement}"; }
    | 'case' constant_expression ':' statement[context => 'case'] 
          { $return = "In the case it has the value $item{constant_expression}, do this:\n$item{statement}"; }
    | 'default' ':' statement 
          { $return = "In the default case, do this:\n$item{statement}"; } 

expression:
      <leftop: assignment_expression[context => $arg{context}] ',' assignment_expression[context => $arg{context}]>
          {
            $return = join(", then ^L",@{$item[-1]}); 
          }

assignment_expression:
      unary_expression[context => 'assignment_expression'] 
        assignment_operator[context => $arg{context}] 
        assignment_expression[context =>  'assignment_expression'] 
          {
            my $assignment_expression = $item{assignment_expression}; 
            my $assignment_operator = $item{assignment_operator};

            if ($arg{context} eq 'statement' or $arg{context} eq 'for loop') {
              $return .= "${$item{assignment_operator}}[0] $item{unary_expression}${$item{assignment_operator}}[1] $assignment_expression";
            } else {
              $return = "$item{unary_expression}, $assignment_operator $assignment_expression"; 
            } 
          } 
    | conditional_expression[context => $arg{context}]

conditional_expression:
      logical_OR_AND_expression[context => $arg{context}]
        '?' expression[context => 'conditional_expression1']
        ':' conditional_expression[context => 'conditional_expression2']
          {
            $return = "the value depending on if $item{logical_OR_AND_expression} is true" .
              " then $item{expression} otherwise $item{conditional_expression}";  
          } 
    | logical_OR_AND_expression[context => $arg{context}] 

assignment_operator:
      '=' 
          {
            if ($arg{context} eq 'statement') { 
              $return = ['Assign to', ' the value' ]; 
            } elsif ($arg{context} eq 'for loop') {
              $return = ['assigning to', ' the value' ];
            } else { 
              $return = ', which is assigned to be '; 
            }
          }
    | '+=' 
          {
            if ($arg{context} eq 'statement') { 
              $return = ['Increment',' by'];
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['incrementing',' by'];
            } else { 
              $return = 'which is incremented by '; 
            }
          }
    | '-='
          {
            if ($arg{context} eq 'statement') { 
              $return = ['Decrement' , ' by']; 
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['decrementing' , ' by']; 
            } else { 
              $return = 'which is decremented by '; 
            }
          }
    | '*='
          {
            if ($arg{context} eq 'statement') { 
              $return = ['Multiply' , ' by'];  
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['multiplying' , ' by'];
            } else { 
              $return = 'which is multiplied by '; 
            }
          }
    | '/='
          { 
            if ($arg{context} eq 'statement') {  
              $return = ['Divide' , ' by' ]; 
            } elsif ($arg{context} eq 'for loop') {  
              $return = ['dividing' , ' by' ]; 
            } else { 
              $return = 'which is divided by '; 
            }
          }
    | '%=' 
          { 
            if ($arg{context} eq 'statement') { 
              $return = ['Reduce', ' to modulo '] ;  
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['reducing', ' to modulo '] ;  
            } else { 
              $return = 'which is reduced to modulo '; 
            }
          }
    | '<<='
          { 
            if ($arg{context} eq 'statement') { 
              $return = ['Bit-shift', ' left by'];  
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['bit-shifting', ' left by'];  
            } else { 
              $return = 'which is bit-shifted left by '; 
            }
          }
    | '>>='
          { 
            if ($arg{context} eq 'statement') { 
              $return = ['Bit-shift', ' right by'];  
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['bit-shifting', ' right by'];  
            } else { 
              $return = 'which is bit-shifted right by '; 
            }
          }
    | '&='
          { 
            if ($arg{context} eq 'statement') { 
              $return = ['Bit-wise ANDed', ' by' ];  
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['bit-wise ANDing', ' by' ];  
            } else { 
              $return = 'which is bit-wise ANDed by '; 
            }
          }
    | '^='
          { 
            if ($arg{context} eq 'statement') { 
              $return = ['Exclusive-OR',' by'];
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['exclusive-ORing',' by'];
            } else { 
              $return = 'which is exclusive-ORed by '; 
            }
          }
    | '|='
          { 
            if ($arg{context} eq 'statement') { 
              $return = ['Bit-wise ORed', ' by'];  
            } elsif ($arg{context} eq 'for loop') { 
              $return = ['bit-wise ORing', ' by'];  
            } else { 
              $return = 'which is bit-wise ORed by '; 
            }
          }

constant_expression:
      conditional_expression

logical_OR_AND_expression:
      <leftop:
        rel_add_mul_shift_expression[context => $arg{context}]
        log_OR_AND_bit_or_and_eq
        rel_add_mul_shift_expression[context => 'logical_OR_AND_expression'] >
          {
            if (defined $arg{context} and $arg{context} eq 'for_expression') { print STDERR "hmm2\n"; }
            my @ands = @{$item[1]}; 
            $return = join ('' , @ands);
          } 

log_OR_AND_bit_or_and_eq: 
      '||' { $return = ' or '; }
    | '&&' { $return = ' and '; }
    | '|'  { $return = ' bitwise ORed by '; }
    | '&'  { $return = ' bitwise ANDed by '; }
    | '^'  { $return = ' bitwise XORed by ';}
    | '==' { $return = ' is equal to ' ; }
    | '!=' { $return = ' is not equal to ' ; } 

rel_mul_add_ex_op: 
      '+'  { $return = ' plus '; }
    | '-'  { $return = ' minus '; }
    | '*'  { $return = ' times '; }
    | '/'  { $return = ' divided by '; }
    | '%'  { $return = ' modulo '; }
    | '<<' { $return = ' shifted left by '; }
    | '>>' { $return = ' shifted right by '; }
    | '>=' { $return = ' is greater than or equal to '; }
    | "<=" { $return = ' is less than or equal to '; }
    | '>'  { $return = ' is greater than '; }
    | '<'  { $return = ' is less than '; }

unary_operator: 
      '&' { $return = 'the address of '; }
    | '*' { $return = 'the contents of '; }
    | '+' { $return = 'the value of '; }
    | '-' ...constant { $return  = 'negative '; }
    | '-' { $return = 'minus '; }
    | '~' { $return = "the one's complement of "; }
    | '!' { $return = 'the logical negation of '; }


rel_add_mul_shift_expression:
      cast_expression[context => $arg{context}] ...';'
          { $return = $item{cast_expression}; }
    | <leftop:
        cast_expression[context => $arg{context}]
        rel_mul_add_ex_op
        cast_expression[context => 'add_mul_shift_expression'] >
          {
            my @ands = @{$item[1]}; 
            $return = join ('' , @ands);
          } 

closure: 
      ',' | ';' | ')' 

cast_expression:
      '(' type_name ')' cast_expression[context => 'recast']
          { $return = "a casting into the type \'$item{type_name}\' of $item{cast_expression}"; }
    | unary_expression[context => $arg{context}] 
          { $return = $item{unary_expression}; } 
      #( ...closure )(?) 
      #   {
      #     if ($arg{context} eq 'statement' #&& !($return =~ /^Perform/)
      # ) 
      #   {
      #     if (${$item[-1]}[0]) {  
      #        $return .= ".\n";
      #     } 
      #  }
      #}

declaration_list: 
      # <skip: '\s*'>
      preproc[context => 'statement'](?) declaration(s) 
          { $return = join('', @{$item{'preproc(?)'}}) . join('', @{$item{'declaration(s)'}}); }

declaration:
      declaration_specifiers init_declarator_list(?) ';'
          {
            # This whole thing needs to be re-written to parse declarations inside-out.
            my @init_list = defined $item{'init_declarator_list(?)'}->[0] ? @{$item{'init_declarator_list(?)'}->[0]} : ('');
            my $init_declaration_list;

            if ($item{declaration_specifiers} =~ s/type definition of //) {
              if(@init_list > 1) {
                my $last = pop @init_list;
                $init_declaration_list = join(', ', @init_list) . ' and ' . $last;
                push $last, @init_list;
              } else {
                $init_declaration_list = $init_list[0];
              }

              $return = "Let $init_declaration_list be another name for $item{declaration_specifiers}.\n";

              push @defined_types, @init_list; 
            } else {
              while(@init_list) {
                $return .= "Let ";

                my $first_object = shift @init_list;
                my @args = split /\|/, $first_object, 3;

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

                my @initializers;
                if($first_initializer) {
                  push @initializers, [ $first_identifier, $first_initializer ];
                }
                
                for(my $i = 0; $i < @init_list; $i++) {
                  @args = split /\|/, $init_list[$i], 3;

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
 
                $return .= ' be ';

                if($first_qualifier) {
                  if(@identifiers == 1) {
                    $return .= $first_qualifier =~ m/^[aeiouy]/ ? 'an ' : 'a ';
                  }
                  $return .= "$first_qualifier $item{declaration_specifiers}";
                } else {
                  if(@identifiers == 1 and $item{declaration_specifiers} !~ /^(a|an)\s+/) {
                    $return .= $item{declaration_specifiers} =~ m/^[aeiouy]/ ? 'an ' : 'a ';
                  }
                  $return .= "$item{declaration_specifiers}";
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
                        $initializer =~ s/^initialized to //;
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
                $return .= ".\n";
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
              $return = "$item{declarator}|initialized to $init"; 
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
          { $return = 'the set ' . join('', @{$item{'initializer_list(?)'}}); }

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
      postfix_expression[context => $arg{context}] 
          { $return = $item{postfix_expression}; }
    | '++' unary_expression
          {
            if ($arg{context} eq 'statement' ) {
              $return = "pre-increment $item{unary_expression}"; 
            } else { 
              $return = "the pre-incremented $item{unary_expression}";
            }
          }
    | '--' unary_expression  
          {
            if ($arg{context} eq 'statement' ) {
              $return = "Pre-decrement $item{unary_expression}"; 
            } else { 
              $return = "the pre-decremented $item{unary_expression}";
            }
          }
    | unary_operator cast_expression[context => $arg{context}]
          { $return = $item{unary_operator} . $item{cast_expression}; }
    |'sizeof' unary_expression 
          { $return = "the size of $item{unary_expression}"; }
    |'sizeof' '(' type_name ')' 
          { $return = "the size of the datatype $item{type_name}"; }

postfix_expression:
      primary_expression[context => $arg{context}] '(' argument_expression_list(?) ')' # function call 
          {
            push @basics, $basic; 
            $basic =  $item{primary_expression};

            if(not defined $arg{context}) {
              $return = "the result of ";
            } else {
              $return = "Perform ";
            }

            # is this function call involving a pointer to a function?
            if ($basic =~ /parenthetical/) { 
              $return .= "the function pointed by $basic"; 
            } else { 
              $return =~ s/Perform/Call/;
              $return .= "the function $basic"; 
            }

            # To discriminate between macros and functions. 
            foreach (@macros) { 
              if ($basic eq $_) { 
                $return =~ s/Call/Insert/;
                $return =~ s/function/macro/; 
              }
            }

            my $arg_exp_list = join('',@{$item{'argument_expression_list(?)'}}); 
            if ($arg_exp_list) { 
              $return .= " with argument$arg_exp_list";
            }
            1;
          }
    | primary_expression[context => $arg{context}]  
          {
            # must be global. use stack to prevent disasters.
            # Todo: this is just a Bad Idea, TM. $return needs to be turned to an hash with the 
            # arguments doing the right thing and then the last action assembles the sucker.
            push @basics, $basic; 
            $basic =  $item{primary_expression};
            $return = $item{primary_expression}; 
          }

      # array reference and plain expression
      ( '[' expression[context => 'array_address'] ']' 
          { $return = $item{expression}; } 
      )(s?)
          {
            my $item_expression = '';
            if (@{$item[-1]}) { 
              $item_expression=join(',',@{$item[-1]}); 
              $basic =~ s/^'//; 
              $basic =~ s/\'$//; 
            }

            if ( length $item_expression) { 
              $return = "array $basic\'s element at address ($item_expression)";
            }
          }

      # struct accesses:
      ( '.' identifier )(?)
          { 
            # capitalize when necessary!
            my $identifier = join('',@{$item[-1]}); 
            if ($identifier) {
              $return = "the member $identifier of structure $basic"; 
            }
          } 
      ( '->' identifier )(?) 
          {
            # capitalize when necessary!
            my $identifier = join('',@{$item[-1]}); 
            if ($identifier) {
              $return = "the member $identifier of the structure pointed to by $basic"; 
            } 
          }
      ( '++' )(?)
          {
            my $increment = join('',@{$item[-1]}); 
            if ($increment) {
              if ($arg{context} eq 'statement') { 
                $return = "increment $basic by one";
              } else { 
                $return = "$return which is incremented by one";
              }
            }
          }
      ( '--' )(?)
          {
            my $increment = join('',@{$item[-1]}); 
            if ($increment) {
              if ($arg{context} eq 'statement') { 
                $return = "decrement $basic by one";
              } else { 
               $return = "$return which is decremented by one";
              }
            }
            $basic = pop @basics; 
            1;
          }

    # having done the simplest cases, we go to the catch all for left recursions.
    | primary_expression postfix_suffix(s)
          {
            # todo: test this. formulate a syntax setup.
            print STDERR "Danger Will Robinson! Untested code testing!!\n"; 
            $return = $item{primary_expression} . "'s " . join('',@{$item{'postfix_suffix(s)'}}); 
          }

postfix_suffix:
      ('[' expression ']')(s)
    | '.' identifier 
    | '->' identifier 
    | '++' 
    | '--' 

argument_expression_list:
      <leftop: assignment_expression ',' assignment_expression >
          {
            my @arg_exp_list = @{$item[1]}; 
            my $last = ''; 
            if ($#arg_exp_list > 1) {
              $last = pop @arg_exp_list; 
              $return = 's ' . join(', ', @arg_exp_list) . ", and $last";
            } elsif ( $#arg_exp_list == 1 ) { 
              $return = "s $arg_exp_list[0] and $arg_exp_list[1]";  
            } else { 
              $return = " $arg_exp_list[0]";
            }
          } 

narrow_closure:
      ';' | ',' | '->' 

primary_expression:
      '(' expression ')' (...narrow_closure)(?)
          { 
            my $expression = $item{expression} ; 
            my $repeats = 1; 
            my $ending = 1; 

            if ($expression =~  /^the (\d+)-layered parenthetical expression/) { 
              $repeats = $1 + 1; 
              $expression =~ s/^the \d+-layered parenthetical expression //;
            } elsif ($expression =~  /^the parenthetical expression/) { 
              $repeats = 2; 
              $expression =~ s/^the parenthetical expression //;
            } 

            if ($expression =~ / now$/) { 
              $ending++; 
              $expression =~ s/ now$//; 
              $expression .= " (now drop $ending layers of context)" ; 
            } elsif ($expression =~ /now drop (\d+) layers of context\)$/ ) { 
              $ending = $1 + 1; 
              $expression =~ s/\d+ layers of context\)$/$ending layers of context \)/; 
            } else { $expression .= ' now'; } 
              if ($repeats > 1) { 
                $return = "the $repeats-layered parenthetical expression $expression"; 
              } else { 
                $return = "the parenthetical expression $expression"; 
              }

              if (@{$item[-1]}) {
                $return =~ s/ now$//;
              } 
            }
    | constant
    | string 
    | identifier

declarator:
      direct_declarator
    | pointer direct_declarator
          { $return = "$item{direct_declarator}|$item{pointer}"; }

direct_declarator:
      identifier[context => 'direct_declarator'] array_declarator(s?)
          { 
            if(@{$item{'array_declarator(s?)'}}) {
              $return = "$item{identifier}|" . join('', @{$item{'array_declarator(s?)'}});
            } else {
              $return = "$item{identifier}";
            }
          }
    | '(' declarator ')' array_declarator(s)
          { 
            my ($prefix, $name) = split / ([^ ]+)$/, $item{'declarator'};
            if(not defined $name) {
              $name = $prefix;
              $prefix = undef;
            } else {
              $prefix .= ' ';
            }

            $return = "$name|$prefix" . join('', @{$item{'array_declarator(s)'}});
          }
    | '(' declarator array_declarator(s) ')'
          { $return = $item{'declarator'} . join('', @{$item{'array_declarator(s)'}}) }
    | '(' declarator ')' 
          { $return = $item{declarator}; }

array_declarator:
      ( '[' assignment_expression(?) ']'
          {
            if (@{$item{'assignment_expression(?)'}}) { 
              $return = 'size '. join('',@{$item{'assignment_expression(?)'}}) . ' ';
            } else { 
              $return = 'unspecified size ';
            }
          }
      )(s?)
          {
            my @array = @{$item[-1]};  
            if (@array) { 
              $return .= 'an array of ' . join('of an array of ' , @array) . 'of ';
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
      <skip: '[ \t]*'> parameter_list
    | parameter_list ',' '...' # FIXME: never reached
          { $return = $item{parameter_list} . ', and possibly other arguments'; }

parameter_list:
      <leftop: parameter_declaration ',' parameter_declaration>
          {
            my @parameter_list = @{$item[1]}; 
            if ($#parameter_list > 1) {
              $return = pop(@parameter_list); 
              $return = join(', ', @parameter_list) . ', and ' . $return;  
            } elsif ($#parameter_list == 1) { 
              $return = $parameter_list[0] . ' and ' .$parameter_list[1];
            } else { 
              if(ref $parameter_list[0] eq 'ARRAY') {
                my $list = join('', @{ $parameter_list[0] });
                if(not $list) {
                  $return = "no parameters";
                } else {
                  $return = $list;
                }
              } else {
                $return = $parameter_list[0];
              }
            }
          }

parameter_declaration:
      declaration_specifiers declarator 
          { $return = $item{declaration_specifiers} . ' ' . $item{declarator}; }
    | /,?\.\.\./ 
          { $return = "variadic parameters"; }
    | declaration_specifiers abstract_declarator(?) 
    | ''
          { $return = "unspecified parameters"; }

abstract_declarator: 
      pointer 
    | pointer(?) direct_abstract_declarator 
          { $return = join('',@{$item{'pointer(?)'}}) . $item{direct_abstract_declarator}; }

direct_abstract_declarator:
      '(' abstract_declarator ')'
    | '[' ']'
    | '[' constant_expression ']'
    | DAD '[' ']'
    | DAD '[' constant_expression ']'
    | '(' ')'
    | '(' parameter_type_list ')'
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

pointer:
      '*' type_qualifier_list(s) pointer(?) 
          { 
            $return = 'a pointer to a ' . join('', @{$item{'type_qualifier_list(s)'}});
            $return .= ' ' . join('', @{$item{'pointer(?)'}}) if @{$item{'pointer(?)'}};
          }
    | ('*')(s) 
          { 
            my $size = $#{$item[1]} +1 ; 
            if ($size > 1) { 
              while($size-- > 1) {
                $return .= 'pointer to ';
              }
            }
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
            $return = join('',@{$item{'comment(?)'}}) . $item{storage_class_specifier} ;
            if ($decl_spec) { $return .=  ' ' . $decl_spec; } 
          }
    | comment(?) type_specifier declaration_specifiers(?) 
          {
            my $decl_spec = join(' ', @{$item{'declaration_specifiers(?)'}});
            $return = join('',@{$item{'comment(?)'}}) . $item{type_specifier};
            if ($decl_spec) { $return .=  ' ' . $decl_spec; } 
          }
    | comment(?) type_qualifier declaration_specifiers(?) 
          {
            my $decl_spec = $return = join('',@{$item{'comment(?)'}}) . $item{type_qualifier} . ' ' .  join(' ',@{$item{'declaration_specifiers(?)'}});
          }

storage_class_specifier:
      'auto'
          { $return = "(auto)"; }
    | 'extern'
          { $return = "(declared elsewhere)"; }
    | 'static' 
          { $return = "(this declaration is not to be shared)"; }
    | 'register'
          { $return = "(suggestion to be as fast as possible)"; }
    | 'typedef'
          { $return = 'type definition of'; }

type_qualifier:
      'const'
          { $return = "constant"; }
    | 'volatile' 

type_specifier:
      'double'
    | 'short'
    | 'long' 
    | 'char'
    | 'int' 
    | 'float'
    | 'void'
    | 'signed'
    | 'unsigned'
    | struct_or_union_specifier
    | enum_specifier
    | typedef_name 

typedef_name:
      identifier
          {
            my $answer = 0; 
            foreach (@defined_types) { 
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
            $return .= " with members $item{struct_declaration_list}"; 
          }
    | struct_or_union identifier
          {
            $item{struct_or_union} =~ s/^(a|an)/the/;
            $return = "$item{struct_or_union} $item{identifier}";
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
      specifier_qualifier_list ';'
    | comment(?) specifier_qualifier_list struct_declarator_list ';'
          { $return = join('', @{$item{'comment(?)'}}) . $item{specifier_qualifier_list} . ' ' . $item{struct_declarator_list}; }

type_name:
      specifier_qualifier_list abstract_declarator(?)
          { $return = $item{specifier_qualifier_list} . join('',@{$item{'abstract_declarator(?)'}}); }

specifier_qualifier_list:
      type_specifier specifier_qualifier_list(?) 
          { $return = $item{type_specifier} . join('', @{$item{'specifier_qualifier_list(?)'}}); }

struct_declarator_list:
      struct_declarator
    | struct_declarator ',' struct_declarator_list 
          { $return = $item{struct_declarator} . join('',@{$item{struct_declarator_list}}); }

struct_declarator:
      declarator
    | declarator(?) ':' constant_expression 
          { $return = join('',@{$item{'declarator(?)'}}) . " a bit field $item{constant_expression}"; }

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
               $return .= 'marking ' . join('', @{$item[-1]}); 
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
      /-?[0-9]*\.[0-9]+f?/ 
          {
            if ($item[1] =~ /\D/) { 
              $return = "the floating point number $item[1]";
            } else { 
              $return = $item[1];
            }
          } 
    | /0x[0-9a-fA-F]+/ ('L')(?)
          { 
            if ($item[-1]) { 
              $return = 'the long ' ."hexadecimal number $item[1]"; 
            } else { 
              $return = 'the ' . "hexadecimal number $item[1]";
            } 
          } 
    | /0\d+/
          { $return = "the octal number $item[1]"; } 
    |/-?[0-9]+[lu]?/i # integer constant
          {
            $return = $item[-1]; 
            $return =~ s/[Uu]$/(unsigned)/; 
            $return =~ s/[Ll]$/(long)/; 
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
  # | enumeration_constant 
  # needs more.
 
integer_constant:
      /[0-9]+/ 

identifier_word:
      /[a-z_\$][a-z0-9_]*/i
          { $return = "`$item[-1]`"; }

string:
      /(?:\"(?:\\\"|(?!\").)*\")/

reserved: 
      'int' | 'double' | 'short' | 'volatile' | 'register' | 'float' | 'signed'
    | 'unsigned' | 'char' | 'for' | 'if' | 'switch' | 'while' | 'do' | 'case'
    | 'extern' | 'void' | 'exit' | 'return' | 'auto' | 'break' | 'const'
    | 'continue' | 'default' | 'else' | 'enum' | 'struct' | 'goto' | 'long'
    | 'register' | 'sizeof' | 'static' | 'typedef' | 'union' 

