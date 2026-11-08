% Input/output examples for a Prolog repo: runs its real predicates on 200 inputs made the
% same way every time, and writes io/ios.txt (to read) and io/ios.pl (one io/4 fact each).
%
%   swipl io/make_ios.pl     writes both files
%   swipl io/check_ios.pl    runs the 200 inputs again; fails if any output changed
%
% The repo's io/cases.pl says what to run:
%   io_title(Title).
%   io_cases([Name, ...]).          predicates, taken in turn
%   io_input(Name, K, Args).        the K-th list of inputs for Name (K = 1, 2, ...)
%   io_run(Name, Args, Output).     runs it; Output is what it gives
% An input that fails gives false; one that raises an error gives error(...); one that runs
% over 10 seconds gives error(time_limit_exceeded).

:- module(ios_engine, [make_ios/0, check_ios/0, pick/4, pick_n/5, num/5, load_repo/1, consult_repo/1]).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).
:- use_module(library(time)).

ios_dir(Dir) :- prolog_load_context(directory, Dir), !.
ios_dir(io).

:- dynamic io_dir_/1.
:- ios_dir(D), retractall(io_dir_(_)), assertz(io_dir_(D)).

io_file(Name, Path) :- io_dir_(D), atomic_list_concat([D, '/', Name], Path).

% Loading the repo's own files from io/cases.pl (paths from the repo's top folder).
repo_path(Rel, Abs) :- io_dir_(D), file_directory_name(D, Top), atomic_list_concat([Top, '/', Rel], Abs).
load_repo(Rel) :- repo_path(Rel, F), user:use_module(F).
consult_repo(Rel) :- repo_path(Rel, F), user:consult(F).

count(200).

% Choosing inputs without randomness, so they are the same on every machine:
% pick(K, Salt, List, X): an element of List chosen by K and Salt.
% The first len(List) picks go through the whole list; each later round starts elsewhere,
% so inputs picked from lists of the same length still meet in new combinations.
pick(K, Salt, List, X) :-
    length(List, L), L > 0,
    I is (K - 1 + Salt * 5 + ((K - 1) // L) * (Salt + 1)) mod L,
    nth0(I, List, X).
% pick_n(K, Salt, Max, List, Xs): 1..Max elements of List.
pick_n(K, Salt, Max, List, Xs) :-
    N is 1 + (K * 31 + Salt * 17) mod Max,
    numlist(1, N, Is),
    maplist([I, X]>>(S2 is Salt * 13 + I, pick(K, S2, List, X)), Is, Xs).
% num(K, Salt, Lo, Hi, N): a whole number from Lo to Hi.
num(K, Salt, Lo, Hi, N) :- R is Hi - Lo + 1, N is Lo + (K - 1 + Salt * 3 + ((K - 1) // R) * (Salt + 1)) mod R.

% One example: N-th, case Name, its K-th input.
example(N, io(N, Name, Args, Output)) :-
    user:io_cases(Cases),
    length(Cases, L),
    I is (N - 1) mod L,
    K is (N - 1) // L + 1,
    nth0(I, Cases, Name),
    catch(user:io_input(Name, K, Args), E,
          ( format(user_error, "Making input ~d for ~w raised ~q~n", [K, Name, E]), throw(E) )),
    ( var(Args) -> format(user_error, "No input ~d for ~w~n", [K, Name]), fail ; true ),
    run(Name, Args, Output).

% Runs on a copy of the inputs, so they stay as they were; variables of the inputs that the
% run leaves unbound are tied back to the originals, so the output shows the same names.
run(Name, Args, Output) :-
    copy_term(Args, Args1),
    term_variables(Args, Vs), term_variables(Args1, V1s),
    catch(call_with_time_limit(10, (user:io_run(Name, Args1, O) -> Output0 = O ; Output0 = false)),
          E, error_of(E, Output0)),
    tie(V1s, Vs),
    Output = Output0.
tie([], []).
tie([V1 | V1s], [V | Vs]) :- ( var(V1), \+ ( member(W, Vs), W == V1 ) -> V1 = V ; true ), tie(V1s, Vs).

error_of(time_limit_exceeded, error(time_limit_exceeded)) :- !.
error_of(error(Formal, _), error(Formal)) :- !.
error_of(E, error(E)).

examples(Ios) :-
    count(C),
    numlist(1, C, Ns),
    maplist(example, Ns, Ios).

text_of(Ios, Text) :-
    user:io_title(Title),
    length(Ios, C),
    format(string(Head), "~w: ~d inputs and outputs, from real runs (swipl io/make_ios.pl writes this file; swipl io/check_ios.pl checks it).~n~n", [Title, C]),
    maplist(io_text, Ios, Parts),
    atomic_list_concat([Head | Parts], Text).

io_text(io(N, Name, Args, Out), Text) :-
    copy_term(Args-Out, A-O),
    numbervars(A-O, 0, _),
    maplist([X, S]>>format(string(S), "~W", [X, [quoted(true), numbervars(true), portray(false), max_depth(0), priority(999), spacing(next_argument)]]), A, Ss),
    atomic_list_concat(Ss, ', ', ArgText),
    format(string(OText), "~W", [O, [quoted(true), numbervars(true), portray(false), max_depth(0), priority(999), spacing(next_argument)]]),
    format(string(Text), "~d. ~w(~w)~n   => ~w~n", [N, Name, ArgText, OText]).

write_facts(Path, Ios) :-
    setup_call_cleanup(open(Path, write, S, [encoding(utf8)]),
        ( format(S, "% ~d inputs and outputs, from real runs: io(N, Predicate, Inputs, Output).~n", [200]),
          forall(member(Io, Ios),
                 ( copy_term(Io, Io1), numbervars(Io1, 0, _),
                   write_term(S, Io1, [quoted(true), numbervars(true), portray(false), fullstop(true), nl(true), max_depth(0)]) )) ),
        close(S)).

make_ios :-
    examples(Ios),
    text_of(Ios, Text),
    io_file('ios.txt', TxtPath),
    setup_call_cleanup(open(TxtPath, write, S, [encoding(utf8)]), write(S, Text), close(S)),
    io_file('ios.pl', FactsPath),
    write_facts(FactsPath, Ios),
    include([io(_, _, _, O)]>>(nonvar(O), O = error(_)), Ios, Errs), length(Errs, NE),
    include([io(_, _, _, O)]>>(O == false), Ios, Fails), length(Fails, NF),
    length(Ios, C),
    format("~d inputs and outputs written to io/ios.txt and io/ios.pl (~d failed, ~d raised errors)~n", [C, NF, NE]).

saved(Ios) :-
    io_file('ios.pl', Path),
    setup_call_cleanup(open(Path, read, S, [encoding(utf8)]), read_all(S, Ios), close(S)).
read_all(S, Ios) :-
    read_term(S, T, []),
    ( T == end_of_file -> Ios = [] ; Ios = [T | Rest], read_all(S, Rest) ).

check_ios :-
    saved(Saved),
    length(Saved, C),
    ( C =:= 200 -> true ; format("io/ios.pl has ~d examples, not 200~n", [C]), fail ),
    findall(N, ( member(io(N, Name, Args, Out), Saved),
                 run(Name, Args, New),
                 \+ Args-Out =@= Args-New,
                 copy_term(Out-New, O1-N1), numbervars(O1-N1, 0, _),
                 format("example ~d (~w) changed:~n   was ~W~n   now ~W~n", [N, Name, O1, [quoted(true), numbervars(true), max_depth(12)], N1, [quoted(true), numbervars(true), max_depth(12)]]) ),
            Changed),
    length(Changed, NC),
    examples(Ios), text_of(Ios, Text),
    io_file('ios.txt', TxtPath), read_file_to_string(TxtPath, Old, [encoding(utf8)]),
    ( Old == Text -> TextSame = true ; TextSame = false, format("io/ios.txt is not what the cases give now~n") ),
    ( NC =:= 0, TextSame == true
    -> format("All ~d inputs give the same outputs.~n", [C])
    ;  format("~d of ~d outputs changed. If that is meant, run swipl io/make_ios.pl and check the diff.~n", [NC, C]), fail ).
