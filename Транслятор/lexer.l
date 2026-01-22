%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include "parser.tab.h"
    extern FILE *yyin;
%}

%%

"#include"          { return INCLUDE; }
"<stdio.h>"         { return HEADER; }

"int"               { return INT; }
"void"              { return VOID; }
"main"              { return MAIN; }
"return"            { return RETURN; }
"printf"            { return PRINTF; }
"if"                { return IF; }
"else"              { return ELSE; }
"while"             { return WHILE; }
"for"               { return FOR; }

"{"                 { return LBRACE; }
"}"                 { return RBRACE; }
"("                 { return LPAREN; }
")"                 { return RPAREN; }
";"                 { return SEMICOLON; }
","                 { return COMMA; }

"=="                { return EQ; }
"!="                { return NEQ; }
"<="                { return LE; }
">="                { return GE; }
"<"                 { return LT; }
">"                 { return GT; }

"="                 { return ASSIGN; }
"+"                 { return PLUS; }
"-"                 { return MINUS; }
"*"                 { return MUL; }
"/"                 { return DIV; }

\"([^\\\"]|\\.)*\"  { yylval.str = strdup(yytext); return STRING; } 

[0-9]+              { yylval.num = atoi(yytext); return NUMBER; }

[a-zA-Z_][a-zA-Z0-9_]*  { yylval.str = strdup(yytext); return ID; }

"//".*              { }

[ \t\r\n]+          { }

.                   { }

%%

int yywrap() { return 1; }
