%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    #define YYDEBUG 1

    int yylex(void);
    int yyerror(char *s);
    extern FILE *yyout;
    extern FILE *yyin;

    int is_main = 0;      /* сейчас парсим main или обычную функцию */
    int indent  = 0;      /* текущий уровень отступа */

    void print_indent(void) {
        /* используем глобальный indent */
        for (int i = 0; i < indent; ++i)
            fprintf(yyout, "    ");  /* 4 пробела */
    }
%}

/* семантические типы */
%union{
    char *str;
    int   num;
}

/* токены */
%token INCLUDE HEADER INT MAIN RETURN PRINTF VOID
%token IF ELSE WHILE FOR
%token LBRACE RBRACE LPAREN RPAREN SEMICOLON COMMA
%token ASSIGN PLUS MINUS MUL DIV
%token EQ NEQ LE GE LT GT
%token <str> STRING
%token <num> NUMBER
%token <str> ID

/* типы нетерминалов */
%type <str> expr func_call_stmt
%type <str> param_list param_list_opt
%type <str> for_init_opt for_cond_opt for_post_opt
%type <str> arg_list


/* приоритеты */
%left EQ NEQ LT GT LE GE 
%left PLUS MINUS
%left MUL DIV
%right UMINUS
%left LPAREN  /* добавьте это для вызова функций */

%%
/* ======= вся программа ======= */
program:
      /* пусто */
    | program include
    | program function
    ;

/* #include <stdio.h> */
include:
    INCLUDE HEADER
    ;

/* ======= функции ======= */
function:
      func_header compound_stmt
        {
            if (is_main) {
                /* хвост запуска main */
                fprintf(yyout,
                    "\nif __name__ == \"__main__\":\n"
                    "    main()\n");
                is_main = 0;
            }
        }
    ;

func_header:
      INT MAIN LPAREN RPAREN
        {
            indent = 0;           /* новая верхнеуровневая функция */
            print_indent();
            fprintf(yyout, "def main():\n");
            is_main = 1;
            indent = 1;           /* тело main -> один отступ */
        }
    | INT MAIN LPAREN VOID RPAREN
        {
            indent = 0;
            print_indent();
            fprintf(yyout, "def main():\n");
            is_main = 1;
            indent = 1;
        }
    | INT ID LPAREN param_list_opt RPAREN
        {
            indent = 0;           /* обычная функция тоже с нулевого отступа */
            print_indent();
            fprintf(yyout, "def %s(%s):\n", $2, $4);
            is_main = 0;
            indent = 1;
        }
    ;

/* параметры функции: int a, int b, ... */
param_list_opt:
      /* нет параметров */
        { $$ = strdup(""); }
    | param_list
        { $$ = $1; }
    ;

param_list:
      INT ID
        {
            $$ = strdup($2);
        }
    | param_list COMMA INT ID
        {
            $$ = malloc(strlen($1) + strlen($4) + 3);
            sprintf($$, "%s, %s", $1, $4); //?
        }
    ;

/* ======= блоки и операторы ======= */

compound_stmt:
    LBRACE stmt_list_opt RBRACE
    ;

stmt_list_opt:
      /* пусто */
    | stmt_list
    ;

stmt_list:
      stmt
    | stmt_list stmt
    ;

stmt:
      printf_stmt
    | return_stmt
    | var_decl
    | assign_stmt
    | if_stmt
    | while_stmt
    | for_stmt
    | func_call_stmt
    ;

printf_stmt:
      PRINTF LPAREN STRING RPAREN SEMICOLON
        {
            print_indent();
            fprintf(yyout, "print(%s)\n", $3);
        }
    | PRINTF LPAREN STRING COMMA expr RPAREN SEMICOLON
        {
            print_indent();
            fprintf(yyout, "print(%s)\n", $5);
        }
    ;

return_stmt:
    RETURN expr SEMICOLON
        {
            print_indent();
            fprintf(yyout, "return %s\n", $2);
        }
    ;

var_decl:
    INT ID SEMICOLON
        {
            print_indent();
            fprintf(yyout, "%s = 0\n", $2);
        }
    | INT ID ASSIGN expr SEMICOLON
        {
            print_indent();
            fprintf(yyout, "%s = %s\n", $2, $4);
        }
    ;

assign_stmt:
    ID ASSIGN expr SEMICOLON
        {
            print_indent();
            fprintf(yyout, "%s = %s\n", $1, $3);
        }
    ;

func_call_stmt:
    ID LPAREN arg_list RPAREN SEMICOLON
        {
            print_indent();
            fprintf(yyout, "%s(%s)\n", $1, $3);
        }
    | ID LPAREN RPAREN SEMICOLON
        {
            print_indent();
            fprintf(yyout, "%s()\n", $1);
        }
    ;

/* ======= if / else if / else ======= */

if_stmt:
    IF LPAREN expr RPAREN
        {
            print_indent();
            fprintf(yyout, "if %s:\n", $3);
            indent++;
        }
    compound_stmt
        {
            /* тело if закончено — возвращаем отступ к уровню if */
            indent--;
        }
    if_tail_opt
    ;

/* хвост if: цепочка elif/else или ничего */
if_tail_opt:
      /* пусто */
    | if_tail
    ;

/* цепочка elif/else:
   - либо несколько "else if (...) { ... }" подряд
   - либо в конце "else { ... }"
*/
if_tail:
      ELSE IF LPAREN expr RPAREN
        {
            print_indent();
            fprintf(yyout, "elif %s:\n", $4);
            indent++;
        }
      compound_stmt
        {
            indent--;
        }
      if_tail_opt
    | ELSE
        {
            print_indent();
            fprintf(yyout, "else:\n");
            indent++;
        }
      compound_stmt
        {
            indent--;
        }
    ;

/* ======= while ======= */

while_stmt:
    WHILE LPAREN expr RPAREN
        {
            print_indent();
            fprintf(yyout, "while %s:\n", $3);
            indent++;
        }
    compound_stmt
        {
            indent--;
        }
    ;

/* ======= for (init; cond; post) ======= */
/* Преобразуем в:
   init
   while cond:
       body
       post
*/

for_stmt:
    FOR LPAREN for_init_opt SEMICOLON for_cond_opt SEMICOLON for_post_opt RPAREN
        {
            /* init перед while */
            if ($3 && strlen($3) > 0) {
                print_indent();
                fprintf(yyout, "%s\n", $3);
            }
            print_indent();
            fprintf(yyout, "while %s:\n", ($5 && strlen($5) > 0) ? $5 : "True");
            indent++;
        }
    compound_stmt
        {
            /* пост-выражение в конце каждой итерации */
            if ($7 && strlen($7) > 0) {
                print_indent();
                fprintf(yyout, "%s\n", $7);
            }
            indent--;
        }
    ;

for_init_opt:
      /* пусто */
        { $$ = strdup(""); }
    | ID ASSIGN expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s = %s", $1, $3);
        }
    | INT ID ASSIGN expr
        {
            $$ = malloc(strlen($2) + strlen($4) + 4);
            sprintf($$, "%s = %s", $2, $4);
        }
    ;

for_cond_opt:
      /* пусто — условие по умолчанию True */
        { $$ = strdup(""); }
    | expr
        { $$ = $1; }
    ;

for_post_opt:
      /* пусто */
        { $$ = strdup(""); }
    | ID ASSIGN expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s = %s", $1, $3);
        }
    ;

/* ======= выражения: числа, переменные, вызовы функций, арифметика, сравнения ======= */

expr:
      NUMBER
        {
            char buf[32];
            sprintf(buf, "%d", $1);
            $$ = strdup(buf);
        }
    | ID
        {
            $$ = strdup($1);
        }
    | ID LPAREN arg_list RPAREN
        {
            $$ = malloc(strlen($1) + strlen($3) + 3);
            sprintf($$, "%s(%s)", $1, $3);
        }
    | ID LPAREN RPAREN
        {
            $$ = malloc(strlen($1) + 3);
            sprintf($$, "%s()", $1);
        }
    | expr PLUS expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s + %s", $1, $3);
        }
    | PLUS expr %prec UMINUS
        {
            $$ = malloc(strlen($2) + 2);
            sprintf($$, "+%s", $2);
        }
    | expr MINUS expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s - %s", $1, $3);
        }
    | MINUS expr %prec UMINUS
        {
            $$ = malloc(strlen($2) + 2);
            sprintf($$, "-%s", $2);
        }
    | expr MUL expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s * %s", $1, $3);
        }
    | expr DIV expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s / %s", $1, $3);
        }
    | expr LT expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s < %s", $1, $3);
        }
    | expr GT expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 4);
            sprintf($$, "%s > %s", $1, $3);
        }
    | expr LE expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 5);
            sprintf($$, "%s <= %s", $1, $3);
        }
    | expr GE expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 5);
            sprintf($$, "%s >= %s", $1, $3);
        }
    | expr EQ expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 5);
            sprintf($$, "%s == %s", $1, $3);
        }
    | expr NEQ expr
        {
            $$ = malloc(strlen($1) + strlen($3) + 5);
            sprintf($$, "%s != %s", $1, $3);
        }
    | LPAREN expr RPAREN
        {
            $$ = strdup($2);
        }
    ;

arg_list:
      expr
        {
            $$ = $1;
        }
    | arg_list COMMA expr
        {
            $$ = malloc(strlen($1) + 2 + strlen($3) + 1);
            sprintf($$, "%s, %s", $1, $3);  /* добавил пробел для читаемости */
        }
    ;
%%

int main(void) {

    yyout = fopen("output.txt","w");
    if (!yyout) {
        printf("Cannot open output.txt for writing\n");
        return 1;
    }

    char fname[256];

    printf("Enter the name of file\n");
    if (scanf("%255s", fname) != 1) {
        printf("No input file name\n");
        return 1;
    }

    FILE *pt = fopen(fname, "r");
    if(!pt)
    {
        printf("Cannot open input file\n");
        return -1;
    }
    yyin = pt;


       extern int yydebug;
       yydebug = 1;


    yyparse();

    fclose(pt);
    fclose(yyout);
    return 0;
}

int yyerror(char* s){
    printf("ERROR: %s\n", s);
    return 0;
}
