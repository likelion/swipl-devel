/*  $Id$

    Copyright (c) 1990 Jan Wielemaker. All rights reserved.
    jan@swi.psy.uva.nl

    Purpose: Index online manual
*/

:- module(online,
	[ online_index/2
	, online_index/0
	]).

:- multifile
	user:portray/1.

user:portray(X) :-
	nonvar(X),
	is_list(X),
	checklist(is_ascii, X), !,
	format('"~s"', [X]).
	

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
This library module creates the index file for the  online  manual.   By
default, as expected by help.pl, the manual is called MANUAL and resides
in the Prolog library directory.  online_index[0,2] parses this file and
creates the index file help_index.pl.  Toplevel:

online_index/0
	Equivalent to online_index($MANUAL, $INDEX).  The two variables
	are taken from the Unix environment.

online_index(+Manual, +Index)
	Create index for `Manual' and write the output on `Index'.

SEE ALSO

      - The program `online' in the manual source directory
      - help.pl which implements the online manual on top of this.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- dynamic
	page/2,
	predicate/5,
	function/3,
	section/4,
	summary/3,
	end_offset/1.

online_index :-
	online_index('$MANUAL', '$INDEX').

online_index(In, Out) :-
	parse_summaries('summary.doc'),
	open(In, read, in),
	read_index,
	close(in),
	open(Out, write, out),
	write_manual,
	close(out).

%	write_manual
%	Write the index file (using the asserted data) to stream `out'.

write_manual :-
	format(out, '/*  $Id', []),
	format(out, '$~n~n', []),
	format(out, '    Generated by online_index/0~n~n', []),
	format(out, '    Purpose: Index to file online_manual~n', []),
	format(out, '*/~n~n', []),
	format(out, ':- module(help_index,~n', []),
	format(out, '	[ predicate/5~n', []),
	format(out, '	, section/4~n', []),
	format(out, '	, function/3~n', []),
	format(out, '	]).~n~n', []),
	list(predicate, 5),
	list(section, 4),
	list(function, 3).

list(Name, Arity) :-
	functor(Head, Name, Arity),
	format(out, '%   Predicate ~w/~w~n~n', [Name, Arity]),
	Head,
	    format(out, '~q.~n', Head),
	fail.
list(_, _) :-
	format(out, '~n~n', []).

%	read_index/0
%	Create an index in the prolog database.  Input is read from stream
%	`in'

read_index :-
	flag(last, _, false),
	repeat,
	    (   flag(last, true, true)
	    ->	character_count(in, EndOffset),
		End is EndOffset - 1,
		assert(end_offset(End)), !
	    ;   character_count(in, Offset),
		read_page(Page),
		character_count(in, EndOffset),
		End is EndOffset - 1,
	        identify_page(Offset, End, Page),
	        fail
	    ),
	update_offsets.

%	read_page(-Page)
%	Read the next page from stream `in'.  Pages are separeted (by
%	dvi2tty) by ^L.  The last page is ended by the end-of-file. 

read_page([C|R]) :-
	get0(in, C),
	(   C == -1
	->  flag(last, _, true),
	    fail
	;   C \== 12
	), !,
	read_page(R).
read_page([]).
	
%	identify_page(+StartOffset, +EndOffset, +Page)
%	Parse the start of `Page' and record it in the database as a
%	page describing a certain type of data as well as were it starts
%	and ends.

identify_page(Offset, EndOffset, Page) :-
	parse(page(Type, TextOffset), Page, _),
%	format('~w~n', page(Type, offsets(Offset, EndOffset, TextOffset))),
	assert(page(Type, offsets(Offset, EndOffset, TextOffset))).

parse(page(Type, Offset)) -->
	skip_blank_lines(0, Offset),
	get_line(Line),
	type(Line, Type).

skip_blank_lines(Sofar, Offset) -->
	blank_line(Line), !,
	{   length(Line, L),
	    NextSofar is Sofar + L
	},
	skip_blank_lines(NextSofar, Offset).
skip_blank_lines(Offset, Offset) -->
	{ true }.

blank_line([10]) -->
	char(10), !.
blank_line([C|R]) -->
	blank(C), !,
	blank_line(R).

get_line([]) -->
	char(10), !.
get_line([C|R]) -->
	char(C),
	get_line(R).

%	Typing on the first line

type(Line, predicate(Name, Arity, Summary)) -->
	{ predicate_line(Line, Name, Arity),
	  (   summary(Name, Arity, Summary)
	  ->  true
	  ;   format('ERROR: No summary for ~w/~w~n', [Name, Arity]),
	      Summary = ''
	  )
        }, !.
type(Line, section(Index, Name)) -->
	{ section_line(Line, Index, Name) }, !.
type(Line, section(Index, Name)) -->
	{ chapter_line(Line, Index) }, !,
	skip_blank_lines(0, _),
	get_line(NameLine),
	{ name(Name, NameLine)}.
type(Line, function(Name)) -->
	{ function_line(Line, Name) }, !.
type(Line, unknown) -->
	{ % trace,
	  format('Unidentified: ~s~n', [Line])
	}.
type(_, _) -->
	{ fail }.

%	Identify line as describing a predicate

predicate_line(Line, Name, Arity) :-
	predicate_line(Name, Arity, Line, []).

predicate_line(Name, Arity) -->
	optional_directive,
	atom(Name),
	arguments(Arity), !,
	{   (   functor(T, Name, Arity),
		user:current_predicate(_, T)
	    ;   current_arithmetic_function(T)
	    )
	->  true
	;   format('Not a defined predicate: ~w/~w~n', [Name, Arity])
	}.
predicate_line(Name, 1) -->			% prefix operator
	atom(Name),
	skip_blanks,
	arg,
	optional_dots, !.
predicate_line(Name, 2) -->			% infix operator
	skip_blanks,
	arg,
	skip_blanks,
	atom(Name),
	skip_blanks,
	arg,
	skip_blanks, !.
predicate_line(Name, 0) -->
	atom(Name).

optional_directive -->
	starts(":- "), !,
	skip_blanks.
optional_directive -->
	{ true }.

atom(Name) -->
	lower_case(C1), !,
	alphas(Cs),
	{ name(Name, [C1|Cs]) }.
atom(Name) -->
	symbol(C1), !,
	symbols(Cs),
	{ name(Name, [C1|Cs]) }.
atom(Name) -->
	single(S),
	{ name(Name, [S]) }.

alphas([C|R]) -->
	alpha(C), !,
	alphas(R).
alphas([]) -->
	{ true }.

arguments(Args) -->
	char(0'(),
	args(0, Args),
	char(0')).

args(N, Args) -->
	skip_blanks,
	arg,
	{ NN is N + 1 }, !,
	optional(0',),
	args(NN, Args).
args(Args, Args) -->
	{ true }.

optional_dots -->
	skip_blanks,
	starts(", ..."),
	skip_blanks.
optional_dots -->
	{ true }.

arg -->
	input_output,
	alphas(_),
	optional(0'/),
	optional_input_output,
	alphas(_), !.
arg -->
	starts("[]").

input_output -->
	char(C),
	{ memberchk(C, "+-?") }.

optional_input_output -->
	input_output, !.
optional_input_output -->
	{ true }.

%	Identify line as describing a function

function_line(Line, Name) :-
	function_line(Name, Line, _).

function_line(Name) -->
	function_type,
	function_name(Name).

function_type -->
	skip_blanks,
	alpha(_),
	alpha(_),
	atom(_),
	skip_blanks,
	optional(0'(),
	optional(0'*),
	skip_blanks.

function_name(Name) -->
	char(0'P),
	char(0'L),
	char(0'_),
	atom(Rest),
	{ concat('PL_', Rest, Name) }.

%	Identify line as starting a section

section_line(Line, Index, Name) :-
	section_index(Index, Line, S),
	name(Name, S).

section_index([C|R]) -->
	skip_blanks,
	number(C),
	subindex(R),
	skip_blanks.

subindex([S|R]) -->
	char(0'.), !,
	number(S),
	subindex(R).
subindex([]) -->
	{ true }.

number(N) -->
	digits(D),
	{ D = [_|_] },
	{ name(N, D) }.

digits([D|R]) -->
	digit(D), !,
	digits(R).
digits([]) -->
	{ true }.

%	Identify line as starting a chapter

chapter_line(Line, Index) :-
	chapter_line(Index, Line, []).

chapter_line([Chapter]) -->
	starts("Chapter"),
	skip_blanks,
	number(Chapter).

starts([]) -->
	!.
starts([C|R]) -->
	char(C),
	starts(R).

%	PRIMITIVES.

skip_blanks -->
	blank(_), !,
	skip_blanks.
skip_blanks -->
	{ true }.

blank(C) -->
	char(C),
	{ blank(C) }.
	
blank(9).
blank(32).

optional(List, In, Out) :-
	is_list(List), !,
	(   append(List, Out, In)
	->  true
	;   Out = In
	).
optional(C) -->
	char(C), !.
optional(_) -->
	{ true }.

symbols([C|R])-->
	symbol(C), !,
	symbols(R).
symbols([]) -->
	{ true }.

symbol(S) -->
	char(S),
	{ memberchk(S, "\#$&*+-./:<=>?@^`~") }.

single(S) -->
	char(S),
	{ memberchk(S, "!,;|") }.

digit(D) -->
	char(D),
	{ between(0'0, 0'9, D) }.

lower_case(C) -->
	char(C),
	{ between(0'a, 0'z, C) }.

upper_case(C) -->
	char(C),
	{ between(0'A, 0'Z, C) }.

alpha(C) -->
	lower_case(C), !.
alpha(C) -->
	upper_case(C), !.
alpha(C) -->
	digit(C), !.
alpha(0'_) -->
	char(0'_).

char(C, [C|L], L).
	
%	update_offsets

update_offsets :-
	page(section(Index, Name), offsets(F, _, O)),
	    (   next_index(Index, Next),
		page(section(Next, _), offsets(To,_,_))
	    ->  true
	    ;	end_offset(To)
	    ),
	    From is F + O,
	    assert(section(Index, Name, From, To)),
	fail.
update_offsets :-
	page(predicate(Name, Arity, Summary), offsets(F, T, O)),
	    From is F + O,
	    assert(predicate(Name, Arity, Summary, From, T)),
	fail.
update_offsets :-
	page(function(Name), offsets(F, T, O)),
	    From is F + O,
	    assert(function(Name, From, T)),
	fail.
update_offsets.

%	next_index(+This, -Next)
%	Return index of next section.  Note that the next of [3,4] both
%	can be [3-5] and [4].

next_index(L, N) :-
	(    reverse(L, [Last|Tail])
	;    reverse(L, [_,Last|Tail])
	),
	Next is Last + 1,
	reverse([Next|Tail], N).

	
		/********************************
		*       PARSE SUMMARIES         *
		********************************/
	
%	parse_summaries(+File)
%	Reads the predicate summary chapter of the manual to get the
%	summary descriptions.  Normally this file is called summary.doc

parse_summaries(File) :-
	open(File, read, in),
	parse_summaries,
	close(in).

parse_summaries :-
	repeat,
	read_line(Line),
	(   Line == end_of_file
	->  !
	;   do_summary(Line),
	    fail
	).

read_line(L) :-
	get0(in, C),
	(   C == -1
	->  L = end_of_file
	;   C == 10
	->  L = []
	;   L = [C|R],
	    read_line(R)
	).

do_summary(Line) :-
	parse_summary(Name, Arity, Summary, Line, []), !,
	(   Name == 0
	->  true
	;   assert(summary(Name, Arity, Summary))
	).
do_summary(Line) :-
%	trace,
	format('Failed to parse "~s"~n', [Line]).
do_summary(_) :- fail.

parse_summary(Name, Arity, Summary) -->
	optional("\\"),
	skip_blanks,
	starts("\verb"),
	[VC],
	name_arity(Name, Arity),
	string(_),
	[VC],
	skip_blanks,
	starts("\>"),
	skip_blanks,
	summary_description(S),
	skip_blanks,
	optional("\\"),
	skip_blanks,
	{ name(Summary, S) }, !.
parse_summary(0, _, _) -->
	(   "%"
	;   "\chapter"
	;   "\section"
	;   "\begin"
	;   "\end"
	;   "\newcommand"
	), !,
	string(_).
parse_summary(0, _, _) -->
	string(_),
	"\kill", !,
	string(_).
parse_summary(0, _, _) -->
	"\\".
parse_summary(0, _, _) -->		% operator descriptions
	optional("\\"),
	skip_blanks,
	starts("\verb"),
	[_],
	skip_blanks,
	number(_), !,
	string(_).
parse_summary(0, _, _) -->
	[].

summary_description(S) -->
	"\lib{",
	string(Lib),
	"}", !,
	summary_description(S2),
	{flatten(["library(", Lib, "):", S2], S)}.
summary_description(S) -->
	"\hook{",
	string(_Module),
	"}", !,
	summary_description(S2),
	{append("hook:", S2, S)}.
summary_description([]) --> {true}.
summary_description([H|T]) -->
	[H],
	summary_description(T).

name_arity(Name, Arity) -->
	string(S),
	skip_blanks,
	"/",
	optional(0'[),
	number(Arity), !,
	{ name(Name, S) }.

string("") -->
	{ true }.
string([C|R]) -->
	char(C),
	string(R).
