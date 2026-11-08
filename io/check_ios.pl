% Runs the 200 inputs in io/ios.pl again and fails if any output changed: swipl io/check_ios.pl
:- initialization(main, main).
:- prolog_load_context(directory, D), atom_concat(D, '/ios_engine.pl', E), use_module(E).
:- prolog_load_context(directory, D), atom_concat(D, '/cases.pl', C), consult(C).
main :- ( ios_engine:check_ios -> halt(0) ; halt(1) ).
