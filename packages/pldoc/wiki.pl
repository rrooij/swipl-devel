/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        wielemak@science.uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 1985-2006, University of Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(pldoc_wiki,
	  [ wiki_lines_to_dom/3,	% +Lines, +Map, -DOM
	    indented_lines/3,		% +Text, +PrefixChars, -Lines
	    strip_leading_par/2		% +DOM0, -DOM
	  ]).
:- use_module(library(lists)).
:- use_module(library(debug)).


		 /*******************************
		 *	    WIKI PARSING	*
		 *******************************/

%%	wiki_lines_to_dom(+Lines:lines, +Args:list(atom), -Term) is det
%
%	Translate a Wiki text into  an   HTML  term suitable for html//1
%	from the html_write library.

wiki_lines_to_dom(Lines, Args, HTML) :-
	tokenize_lines(Lines, Tokens),
	wiki_structure(Tokens, Pars),
	wiki_faces(Pars, Args, HTML).

%%	wiki_structure(+Lines:lines, -Pars:list(par)) is det
%
%	Get the structure in terms of  paragraphs, lists and tables from
%	the  lines.  This  processing  uses  a  mixture  of  layout  and
%	punctuation.

wiki_structure([], []) :- !.
wiki_structure([_-[]|T], Pars) :- !,	% empty lines
	wiki_structure(T, Pars).
wiki_structure(Lines, [\tags(Tags)]) :-
	tags(Lines, Tags), !.
wiki_structure(Lines, [P1|PL]) :-
	take_par(Lines, P1, RestLines),
	wiki_structure(RestLines, PL).
	
take_par(Lines, List, Rest) :-
	list_item(Lines, Type, Indent, LI, LIT, Rest0), !,
	rest_list(Rest0, Type, Indent, LIT, [], Rest),
	List =.. [Type, LI].
take_par([N-['|'|RL1]|LT], table([tr(R0)|RL]), Rest) :-
	phrase(row(R0), RL1),
	rest_table(LT, N, RL, Rest), !.
take_par([_-L1|LT], p(Par), Rest) :- !,
	append(L1, PT, Par),
	rest_par(LT, PT, Rest).
take_par([Verb|Lines], Verb, Lines).

%%	list_item(+Lines, ?Type, ?Indent, -LI0, -LIT, -RestLines) is det.
%
%	Create a list-item. Naturally this should produce a single item,
%	but DL lists produce two items, so   we create the list of items
%	as a difference list.

list_item([Indent-Line|LT], Type, Indent, Items, ItemT, Rest) :- !,
	list_item_prefix(Type, Line, L1),
	(   Type == dl
	->  append(DT0, [:|DD], L1),
	    append(DD, LIT, LI0),
	    strip_ws(DT0, DT),
	    Items = [dt(DT),dd(DD)|ItemT]
	;   append(L1, LIT, LI0),
	    Items = [li(LI0)|ItemT]
	),
	rest_list_item(LT, Type, Indent, LIT, Rest).
list_item(Lines, _, Indent, [SubList|LIT], LIT, Rest) :-	% sub-list
	nonvar(Indent),
	Lines = [SubIndent-Line|_],
	SubIndent > Indent,
	list_item_prefix(_, Line, _), !,
	take_par(Lines, SubList, Rest).

%%	rest_list_item(+Lines, +Type, +Indent, -RestItem, -RestLines) is det

rest_list_item([], _, _, [], []).
rest_list_item([_-[]|L], _, _, [], L) :- !.	% empty line
rest_list_item(L, _, N, [], L) :-		% less indented
	L = [I-_|_], I < N, !.
rest_list_item(L, _, _, [], L) :-		% Start with mark
	L = [_-Line|_],
	list_item_prefix(_, Line, _), !.
rest_list_item([_-L1|L0], Type, N, ['\n'|LI], L) :-
	append(L1, LIT, LI),
	rest_list_item(L0, Type, N, LIT, L).

%%	rest_list(+Lines, +Type, +Indent,
%		  -Items, -ItemTail, -RestLines) is det.

rest_list(Lines, Type, N, Items, IT, Rest) :-
	list_item(Lines, Type, N, Items, IT0, Rest0), !,
	rest_list(Rest0, Type, N, IT0, IT, Rest).
rest_list(Rest, _, _, IT, IT, Rest).

%%	list_item_Line(?Type, +Line, -Rest) is det.

list_item_prefix(ul, [*, ' '|T], T) :- !.
list_item_prefix(dl, [$, ' '|T], T) :-
	memberchk(:, T), !.
list_item_prefix(ol, [N, '.', ' '|T], T) :-
	string(N),
	string_to_list(N, [D]),
	between(0'0, 0'9, D).

%	row(-Cells)// is det.

row([C0|CL]) -->
	cell(C0), !,
	row(CL).
row([]) -->
	[].

cell(td(C)) -->
	string(C0),
	['|'], !,
	{ strip_ws(C0, C)
	}.

rest_table([N-['|'|RL1]|LT], N, [tr(R0)|RL], Rest) :- !,
	phrase(row(R0), RL1),
	rest_table(LT, N, RL, Rest).
rest_table(Rest, _, [], Rest).

%%	rest_par(+Lines, -Part, -RestLines) is det.

rest_par([], [], []).
rest_par([_-[]|Rest], [], Rest) :- !.
rest_par([_-L1|LT], ['\n'|Par], Rest) :-
	append(L1, PT, Par),
	rest_par(LT, PT, Rest).


%%	strip_ws(+Tokens, -Stripped)
%
%	Strip leading and trailing whitespace from a token list.  Note
%	the the whitespace is already normalised.

strip_ws([' '|T0], T) :- !,
	strip_ws(T0, T).
strip_ws(L0, L) :-
	append(L, [' '], L0), !.
strip_ws(L, L).


%%	strip_leading_ws(+Tokens, -Stripped) is det.
%

strip_leading_ws([' '|T], T) :- !.
strip_leading_ws(T, T).


		 /*******************************
		 *	       TAGS		*
		 *******************************/

%%	tags(+Lines:lines, -Tags) is semidet.
%
%	If the first line is a @tag, read the remainder of the lines to
%	a list of \tag(Name, Value) terms.

tags(Lines, Tags) :-
	collect_tags(Lines, Tags0),
	keysort(Tags0, Tags1),
	finalize_tags(Tags1, Tags).

collect_tags([], []).
collect_tags([Indent-[@,String|L0]|Lines], [Order-tag(Tag,Value)|Tags]) :-
	tag_name(String, Tag, Order), !,
	strip_leading_ws(L0, L),
	append(L, VT, Value),
	rest_tag(Lines, Indent, VT, [], RestLines),
	collect_tags(RestLines, Tags).


%%	tag_name(+String, -Tag:atom, -Order:int) is semidet.
%
%	If String denotes a know tag-name, 

tag_name(String, Tag, Order) :-
	string(String),
	format(atom(Name), '~s', [String]),
	(   renamed_tag(Name, Tag),
	    tag_order(Tag, Order)
	->  print_message(warning, pldoc(depreciated_tag(Name, Tag)))
	;   tag_order(Name, Order)
	->  Tag = Name
	;   print_message(warning, pldoc(unknown_tag(Name))),
	    fail
	).


rest_tag([], _, VT, VT, []) :- !.
rest_tag(Lines, Indent, VT, VT, Lines) :-
	Lines = [Indent-[@,NameS|_]|_],
	string(NameS), !.
rest_tag([_-L|Lines0], Indent, VT0, VT, Lines) :-
	append(['\n'|L], VT1, VT0),
	rest_tag(Lines0, Indent, VT1, VT, Lines).


%%	renamed_tag(+DepreciatedTag:atom, -Tag:atom) is semidet.
%
%	Declaration for depreciated tags.

renamed_tag(exception, throws).


%%	tag_order(+Tag:atom, -Order:int) is semidet.
%
%	Both declares the know tags and  their expected order. Currenrly
%	the tags are forced into  this   order  without  warning. Future
%	versions may issue a warning if the order is inconsistent.

tag_order(param,       1).
tag_order(throws,      2).
tag_order(author,      3).
tag_order(version,     4).
tag_order(see,	       5).
tag_order(depreciated, 6).
tag_order(compat,      7).		% PlDoc extension


%%	finalize_tags(+TaggedTags:list, -Tags:list) is det.
%
%	Creates the final tag-list.  Tags is a list of
%	
%		* \params(List of \param(Name, Descr))
%		* \tag(Name, Value)

finalize_tags([], []).
finalize_tags([_-tag(param, V1)|T0], [\params([P1|PL])|Tags]) :- !,
	param_tag(V1, P1),
	param_tags(T0, PL, T1),
	finalize_tags(T1, Tags).
finalize_tags([_-tag(Tag,Value)|T0], [\tag(Tag, Value)|T]) :-
	finalize_tags(T0, T).

param_tag([PN|Descr0], \param(PN, Descr)) :-
	strip_leading_ws(Descr0, Descr).

param_tags([_-tag(param, V1)|T0], [P1|PL], T) :- !,
	param_tag(V1, P1),
	param_tags(T0, PL, T).
param_tags(T, [], T).


		 /*******************************
		 *	       FACES		*
		 *******************************/

%%	wiki_faces(+Structure, +ArgNames, -HTML)
%
%	Given the wiki structure, analyse the content of the paragraphs,
%	list items and gtable cells and apply font faces and links.

wiki_faces(DOM0, ArgNames, DOM) :-
	structure_term(DOM0, Functor, Content0), !,
	wiki_faces_list(Content0, ArgNames, Content),
	structure_term(DOM, Functor, Content).
wiki_faces(Verb, _, Verb) :-
	verbatim_term(Verb), !.
wiki_faces(Content0, ArgNames, Content) :-
	assertion(is_list(Content0)),
	phrase(wiki_faces(Content, ArgNames), Content0).

wiki_faces_list([], _, []).
wiki_faces_list([H0|T0], Args, [H|T]) :-
	wiki_faces(H0, Args, H),
	wiki_faces_list(T0, Args, T).

structure_term(\tags(Tags), tags, [Tags]) :- !.
structure_term(\params(Params), params, [Params]) :- !.
structure_term(\param(Name,Descr), param(Name), [Descr]) :- !.
structure_term(\tag(Name,Value), tag(Name), [Value]) :- !.
structure_term(Term, Functor, Args) :-
	functor(Term, Functor, 1),
	structure_tag(Functor), !,
	Term =.. [Functor|Args].

structure_tag(p).
structure_tag(ul).
structure_tag(ol).
structure_tag(dl).
structure_tag(li).
structure_tag(dt).
structure_tag(dd).
structure_tag(table).
structure_tag(tr).
structure_tag(td).

%%	verbatim_term(?Term) is det
%
%	True if Term must be passes verbatim.

verbatim_term(pre(_)).

%%	wiki_face(-WithFaces, +ArgNames)// is det.

wiki_faces([], _) -->
	[].
wiki_faces([H|T], ArgNames) -->
	wiki_face(H, ArgNames),
	wiki_faces(T, ArgNames).


wiki_face(var(Word), ArgNames) -->
	[Word],
	{ string(Word),			% punctuation and blanks are atoms
	  member(Arg, ArgNames),
	  sub_atom(Arg, 0, _, 0, Word)	% match string to atom
	}, !.
wiki_face(b(Bold), ArgNames) -->
	[*], wiki_faces(Bold, ArgNames), [*], !.
wiki_face(i(Bold), ArgNames) -->
	['_'], wiki_faces(Bold, ArgNames), ['_'], !.
wiki_face(code(Bold), _) -->
	[=], wiki_faces(Bold, []), [=], !.
wiki_face(a([href=HREF], [Name, '/', ArityWord]), _) -->
	[ Name, '/', ArityWord ],
	{ catch(atom_number(ArityWord, Arity), _, fail),
	  Arity >= 0, Arity < 100, !,
	  format(string(HREF), '/predicate/~w/~w', [Name, Arity])
	}.
wiki_face(a([href=HREF], [Name, '//', ArityWord]), _) -->
	[ Name, '/', '/', ArityWord ],
	{ catch(atom_number(ArityWord, Arity), _, fail),
	  Arity >= 0, Arity < 100, !,
	  format(string(HREF), '/DCG/~w/~w', [Name, Arity])
	}.
wiki_face(FT, ArgNames) -->
	[T],
	{   atomic(T)
	->  FT = T
	;   wiki_faces(T, ArgNames, FT)
	}.

%%	tokenize_lines(+Lines:lines, -TokenLines) is det
%
%	Convert Indent-Codes into Indent-Tokens

tokenize_lines([], []).
tokenize_lines(Lines, [Pre|T]) :-
	verbatim(Lines, Pre, RestLines), !,
	tokenize_lines(RestLines, T).
tokenize_lines([I-H0|T0], [I-H|T]) :-
	phrase(tokens(H), H0),
	tokenize_lines(T0, T).


%%	tokens(-Tokens:list)// is det.
%
%	Create a list of tokens, where  is  token   is  either  a ' ' to
%	denote spaces, a string denoting a word   or  an atom denoting a
%	punctuation character.

tokens([H|T]) -->
	token(H), !,
	tokens(T).
tokens([]) -->
	[].

token(T) -->
	[C],
	(   { code_type(C, space) }
	->  ws,
	    { T = ' ' }
	;   { code_type(C, alnum) },
	    word(Rest),
	    { string_to_list(T, [C|Rest]) }
	;   { char_code(T, C) }
	).

word([C0|T]) -->
	[C0],  { code_type(C0, alnum); C0 == 0'_ }, !,	%'
	word(T).
word([]) -->
	[].


%%	verbatim(+Lines, -Pre, -RestLines) is det.
%
%	Extract a verbatim environment.  The  returned   Pre  is  of the
%	format  pre(String).  The  indentation  of  the  leading  ==  is
%	substracted from the indentation of the verbatim lines.
%
%	Verbatim environment is delimited as
%	
%	==
%		...,
%		verbatim(Lines, Pre, Rest)
%		...,
%	==

verbatim([Indent-"=="|Lines], pre(Pre), RestLines) :-
	verbatim_body(Lines, Indent, [10|PreCodes], [],
		      [Indent-"=="|RestLines]), !,
	string_to_list(Pre, PreCodes).

verbatim_body(Lines, _, PreT, PreT, Lines).
verbatim_body([I-L|Lines], Indent, [10|Pre], PreT, RestLines) :-
	PreI is Indent - I,
	pre_indent(PreI, Pre, PreT0),
	verbatim_line(L, PreT0, PreT1),
	verbatim_body(Lines, Indent, PreT1, PreT, RestLines).

pre_indent(Indent, Pre, PreT) :-
	Tabs is Indent // 8,
	Spaces is Indent mod 8,
	format(codes(Pre, PreT), '~*c~*c', [Tabs, 9, Spaces, 32]).

verbatim_line(Line, Pre, PreT) :-
	append(Line, PreT, Pre).


		 /*******************************
		 *	  CREATE LINES		*
		 *******************************/

%%	indented_lines(+Text:string, +Prefixes:list(codes), -Lines:list) is det.
%
%	Extract a list of lines  without   leading  blanks or characters
%	from Prefix from Text. Each line   is a term Indent-Codes, where
%	Indent specifies the line_position of the real text of the line.

indented_lines(Comment, Prefixes, Lines) :-
	string_to_list(Comment, List),
	phrase(split_lines(Prefixes, Lines), List).

split_lines(_, []) -->
	eos, !.
split_lines(Prefixes, [Indent-L1|Ls]) -->
	take_prefix(Prefixes, 0, Indent0),
	white_prefix(Indent0, Indent),
	take_line(L1),
	split_lines(Prefixes, Ls).


%%	take_prefix(+Prefixes:list(codes), +Indent0:int, -Indent:int)// is det.
%
%	Get the leading characters  from  the   input  and  compute  the
%	line-position at the end of the leading characters.

take_prefix(Prefixes, I0, I) -->
	{ member(Prefix, Prefixes) },
	string(Prefix), !,
	{ string_update_linepos(Prefix, I0, I) }.
take_prefix(_, I, I) -->
	[].

white_prefix(I0, I) -->
	[C],
	{  code_type(C, white), !,
	   update_linepos(C, I0, I1)
	},
	white_prefix(I1, I).
white_prefix(I, I) -->
	[].

string_update_linepos([], I, I).
string_update_linepos([H|T], I0, I) :-
	update_linepos(H, I0, I1),
	string_update_linepos(T, I1, I).

update_linepos(0'\t, I0, I) :- !,
	I is (I0\/7)+1.
update_linepos(0'\b, I0, I) :- !,
	I is max(0, I0-1).
update_linepos(0'\r, _, 0) :- !.
update_linepos(0'\n, _, 0) :- !.
update_linepos(_, I0, I) :-
	I is I0 + 1.

%%	take_line(-Line:codes)// is det.
%
%	Take  a  line  from  the  input.   Line  does  not  include  the
%	terminating \r or \n character(s), nor trailing whitespace.

take_line([]) -->
	"\r\n", !.			% DOS file
take_line([]) -->
	"\n", !.			% Unix file
take_line(Line) -->
	[H], { code_type(H, white) }, !,
	take_white(White, WT),
	(   peek_nl
	->  { Line = [] }
	;   { Line = [H|White] },
	    take_line(WT)
	).
take_line([H|T]) -->
	[H], !,
	take_line(T).
take_line([]) -->			% end of string
	[].

take_white([H|T0], T) -->
	[H],  { code_type(H, white) }, !,
	take_white(T0, T).
take_white(T, T) -->
	[].



		 /*******************************
		 *	       MISC		*
		 *******************************/

%%	strip_leading_par(+Dom0, -Dom) is det.
%
%	Remove the leading paragraph for  environments where a paragraph
%	is not required.

strip_leading_par([p(C)|T], L) :- !,
	append(C, T, L).
strip_leading_par(L, L).


		 /*******************************
		 *	     DCG BASICS		*
		 *******************************/

%%	eos// is det
%
%	Peek at end of input

eos([], []).

%%	ws// is det
%
%	Eagerly skip layout characters

ws -->
	[C], {code_type(C, space)}, !,
	ws.
ws -->
	[].

%%	peek_nl//
%
%	True if we are at the end of a line

peek_nl(L,L) :-
	L = [H|_],
	( H == 0'\n ; H == 0'\r ), !.


%%	string(-Tokens:list)// is nondet.
%
%	Defensively take tokens from the input.  Backtracking takes more
%	tokens.

string([]) --> [].
string([H|T]) --> [H], string(T).


