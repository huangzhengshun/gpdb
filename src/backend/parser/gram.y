%{

/*#define YYDEBUG 1*/
/*-------------------------------------------------------------------------
 *
 * gram.y
 *	  POSTGRES SQL YACC rules/actions
 *
 * Portions Copyright (c) 1996-2001, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  $Header: /cvsroot/pgsql/src/backend/parser/gram.y,v 2.295 2002/03/21 16:00:50 tgl Exp $
 *
 * HISTORY
 *	  AUTHOR			DATE			MAJOR EVENT
 *	  Andrew Yu			Sept, 1994		POSTQUEL to SQL conversion
 *	  Andrew Yu			Oct, 1994		lispy code conversion
 *
 * NOTES
 *	  CAPITALS are used to represent terminal symbols.
 *	  non-capitals are used to represent non-terminals.
 *	  SQL92-specific syntax is separated from plain SQL/Postgres syntax
 *	  to help isolate the non-extensible portions of the parser.
 *
 *	  In general, nothing in this file should initiate database accesses
 *	  nor depend on changeable state (such as SET variables).  If you do
 *	  database accesses, your code will fail when we have aborted the
 *	  current transaction and are just parsing commands to find the next
 *	  ROLLBACK or COMMIT.  If you make use of SET variables, then you
 *	  will do the wrong thing in multi-query strings like this:
 *			SET SQL_inheritance TO off; SELECT * FROM foo;
 *	  because the entire string is parsed by gram.y before the SET gets
 *	  executed.  Anything that depends on the database or changeable state
 *	  should be handled inside parse_analyze() so that it happens at the
 *	  right time not the wrong time.  The handling of SQL_inheritance is
 *	  a good example.
 *
 * WARNINGS
 *	  If you use a list, make sure the datum is a node so that the printing
 *	  routines work.
 *
 *	  Sometimes we assign constants to makeStrings. Make sure we don't free
 *	  those.
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <ctype.h>

#include "access/htup.h"
#include "catalog/index.h"
#include "catalog/pg_type.h"
#include "nodes/params.h"
#include "nodes/parsenodes.h"
#include "parser/gramparse.h"
#include "storage/lmgr.h"
#include "utils/numeric.h"
#include "utils/datetime.h"

#ifdef MULTIBYTE
#include "mb/pg_wchar.h"
#else
#define GetStandardEncoding()	0		/* PG_SQL_ASCII */
#define GetStandardEncodingName()	"SQL_ASCII"
#endif

extern List *parsetree;			/* final parse result is delivered here */

static bool QueryIsRule = FALSE;
static Oid	*param_type_info;
static int	pfunc_num_args;


/*
 * If you need access to certain yacc-generated variables and find that
 * they're static by default, uncomment the next line.  (this is not a
 * problem, yet.)
 */
/*#define __YYSCLASS*/

static Node *makeA_Expr(int oper, char *opname, Node *lexpr, Node *rexpr);
static Node *makeTypeCast(Node *arg, TypeName *typename);
static Node *makeStringConst(char *str, TypeName *typename);
static Node *makeFloatConst(char *str);
static Node *makeRowExpr(char *opr, List *largs, List *rargs);
static SelectStmt *findLeftmostSelect(SelectStmt *node);
static void insertSelectOptions(SelectStmt *stmt,
								List *sortClause, List *forUpdate,
								Node *limitOffset, Node *limitCount);
static Node *makeSetOp(SetOperation op, bool all, Node *larg, Node *rarg);
static Node *doNegate(Node *n);
static void doNegateFloat(Value *v);

#define MASK(b) (1 << (b))

%}


%union
{
	int					ival;
	char				chr;
	char				*str;
	bool				boolean;
	JoinType			jtype;
	List				*list;
	Node				*node;
	Value				*value;
	ColumnRef			*columnref;

	TypeName			*typnam;
	DefElem				*defelt;
	SortGroupBy			*sortgroupby;
	JoinExpr			*jexpr;
	IndexElem			*ielem;
	Alias				*alias;
	RangeVar			*range;
	A_Indices			*aind;
	ResTarget			*target;
	PrivTarget			*privtarget;

	VersionStmt			*vstmt;
	DefineStmt			*dstmt;
	RuleStmt			*rstmt;
	InsertStmt			*istmt;
}

%type <node>	stmt, schema_stmt,
		AlterDatabaseSetStmt, AlterGroupStmt, AlterSchemaStmt, AlterTableStmt,
		AlterUserStmt, AlterUserSetStmt, AnalyzeStmt,
		ClosePortalStmt, ClusterStmt, CommentStmt, ConstraintsSetStmt,
		CopyStmt, CreateAsStmt, CreateDomainStmt, CreateGroupStmt, CreatePLangStmt,
		CreateSchemaStmt, CreateSeqStmt, CreateStmt, CreateTrigStmt,
		CreateUserStmt, CreatedbStmt, CursorStmt, DefineStmt, DeleteStmt,
		DropGroupStmt, DropPLangStmt, DropSchemaStmt, DropStmt, DropTrigStmt,
		DropUserStmt, DropdbStmt, ExplainStmt, FetchStmt,
		GrantStmt, IndexStmt, InsertStmt, ListenStmt, LoadStmt, LockStmt,
		NotifyStmt, OptimizableStmt, ProcedureStmt, ReindexStmt,
		RemoveAggrStmt, RemoveFuncStmt, RemoveOperStmt,
		RenameStmt, RevokeStmt, RuleActionStmt, RuleActionStmtOrEmpty,
		RuleStmt, SelectStmt, TransactionStmt, TruncateStmt,
		UnlistenStmt, UpdateStmt, VacuumStmt, VariableResetStmt,
		VariableSetStmt, VariableShowStmt, ViewStmt, CheckPointStmt

%type <node>	select_no_parens, select_with_parens, select_clause,
				simple_select

%type <node>    alter_column_default
%type <ival>    drop_behavior, opt_drop_behavior

%type <list>	createdb_opt_list, createdb_opt_item
%type <boolean>	opt_equal

%type <ival>	opt_lock, lock_type
%type <boolean>	opt_force, opt_or_replace

%type <list>	user_list

%type <list>	OptGroupList
%type <defelt>	OptGroupElem

%type <list>	OptUserList
%type <defelt>	OptUserElem

%type <str>		OptSchemaName
%type <list>	OptSchemaEltList

%type <boolean>	TriggerActionTime, TriggerForSpec, opt_trusted, opt_procedural
%type <str>		opt_lancompiler

%type <str>		TriggerEvents
%type <value>	TriggerFuncArg

%type <str>		relation_name, copy_file_name, copy_delimiter, copy_null,
		database_name, access_method_clause, access_method, attr_name,
		class, index_name, name, func_name, file_name

%type <range>	qualified_name, OptConstrFromTable

%type <str>		opt_id,
		all_Op, MathOp, opt_name,
		OptUseOp, opt_class, SpecialRuleRelation

%type <str>		opt_level, opt_encoding
%type <node>	grantee
%type <list>	grantee_list
%type <ival>	privilege
%type <list>	privileges, privilege_list
%type <privtarget> privilege_target
%type <node>	function_with_argtypes
%type <list>	function_with_argtypes_list
%type <chr>	TriggerOneEvent

%type <list>	stmtblock, stmtmulti,
		OptTableElementList, OptInherit, definition, opt_distinct,
		opt_with, func_args, func_args_list, func_as,
		oper_argtypes, RuleActionList, RuleActionMulti,
		opt_column_list, columnList, opt_name_list,
		sort_clause, sortby_list, index_params, index_list, name_list,
		from_clause, from_list, opt_array_bounds, qualified_name_list,
		expr_list, attrs, opt_attrs, target_list, update_target_list,
		insert_column_list,
		def_list, opt_indirection, group_clause, TriggerFuncArgs,
		select_limit, opt_select_limit

%type <range>	into_clause, OptTempTableName

%type <typnam>	func_arg, func_return, func_type, aggr_argtype

%type <boolean>	opt_arg, TriggerForOpt, TriggerForType, OptTemp, OptWithOids

%type <list>	for_update_clause, opt_for_update_clause, update_list
%type <boolean>	opt_all
%type <boolean>	opt_table
%type <boolean>	opt_chain, opt_trans

%type <node>	join_outer, join_qual
%type <jtype>	join_type

%type <list>	extract_list, position_list
%type <list>	substr_list, trim_list
%type <ival>	opt_interval
%type <node>	substr_from, substr_for

%type <boolean>	opt_binary, opt_using, opt_instead, opt_cursor
%type <boolean>	opt_with_copy, index_opt_unique, opt_verbose, opt_full
%type <boolean>	opt_freeze, analyze_keyword

%type <ival>	copy_dirn, direction, reindex_type, drop_type,
		opt_column, event, comment_type

%type <ival>	fetch_how_many

%type <node>	select_limit_value, select_offset_value

%type <list>	OptSeqList
%type <defelt>	OptSeqElem

%type <istmt>	insert_rest

%type <node>	OptTableElement, ConstraintElem
%type <node>	columnDef
%type <defelt>	def_elem
%type <node>	def_arg, columnElem, where_clause, insert_column_item,
				a_expr, b_expr, c_expr, AexprConst,
				in_expr, having_clause
%type <list>	row_descriptor, row_list, in_expr_nodes
%type <node>	row_expr
%type <node>	case_expr, case_arg, when_clause, case_default
%type <boolean>	opt_empty_parentheses
%type <list>	when_clause_list
%type <ival>	sub_type
%type <list>	OptCreateAs, CreateAsList
%type <node>	CreateAsElement
%type <value>	NumericOnly, FloatOnly, IntegerOnly
%type <columnref>	columnref
%type <alias>	alias_clause
%type <sortgroupby>		sortby
%type <ielem>	index_elem, func_index
%type <node>	table_ref
%type <jexpr>	joined_table
%type <range>	relation_expr
%type <target>	target_el, update_target_el

%type <typnam>	Typename, SimpleTypename, ConstTypename
				GenericType, Numeric, Character, ConstDatetime, ConstInterval, Bit
%type <str>		character, bit
%type <str>		extract_arg
%type <str>		opt_charset, opt_collate
%type <str>		opt_float
%type <ival>	opt_numeric, opt_decimal
%type <boolean>	opt_varying, opt_timezone, opt_timezone_x

%type <ival>	Iconst
%type <str>		Sconst, comment_text
%type <str>		UserId, opt_boolean, var_value, ColId_or_Sconst
%type <str>		ColId, ColLabel, type_name, func_name_keyword
%type <str>		col_name_keyword, unreserved_keyword, reserved_keyword
%type <node>	zone_value

%type <node>	TableConstraint
%type <list>	ColQualList
%type <node>	ColConstraint, ColConstraintElem, ConstraintAttr
%type <ival>	key_actions, key_delete, key_update, key_reference
%type <str>		key_match
%type <ival>	ConstraintAttributeSpec, ConstraintDeferrabilitySpec,
				ConstraintTimeSpec

%type <list>	constraints_set_list
%type <boolean>	constraints_set_mode

%type <boolean> opt_as


/*
 * If you make any token changes, remember to:
 *		- use "yacc -d" and update parse.h
 *		- update the keyword table in parser/keywords.c
 */

/* Reserved word tokens
 * SQL92 syntax has many type-specific constructs.
 * So, go ahead and make these types reserved words,
 *  and call-out the syntax explicitly.
 * This gets annoying when trying to also retain Postgres' nice
 *  type-extensible features, but we don't really have a choice.
 * - thomas 1997-10-11
 * NOTE: don't forget to add new keywords to the appropriate one of
 * the reserved-or-not-so-reserved keyword lists, below.
 */

/* Keywords (in SQL92 reserved words) */
%token	ABSOLUTE, ACTION, ADD, ALL, ALTER, AND, ANY, AS, ASC, AT, AUTHORIZATION,
		BEGIN_TRANS, BETWEEN, BOTH, BY,
		CASCADE, CASE, CAST, CHAR, CHARACTER, CHECK, CLOSE, 
		COALESCE, COLLATE, COLUMN, COMMIT,
		CONSTRAINT, CONSTRAINTS, CREATE, CROSS, CURRENT_DATE,
		CURRENT_TIME, CURRENT_TIMESTAMP, CURRENT_USER, CURSOR,
		DAY_P, DEC, DECIMAL, DECLARE, DEFAULT, DELETE, DESC,
		DISTINCT, DOUBLE, DROP,
		ELSE, ENCRYPTED, END_TRANS, ESCAPE, EXCEPT, EXECUTE, EXISTS, EXTRACT,
		FALSE_P, FETCH, FLOAT, FOR, FOREIGN, FROM, FULL,
		GLOBAL, GRANT, GROUP, HAVING, HOUR_P,
		IN, INNER_P, INSENSITIVE, INSERT, INTERSECT, INTERVAL, INTO, IS,
		ISOLATION, JOIN, KEY, LANGUAGE, LEADING, LEFT, LEVEL, LIKE, LOCAL,
		MATCH, MINUTE_P, MONTH_P, NAMES,
		NATIONAL, NATURAL, NCHAR, NEXT, NO, NOT, NULLIF, NULL_P, NUMERIC,
		OF, OLD, ON, ONLY, OPTION, OR, ORDER, OUTER_P, OVERLAPS,
		PARTIAL, POSITION, PRECISION, PRIMARY, PRIOR, PRIVILEGES, PROCEDURE, PUBLIC,
		READ, REFERENCES, RELATIVE, REVOKE, RIGHT, ROLLBACK,
		SCHEMA, SCROLL, SECOND_P, SELECT, SESSION, SESSION_USER, SET, SOME, SUBSTRING,
		TABLE, TEMPORARY, THEN, TIME, TIMESTAMP,
		TO, TRAILING, TRANSACTION, TRIM, TRUE_P,
		UNENCRYPTED, UNION, UNIQUE, UNKNOWN, UPDATE, USAGE, USER, USING,
		VALUES, VARCHAR, VARYING, VIEW,
		WHEN, WHERE, WITH, WORK, YEAR_P, ZONE

/* Keywords (in SQL99 reserved words) */
%token	CHAIN, CHARACTERISTICS,
		DEFERRABLE, DEFERRED,
		IMMEDIATE, INITIALLY, INOUT,
		OFF, OUT,
		PATH_P, PENDANT,
		REPLACE, RESTRICT,
        TRIGGER,
		WITHOUT

/* Keywords (in SQL92 non-reserved words) */
%token	COMMITTED, SERIALIZABLE, TYPE_P, DOMAIN_P

/* Keywords for Postgres support (not in SQL92 reserved words)
 *
 * The CREATEDB and CREATEUSER tokens should go away
 * when some sort of pg_privileges relation is introduced.
 * - Todd A. Brandys 1998-01-01?
 */
%token	ABORT_TRANS, ACCESS, AFTER, AGGREGATE, ANALYSE, ANALYZE,
		BACKWARD, BEFORE, BINARY, BIT,
		CACHE, CHECKPOINT, CLUSTER, COMMENT, COPY, CREATEDB, CREATEUSER, CYCLE,
		DATABASE, DELIMITERS, DO,
		EACH, ENCODING, EXCLUSIVE, EXPLAIN,
		FORCE, FORWARD, FREEZE, FUNCTION, HANDLER,
		ILIKE, INCREMENT, INDEX, INHERITS, INSTEAD, ISNULL,
		LANCOMPILER, LIMIT, LISTEN, LOAD, LOCATION, LOCK_P,
		MAXVALUE, MINVALUE, MODE, MOVE,
		NEW, NOCREATEDB, NOCREATEUSER, NONE, NOTHING, NOTIFY, NOTNULL,
		OFFSET, OIDS, OPERATOR, OWNER, PASSWORD, PROCEDURAL,
		REINDEX, RENAME, RESET, RETURNS, ROW, RULE,
		SEQUENCE, SETOF, SHARE, SHOW, START, STATEMENT,
		STATISTICS, STDIN, STDOUT, STORAGE, SYSID,
		TEMP, TEMPLATE, TOAST, TRUNCATE, TRUSTED, 
		UNLISTEN, UNTIL, VACUUM, VALID, VERBOSE, VERSION

/* The grammar thinks these are keywords, but they are not in the keywords.c
 * list and so can never be entered directly.  The filter in parser.c
 * creates these tokens when required.
 */
%token			UNIONJOIN

/* Special keywords, not in the query language - see the "lex" file */
%token <str>	IDENT, FCONST, SCONST, BITCONST, Op
%token <ival>	ICONST, PARAM

/* these are not real. they are here so that they get generated as #define's*/
%token			OP

/* precedence: lowest to highest */
%left		UNION EXCEPT
%left		INTERSECT
%left		JOIN UNIONJOIN CROSS LEFT FULL RIGHT INNER_P NATURAL
%left		OR
%left		AND
%right		NOT
%right		'='
%nonassoc	'<' '>'
%nonassoc	LIKE ILIKE
%nonassoc	ESCAPE
%nonassoc	OVERLAPS
%nonassoc	BETWEEN
%nonassoc	IN
%left		POSTFIXOP		/* dummy for postfix Op rules */
%left		Op				/* multi-character ops and user-defined operators */
%nonassoc	NOTNULL
%nonassoc	ISNULL
%nonassoc	IS NULL_P TRUE_P FALSE_P UNKNOWN	/* sets precedence for IS NULL, etc */
%left		'+' '-'
%left		'*' '/' '%'
%left		'^'
/* Unary Operators */
%left		AT ZONE			/* sets precedence for AT TIME ZONE */
%right		UMINUS
%left		'.'
%left		'[' ']'
%left		'(' ')'
%left		TYPECAST
%%

/*
 *	Handle comment-only lines, and ;; SELECT * FROM pg_class ;;;
 *	psql already handles such cases, but other interfaces don't.
 *	bjm 1999/10/05
 */
stmtblock:  stmtmulti
				{ parsetree = $1; }
		;

/* the thrashing around here is to discard "empty" statements... */
stmtmulti:  stmtmulti ';' stmt
				{ if ($3 != (Node *)NULL)
					$$ = lappend($1, $3);
				  else
					$$ = $1;
				}
		| stmt
				{ if ($1 != (Node *)NULL)
					$$ = makeList1($1);
				  else
					$$ = NIL;
				}
		;

stmt : AlterDatabaseSetStmt
		| AlterGroupStmt
		| AlterSchemaStmt
		| AlterTableStmt
		| AlterUserStmt
		| AlterUserSetStmt
		| ClosePortalStmt
		| CopyStmt
		| CreateStmt
		| CreateAsStmt
		| CreateDomainStmt
		| CreateSchemaStmt
		| CreateGroupStmt
		| CreateSeqStmt
		| CreatePLangStmt
		| CreateTrigStmt
		| CreateUserStmt
		| ClusterStmt
		| DefineStmt
		| DropStmt		
		| DropSchemaStmt
		| TruncateStmt
		| CommentStmt
		| DropGroupStmt
		| DropPLangStmt
		| DropTrigStmt
		| DropUserStmt
		| ExplainStmt
		| FetchStmt
		| GrantStmt
		| IndexStmt
		| ListenStmt
		| UnlistenStmt
		| LockStmt
		| NotifyStmt
		| ProcedureStmt
		| ReindexStmt
		| RemoveAggrStmt
		| RemoveOperStmt
		| RemoveFuncStmt
		| RenameStmt
		| RevokeStmt
		| OptimizableStmt
		| RuleStmt
		| TransactionStmt
		| ViewStmt
		| LoadStmt
		| CreatedbStmt
		| DropdbStmt
		| VacuumStmt
		| AnalyzeStmt
		| VariableSetStmt
		| VariableShowStmt
		| VariableResetStmt
		| ConstraintsSetStmt
		| CheckPointStmt
		| /*EMPTY*/
			{ $$ = (Node *)NULL; }
		;

/*****************************************************************************
 *
 * Create a new Postgres DBMS user
 *
 *
 *****************************************************************************/

CreateUserStmt:  CREATE USER UserId OptUserList 
				  {
					CreateUserStmt *n = makeNode(CreateUserStmt);
					n->user = $3;
					n->options = $4;
					$$ = (Node *)n;
				  }
                 | CREATE USER UserId WITH OptUserList
                  {
					CreateUserStmt *n = makeNode(CreateUserStmt);
					n->user = $3;
					n->options = $5;
					$$ = (Node *)n;
                  }                   
		;

/*****************************************************************************
 *
 * Alter a postgresql DBMS user
 *
 *
 *****************************************************************************/

AlterUserStmt:  ALTER USER UserId OptUserList
				 {
					AlterUserStmt *n = makeNode(AlterUserStmt);
					n->user = $3;
					n->options = $4;
					$$ = (Node *)n;
				 }
			    | ALTER USER UserId WITH OptUserList
				 {
					AlterUserStmt *n = makeNode(AlterUserStmt);
					n->user = $3;
					n->options = $5;
					$$ = (Node *)n;
				 }
		;


AlterUserSetStmt: ALTER USER UserId VariableSetStmt
				{
					AlterUserSetStmt *n = makeNode(AlterUserSetStmt);
					n->user = $3;
					n->variable = ((VariableSetStmt *)$4)->name;
					n->value = ((VariableSetStmt *)$4)->args;
					$$ = (Node *)n;
				}
				| ALTER USER UserId VariableResetStmt
				{
					AlterUserSetStmt *n = makeNode(AlterUserSetStmt);
					n->user = $3;
					n->variable = ((VariableResetStmt *)$4)->name;
					n->value = NULL;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 * Drop a postgresql DBMS user
 *
 *
 *****************************************************************************/

DropUserStmt:  DROP USER user_list
				{
					DropUserStmt *n = makeNode(DropUserStmt);
					n->users = $3;
					$$ = (Node *)n;
				}
		;

/*
 * Options for CREATE USER and ALTER USER
 */
OptUserList: OptUserList OptUserElem		{ $$ = lappend($1, $2); }
			| /* EMPTY */					{ $$ = NIL; }
		;

OptUserElem:  PASSWORD Sconst
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "password";
				  $$->arg = (Node *)makeString($2);
				}
			  | ENCRYPTED PASSWORD Sconst
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "encryptedPassword";
				  $$->arg = (Node *)makeString($3);
				}
			  | UNENCRYPTED PASSWORD Sconst
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "unencryptedPassword";
				  $$->arg = (Node *)makeString($3);
				}
              | SYSID Iconst
				{
				  $$ = makeNode(DefElem);
				  $$->defname = "sysid";
				  $$->arg = (Node *)makeInteger($2);
				}
              | CREATEDB
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "createdb";
				  $$->arg = (Node *)makeInteger(TRUE);
				}
              | NOCREATEDB
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "createdb";
				  $$->arg = (Node *)makeInteger(FALSE);
				}
              | CREATEUSER
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "createuser";
				  $$->arg = (Node *)makeInteger(TRUE);
				}
              | NOCREATEUSER
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "createuser";
				  $$->arg = (Node *)makeInteger(FALSE);
				}
              | IN GROUP user_list
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "groupElts";
				  $$->arg = (Node *)$3;
				}
              | VALID UNTIL Sconst
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "validUntil";
				  $$->arg = (Node *)makeString($3);
				}
        ;

user_list:  user_list ',' UserId
				{
					$$ = lappend($1, makeString($3));
				}
			| UserId
				{
					$$ = makeList1(makeString($1));
				}
		;



/*****************************************************************************
 *
 * Create a postgresql group
 *
 *
 *****************************************************************************/

CreateGroupStmt:  CREATE GROUP UserId OptGroupList
				   {
					CreateGroupStmt *n = makeNode(CreateGroupStmt);
					n->name = $3;
					n->options = $4;
					$$ = (Node *)n;
				   }
			      | CREATE GROUP UserId WITH OptGroupList
				   {
					CreateGroupStmt *n = makeNode(CreateGroupStmt);
					n->name = $3;
					n->options = $5;
					$$ = (Node *)n;
				   }
		;

/*
 * Options for CREATE GROUP
 */
OptGroupList: OptGroupList OptGroupElem		{ $$ = lappend($1, $2); }
			| /* EMPTY */					{ $$ = NIL; }
		;

OptGroupElem:  USER user_list
                { 
				  $$ = makeNode(DefElem);
				  $$->defname = "userElts";
				  $$->arg = (Node *)$2;
				}
               | SYSID Iconst
				{
				  $$ = makeNode(DefElem);
				  $$->defname = "sysid";
				  $$->arg = (Node *)makeInteger($2);
				}
        ;


/*****************************************************************************
 *
 * Alter a postgresql group
 *
 *
 *****************************************************************************/

AlterGroupStmt:  ALTER GROUP UserId ADD USER user_list
				{
					AlterGroupStmt *n = makeNode(AlterGroupStmt);
					n->name = $3;
					n->action = +1;
					n->listUsers = $6;
					$$ = (Node *)n;
				}
			| ALTER GROUP UserId DROP USER user_list
				{
					AlterGroupStmt *n = makeNode(AlterGroupStmt);
					n->name = $3;
					n->action = -1;
					n->listUsers = $6;
					$$ = (Node *)n;
				}
			;


/*****************************************************************************
 *
 * Drop a postgresql group
 *
 *
 *****************************************************************************/

DropGroupStmt: DROP GROUP UserId
				{
					DropGroupStmt *n = makeNode(DropGroupStmt);
					n->name = $3;
					$$ = (Node *)n;
				}
			;


/*****************************************************************************
 *
 * Manipulate a schema
 *
 *
 *****************************************************************************/

CreateSchemaStmt:  CREATE SCHEMA OptSchemaName AUTHORIZATION UserId OptSchemaEltList
				{
					CreateSchemaStmt *n = makeNode(CreateSchemaStmt);
					/* One can omit the schema name or the authorization id... */
					if ($3 != NULL)
						n->schemaname = $3;
					else
						n->schemaname = $5;
					n->authid = $5;
					n->schemaElts = $6;
					$$ = (Node *)n;
				}
		| CREATE SCHEMA ColId OptSchemaEltList
				{
					CreateSchemaStmt *n = makeNode(CreateSchemaStmt);
					/* ...but not both */
					n->schemaname = $3;
					n->authid = NULL;
					n->schemaElts = $4;
					$$ = (Node *)n;
				}
		;

AlterSchemaStmt:  ALTER SCHEMA ColId
				{
					elog(ERROR, "ALTER SCHEMA not yet supported");
				}
		;

DropSchemaStmt:  DROP SCHEMA ColId
				{
					elog(ERROR, "DROP SCHEMA not yet supported");
				}
		;

OptSchemaName: ColId								{ $$ = $1; }
		| /* EMPTY */								{ $$ = NULL; }
		;

OptSchemaEltList: OptSchemaEltList schema_stmt		{ $$ = lappend($1, $2); }
		| /* EMPTY */								{ $$ = NIL; }
		;

/*
 *	schema_stmt are the ones that can show up inside a CREATE SCHEMA
 *	statement (in addition to by themselves).
 */
schema_stmt: CreateStmt
		| GrantStmt
		| ViewStmt
		;

/*****************************************************************************
 *
 * Set PG internal variable
 *	  SET name TO 'var_value'
 * Include SQL92 syntax (thomas 1997-10-22):
 *    SET TIME ZONE 'var_value'
 *
 *****************************************************************************/

VariableSetStmt:  SET ColId TO var_value
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name  = $2;
					if ($4 != NULL)
						n->args = makeList1(makeStringConst($4, NULL));
					$$ = (Node *) n;
				}
		| SET ColId '=' var_value
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name  = $2;
					if ($4 != NULL)
						n->args = makeList1(makeStringConst($4, NULL));
					$$ = (Node *) n;
				}
		| SET TIME ZONE zone_value
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name  = "timezone";
					if ($4 != NULL)
						n->args = makeList1($4);
					$$ = (Node *) n;
				}
		| SET TRANSACTION ISOLATION LEVEL opt_level
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name  = "XactIsoLevel";
					n->args = makeList1(makeStringConst($5, NULL));
					$$ = (Node *) n;
				}
        | SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL opt_level
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name  = "default_transaction_isolation";
					n->args = makeList1(makeStringConst($8, NULL));
					$$ = (Node *) n;
				}
		| SET NAMES opt_encoding
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name  = "client_encoding";
					if ($3 != NULL)
						n->args = makeList1(makeStringConst($3, NULL));
					$$ = (Node *) n;
				}
		| SET SESSION AUTHORIZATION ColId_or_Sconst
				{
					VariableSetStmt *n = makeNode(VariableSetStmt);
					n->name = "session_authorization";
					n->args = makeList1(makeStringConst($4, NULL));
					$$ = (Node *) n;
				}
		;

opt_level:  READ COMMITTED					{ $$ = "read committed"; }
		| SERIALIZABLE						{ $$ = "serializable"; }
		;

var_value:  opt_boolean						{ $$ = $1; }
		| SCONST							{ $$ = $1; }
		| ICONST
			{
				char	buf[64];
				sprintf(buf, "%d", $1);
				$$ = pstrdup(buf);
			}
		| '-' ICONST
			{
				char	buf[64];
				sprintf(buf, "%d", -($2));
				$$ = pstrdup(buf);
			}
		| FCONST							{ $$ = $1; }
		| '-' FCONST
			{
				char * s = palloc(strlen($2)+2);
				s[0] = '-';
				strcpy(s + 1, $2);
				$$ = s;
			}
		| name_list
			{
				List *n;
				int slen = 0;
				char *result;

				/* List of words? Then concatenate together */
				if ($1 == NIL)
					elog(ERROR, "SET must have at least one argument");

				foreach (n, $1)
				{
					Value *p = (Value *) lfirst(n);
					Assert(IsA(p, String));
					/* keep track of room for string and trailing comma */
					slen += (strlen(p->val.str) + 1);
				}
				result = palloc(slen + 1);
				*result = '\0';
				foreach (n, $1)
				{
					Value *p = (Value *) lfirst(n);
					strcat(result, p->val.str);
					strcat(result, ",");
				}
				/* remove the trailing comma from the last element */
				*(result+strlen(result)-1) = '\0';
				$$ = result;
			}
		| DEFAULT							{ $$ = NULL; }
		;

opt_boolean:  TRUE_P						{ $$ = "true"; }
		| FALSE_P							{ $$ = "false"; }
		| ON								{ $$ = "on"; }
		| OFF								{ $$ = "off"; }
		;

/* Timezone values can be:
 * - a string such as 'pst8pdt'
 * - an integer or floating point number
 * - a time interval per SQL99
 */
zone_value:  Sconst
			{
				$$ = makeStringConst($1, NULL);
			}
		| ConstInterval Sconst opt_interval
			{
				A_Const *n = (A_Const *) makeStringConst($2, $1);
				if ($3 != -1)
				{
					if (($3 & ~(MASK(HOUR) | MASK(MINUTE))) != 0)
						elog(ERROR, "Time zone interval must be HOUR or HOUR TO MINUTE");
					n->typename->typmod = ((($3 & 0x7FFF) << 16) | 0xFFFF);
				}
				$$ = (Node *)n;
			}
		| ConstInterval '(' Iconst ')' Sconst opt_interval
			{
				A_Const *n = (A_Const *) makeStringConst($5, $1);
				if ($6 != -1)
				{
					if (($6 & ~(MASK(HOUR) | MASK(MINUTE))) != 0)
						elog(ERROR, "Time zone interval must be HOUR or HOUR TO MINUTE");
					n->typename->typmod = ((($6 & 0x7FFF) << 16) | $3);
				}
				else
				{
					n->typename->typmod = ((0x7FFF << 16) | $3);
				}

				$$ = (Node *)n;
			}
		| FCONST
			{
				$$ = makeFloatConst($1);
			}
		| '-' FCONST
			{
				$$ = doNegate(makeFloatConst($2));
			}
		| ICONST
			{
				char buf[64];
				sprintf(buf, "%d", $1);
				$$ = makeFloatConst(pstrdup(buf));
			}
		| '-' ICONST
			{
				char buf[64];
				sprintf(buf, "%d", $2);
				$$ = doNegate(makeFloatConst(pstrdup(buf)));
			}
		| DEFAULT							{ $$ = NULL; }
		| LOCAL								{ $$ = NULL; }
		;

opt_encoding:  Sconst						{ $$ = $1; }
        | DEFAULT							{ $$ = NULL; }
        | /*EMPTY*/							{ $$ = NULL; }
        ;

ColId_or_Sconst: ColId						{ $$ = $1; }
		| SCONST							{ $$ = $1; }
		;


VariableShowStmt:  SHOW ColId
				{
					VariableShowStmt *n = makeNode(VariableShowStmt);
					n->name  = $2;
					$$ = (Node *) n;
				}
		| SHOW TIME ZONE
				{
					VariableShowStmt *n = makeNode(VariableShowStmt);
					n->name  = "timezone";
					$$ = (Node *) n;
				}
		| SHOW ALL
				{
					VariableShowStmt *n = makeNode(VariableShowStmt);
					n->name  = "all";
					$$ = (Node *) n;
				}
		| SHOW TRANSACTION ISOLATION LEVEL
				{
					VariableShowStmt *n = makeNode(VariableShowStmt);
					n->name  = "XactIsoLevel";
					$$ = (Node *) n;
				}
		;

VariableResetStmt:	RESET ColId
				{
					VariableResetStmt *n = makeNode(VariableResetStmt);
					n->name  = $2;
					$$ = (Node *) n;
				}
		| RESET TIME ZONE
				{
					VariableResetStmt *n = makeNode(VariableResetStmt);
					n->name  = "timezone";
					$$ = (Node *) n;
				}
		| RESET TRANSACTION ISOLATION LEVEL
				{
					VariableResetStmt *n = makeNode(VariableResetStmt);
					n->name  = "XactIsoLevel";
					$$ = (Node *) n;
				}
		| RESET ALL
				{
					VariableResetStmt *n = makeNode(VariableResetStmt);
					n->name  = "all";
					$$ = (Node *) n;
				}
		;


ConstraintsSetStmt:	SET CONSTRAINTS constraints_set_list constraints_set_mode
				{
					ConstraintsSetStmt *n = makeNode(ConstraintsSetStmt);
					n->constraints = $3;
					n->deferred    = $4;
					$$ = (Node *) n;
				}
		;

constraints_set_list:	ALL					{ $$ = NIL; }
		| name_list							{ $$ = $1; }
		;

constraints_set_mode:	DEFERRED			{ $$ = TRUE; }
		| IMMEDIATE							{ $$ = FALSE; }
		;


/*
 * Checkpoint statement
 */
CheckPointStmt: CHECKPOINT
				{
					CheckPointStmt *n = makeNode(CheckPointStmt);
					$$ = (Node *)n;
				}
			;

/*****************************************************************************
 *
 *	ALTER TABLE variations
 *
 *****************************************************************************/

AlterTableStmt:
/* ALTER TABLE <relation> ADD [COLUMN] <coldef> */
		ALTER TABLE relation_expr ADD opt_column columnDef
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'A';
					n->relation = $3;
					n->def = $6;
					$$ = (Node *)n;
				}
/* ALTER TABLE <relation> ALTER [COLUMN] <colname> {SET DEFAULT <expr>|DROP DEFAULT} */
		| ALTER TABLE relation_expr ALTER opt_column ColId alter_column_default
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'T';
					n->relation = $3;
					n->name = $6;
					n->def = $7;
					$$ = (Node *)n;
				}
/* ALTER TABLE <relation> ALTER [COLUMN] <colname> SET STATISTICS <Iconst> */
		| ALTER TABLE relation_expr ALTER opt_column ColId SET STATISTICS Iconst
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'S';
					n->relation = $3;
					n->name = $6;
					n->def = (Node *) makeInteger($9);
					$$ = (Node *)n;
				}
/* ALTER TABLE <relation> ALTER [COLUMN] <colname> SET STORAGE <storagemode> */
        | ALTER TABLE relation_expr ALTER opt_column ColId SET STORAGE ColId
                {
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'M';
					n->relation = $3;
					n->name = $6;
					n->def = (Node *) makeString($9);
					$$ = (Node *)n;
				}
/* ALTER TABLE <relation> DROP [COLUMN] <colname> {RESTRICT|CASCADE} */
		| ALTER TABLE relation_expr DROP opt_column ColId drop_behavior
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'D';
					n->relation = $3;
					n->name = $6;
					n->behavior = $7;
					$$ = (Node *)n;
				}
/* ALTER TABLE <relation> ADD CONSTRAINT ... */
		| ALTER TABLE relation_expr ADD TableConstraint
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'C';
					n->relation = $3;
					n->def = $5;
					$$ = (Node *)n;
				}
/* ALTER TABLE <relation> DROP CONSTRAINT <name> {RESTRICT|CASCADE} */
		| ALTER TABLE relation_expr DROP CONSTRAINT name drop_behavior
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'X';
					n->relation = $3;
					n->name = $6;
					n->behavior = $7;
					$$ = (Node *)n;
				}
/* ALTER TABLE <name> CREATE TOAST TABLE */
		| ALTER TABLE qualified_name CREATE TOAST TABLE
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'E';
					$3->inhOpt = INH_NO;
					n->relation = $3;
					$$ = (Node *)n;
				}
/* ALTER TABLE <name> OWNER TO UserId */
		| ALTER TABLE qualified_name OWNER TO UserId
				{
					AlterTableStmt *n = makeNode(AlterTableStmt);
					n->subtype = 'U';
					$3->inhOpt = INH_NO;
					n->relation = $3;
					n->name = $6;
					$$ = (Node *)n;
				}
		;

alter_column_default:
		SET DEFAULT a_expr
			{
				/* Treat SET DEFAULT NULL the same as DROP DEFAULT */
				if (exprIsNullConstant($3))
					$$ = NULL;
				else
					$$ = $3;
			}
		| DROP DEFAULT					{ $$ = NULL; }
        ;

drop_behavior: CASCADE					{ $$ = CASCADE; }
		| RESTRICT						{ $$ = RESTRICT; }
        ;

opt_drop_behavior: CASCADE				{ $$ = CASCADE; }
		| RESTRICT						{ $$ = RESTRICT; }
		| /* EMPTY */					{ $$ = RESTRICT; /* default */ }
		;



/*****************************************************************************
 *
 *		QUERY :
 *				close <optname>
 *
 *****************************************************************************/

ClosePortalStmt:  CLOSE opt_id
				{
					ClosePortalStmt *n = makeNode(ClosePortalStmt);
					n->portalname = $2;
					$$ = (Node *)n;
				}
		;

opt_id:  ColId									{ $$ = $1; }
		| /*EMPTY*/								{ $$ = NULL; }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				COPY [BINARY] <relname> FROM/TO
 *				[USING DELIMITERS <delimiter>]
 *
 *****************************************************************************/

CopyStmt:  COPY opt_binary qualified_name opt_with_copy copy_dirn copy_file_name copy_delimiter copy_null
				{
					CopyStmt *n = makeNode(CopyStmt);
					n->binary = $2;
					n->relation = $3;
					n->oids = $4;
					n->direction = $5;
					n->filename = $6;
					n->delimiter = $7;
					n->null_print = $8;
					$$ = (Node *)n;
				}
		;

copy_dirn:	TO
				{ $$ = TO; }
		| FROM
				{ $$ = FROM; }
		;

/*
 * copy_file_name NULL indicates stdio is used. Whether stdin or stdout is
 * used depends on the direction. (It really doesn't make sense to copy from
 * stdout. We silently correct the "typo".		 - AY 9/94
 */
copy_file_name:  Sconst							{ $$ = $1; }
		| STDIN									{ $$ = NULL; }
		| STDOUT								{ $$ = NULL; }
		;

opt_binary:  BINARY								{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_with_copy:	WITH OIDS						{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

/*
 * the default copy delimiter is tab but the user can configure it
 */
copy_delimiter:  opt_using DELIMITERS Sconst	{ $$ = $3; }
		| /*EMPTY*/								{ $$ = "\t"; }
		;

opt_using:	USING								{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = TRUE; }
		;

copy_null:  WITH NULL_P AS Sconst				{ $$ = $4; }
		| /*EMPTY*/								{ $$ = "\\N"; }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				CREATE relname
 *
 *****************************************************************************/

CreateStmt:  CREATE OptTemp TABLE qualified_name '(' OptTableElementList ')' OptInherit OptWithOids
				{
					CreateStmt *n = makeNode(CreateStmt);
					$4->istemp = $2;
					n->relation = $4;
					n->tableElts = $6;
					n->inhRelations = $8;
					n->constraints = NIL;
					n->hasoids = $9;
					$$ = (Node *)n;
				}
		;

/*
 * Redundancy here is needed to avoid shift/reduce conflicts,
 * since TEMP is not a reserved word.  See also OptTempTableName.
 */
OptTemp:      TEMPORARY						{ $$ = TRUE; }
			| TEMP							{ $$ = TRUE; }
			| LOCAL TEMPORARY				{ $$ = TRUE; }
			| LOCAL TEMP					{ $$ = TRUE; }
			| GLOBAL TEMPORARY
				{
					elog(ERROR, "GLOBAL TEMPORARY TABLE is not currently supported");
					$$ = TRUE;
				}
			| GLOBAL TEMP
				{
					elog(ERROR, "GLOBAL TEMPORARY TABLE is not currently supported");
					$$ = TRUE;
				}
			| /*EMPTY*/						{ $$ = FALSE; }
		;

OptTableElementList:  OptTableElementList ',' OptTableElement
				{
					if ($3 != NULL)
						$$ = lappend($1, $3);
					else
						$$ = $1;
				}
			| OptTableElement
				{
					if ($1 != NULL)
						$$ = makeList1($1);
					else
						$$ = NIL;
				}
			| /*EMPTY*/							{ $$ = NIL; }
		;

OptTableElement:  columnDef						{ $$ = $1; }
			| TableConstraint					{ $$ = $1; }
		;

columnDef:  ColId Typename ColQualList opt_collate
				{
					ColumnDef *n = makeNode(ColumnDef);
					n->colname = $1;
					n->typename = $2;
					n->constraints = $3;

					if ($4 != NULL)
						elog(NOTICE,"CREATE TABLE / COLLATE %s not yet implemented"
							 "; clause ignored", $4);

					$$ = (Node *)n;
				}
		;

ColQualList:  ColQualList ColConstraint		{ $$ = lappend($1, $2); }
			| /*EMPTY*/						{ $$ = NIL; }
		;

ColConstraint:
		CONSTRAINT name ColConstraintElem
				{
					switch (nodeTag($3))
					{
						case T_Constraint:
							{
								Constraint *n = (Constraint *)$3;
								n->name = $2;
							}
							break;
						case T_FkConstraint:
							{
								FkConstraint *n = (FkConstraint *)$3;
								n->constr_name = $2;
							}
							break;
						default:
							break;
					}
					$$ = $3;
				}
		| ColConstraintElem
				{ $$ = $1; }
		| ConstraintAttr
				{ $$ = $1; }
		;

/* DEFAULT NULL is already the default for Postgres.
 * But define it here and carry it forward into the system
 * to make it explicit.
 * - thomas 1998-09-13
 *
 * WITH NULL and NULL are not SQL92-standard syntax elements,
 * so leave them out. Use DEFAULT NULL to explicitly indicate
 * that a column may have that value. WITH NULL leads to
 * shift/reduce conflicts with WITH TIME ZONE anyway.
 * - thomas 1999-01-08
 *
 * DEFAULT expression must be b_expr not a_expr to prevent shift/reduce
 * conflict on NOT (since NOT might start a subsequent NOT NULL constraint,
 * or be part of a_expr NOT LIKE or similar constructs).
 */
ColConstraintElem:
			  NOT NULL_P
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_NOTNULL;
					n->name = NULL;
					n->raw_expr = NULL;
					n->cooked_expr = NULL;
					n->keys = NULL;
					$$ = (Node *)n;
				}
			| NULL_P
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_NULL;
					n->name = NULL;
					n->raw_expr = NULL;
					n->cooked_expr = NULL;
					n->keys = NULL;
					$$ = (Node *)n;
				}
			| UNIQUE
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_UNIQUE;
					n->name = NULL;
					n->raw_expr = NULL;
					n->cooked_expr = NULL;
					n->keys = NULL;
					$$ = (Node *)n;
				}
			| PRIMARY KEY
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_PRIMARY;
					n->name = NULL;
					n->raw_expr = NULL;
					n->cooked_expr = NULL;
					n->keys = NULL;
					$$ = (Node *)n;
				}
			| CHECK '(' a_expr ')'
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_CHECK;
					n->name = NULL;
					n->raw_expr = $3;
					n->cooked_expr = NULL;
					n->keys = NULL;
					$$ = (Node *)n;
				}
			| DEFAULT b_expr
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_DEFAULT;
					n->name = NULL;
					if (exprIsNullConstant($2))
					{
						/* DEFAULT NULL should be reported as empty expr */
						n->raw_expr = NULL;
					}
					else
					{
						n->raw_expr = $2;
					}
					n->cooked_expr = NULL;
					n->keys = NULL;
					$$ = (Node *)n;
				}
			| REFERENCES qualified_name opt_column_list key_match key_actions 
				{
					FkConstraint *n = makeNode(FkConstraint);
					n->constr_name		= NULL;
					n->pktable			= $2;
					n->fk_attrs			= NIL;
					n->pk_attrs			= $3;
					n->match_type		= $4;
					n->actions			= $5;
					n->deferrable		= FALSE;
					n->initdeferred		= FALSE;
					$$ = (Node *)n;
				}
		;

/*
 * ConstraintAttr represents constraint attributes, which we parse as if
 * they were independent constraint clauses, in order to avoid shift/reduce
 * conflicts (since NOT might start either an independent NOT NULL clause
 * or an attribute).  analyze.c is responsible for attaching the attribute
 * information to the preceding "real" constraint node, and for complaining
 * if attribute clauses appear in the wrong place or wrong combinations.
 *
 * See also ConstraintAttributeSpec, which can be used in places where
 * there is no parsing conflict.
 */
ConstraintAttr: DEFERRABLE
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_ATTR_DEFERRABLE;
					$$ = (Node *)n;
				}
			| NOT DEFERRABLE
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_ATTR_NOT_DEFERRABLE;
					$$ = (Node *)n;
				}
			| INITIALLY DEFERRED
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_ATTR_DEFERRED;
					$$ = (Node *)n;
				}
			| INITIALLY IMMEDIATE
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_ATTR_IMMEDIATE;
					$$ = (Node *)n;
				}
		;


/* ConstraintElem specifies constraint syntax which is not embedded into
 *  a column definition. ColConstraintElem specifies the embedded form.
 * - thomas 1997-12-03
 */
TableConstraint:  CONSTRAINT name ConstraintElem
				{
					switch (nodeTag($3))
					{
						case T_Constraint:
							{
								Constraint *n = (Constraint *)$3;
								n->name = $2;
							}
							break;
						case T_FkConstraint:
							{
								FkConstraint *n = (FkConstraint *)$3;
								n->constr_name = $2;
							}
							break;
						default:
							break;
					}
					$$ = $3;
				}
		| ConstraintElem
				{ $$ = $1; }
		;

ConstraintElem:  CHECK '(' a_expr ')'
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_CHECK;
					n->name = NULL;
					n->raw_expr = $3;
					n->cooked_expr = NULL;
					$$ = (Node *)n;
				}
		| UNIQUE '(' columnList ')'
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_UNIQUE;
					n->name = NULL;
					n->raw_expr = NULL;
					n->cooked_expr = NULL;
					n->keys = $3;
					$$ = (Node *)n;
				}
		| PRIMARY KEY '(' columnList ')'
				{
					Constraint *n = makeNode(Constraint);
					n->contype = CONSTR_PRIMARY;
					n->name = NULL;
					n->raw_expr = NULL;
					n->cooked_expr = NULL;
					n->keys = $4;
					$$ = (Node *)n;
				}
		| FOREIGN KEY '(' columnList ')' REFERENCES qualified_name opt_column_list
				key_match key_actions ConstraintAttributeSpec
				{
					FkConstraint *n = makeNode(FkConstraint);
					n->constr_name		= NULL;
					n->pktable			= $7;
					n->fk_attrs			= $4;
					n->pk_attrs			= $8;
					n->match_type		= $9;
					n->actions			= $10;
					n->deferrable		= ($11 & 1) != 0;
					n->initdeferred		= ($11 & 2) != 0;
					$$ = (Node *)n;
				}
		;

opt_column_list:  '(' columnList ')'			{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NIL; }
		;

columnList:  columnList ',' columnElem
				{ $$ = lappend($1, $3); }
		| columnElem
				{ $$ = makeList1($1); }
		;

columnElem:  ColId
				{
					Ident *id = makeNode(Ident);
					id->name = $1;
					$$ = (Node *)id;
				}
		;

key_match:  MATCH FULL
			{
				$$ = "FULL";
			}
		| MATCH PARTIAL
			{
				elog(ERROR, "FOREIGN KEY/MATCH PARTIAL not yet implemented");
				$$ = "PARTIAL";
			}
		| /*EMPTY*/
			{
				$$ = "UNSPECIFIED";
			}
		;

key_actions:  key_delete				{ $$ = $1; }
		| key_update					{ $$ = $1; }
		| key_delete key_update			{ $$ = $1 | $2; }
		| key_update key_delete			{ $$ = $1 | $2; }
		| /*EMPTY*/						{ $$ = 0; }
		;

key_delete:  ON DELETE key_reference	{ $$ = $3 << FKCONSTR_ON_DELETE_SHIFT; }
		;

key_update:  ON UPDATE key_reference	{ $$ = $3 << FKCONSTR_ON_UPDATE_SHIFT; }
		;

key_reference:  NO ACTION				{ $$ = FKCONSTR_ON_KEY_NOACTION; }
		| RESTRICT						{ $$ = FKCONSTR_ON_KEY_RESTRICT; }
		| CASCADE						{ $$ = FKCONSTR_ON_KEY_CASCADE; }
		| SET NULL_P					{ $$ = FKCONSTR_ON_KEY_SETNULL; }
		| SET DEFAULT					{ $$ = FKCONSTR_ON_KEY_SETDEFAULT; }
		;

OptInherit:  INHERITS '(' qualified_name_list ')'	{ $$ = $3; }
		| /*EMPTY*/									{ $$ = NIL; }
		;

OptWithOids:  WITH OIDS						{ $$ = TRUE; }
			| WITHOUT OIDS					{ $$ = FALSE; }
			| /*EMPTY*/						{ $$ = TRUE; }
		;


/*
 * Note: CREATE TABLE ... AS SELECT ... is just another spelling for
 * SELECT ... INTO.
 */

CreateAsStmt:  CREATE OptTemp TABLE qualified_name OptCreateAs AS SelectStmt
				{
					/*
					 * When the SelectStmt is a set-operation tree, we must
					 * stuff the INTO information into the leftmost component
					 * Select, because that's where analyze.c will expect
					 * to find it.  Similarly, the output column names must
					 * be attached to that Select's target list.
					 */
					SelectStmt *n = findLeftmostSelect((SelectStmt *) $7);
					if (n->into != NULL)
						elog(ERROR,"CREATE TABLE AS may not specify INTO");
					$4->istemp = $2;
					n->into = $4;
					n->intoColNames = $5;
					$$ = $7;
				}
		;

OptCreateAs:  '(' CreateAsList ')'				{ $$ = $2; }
			| /*EMPTY*/							{ $$ = NIL; }
		;

CreateAsList:  CreateAsList ',' CreateAsElement	{ $$ = lappend($1, $3); }
			| CreateAsElement					{ $$ = makeList1($1); }
		;

CreateAsElement:  ColId
				{
					ColumnDef *n = makeNode(ColumnDef);
					n->colname = $1;
					n->typename = NULL;
					n->raw_default = NULL;
					n->cooked_default = NULL;
					n->is_not_null = FALSE;
					n->constraints = NULL;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		QUERY :
 *				CREATE SEQUENCE seqname
 *
 *****************************************************************************/

CreateSeqStmt:  CREATE OptTemp SEQUENCE qualified_name OptSeqList
				{
					CreateSeqStmt *n = makeNode(CreateSeqStmt);
					$4->istemp = $2;
					n->sequence = $4;
					n->options = $5;
					$$ = (Node *)n;
				}
		;

OptSeqList:  OptSeqList OptSeqElem
				{ $$ = lappend($1, $2); }
			|	{ $$ = NIL; }
		;

OptSeqElem:  CACHE NumericOnly
				{
					$$ = makeNode(DefElem);
					$$->defname = "cache";
					$$->arg = (Node *)$2;
				}
			| CYCLE
				{
					$$ = makeNode(DefElem);
					$$->defname = "cycle";
					$$->arg = (Node *)NULL;
				}
			| INCREMENT NumericOnly
				{
					$$ = makeNode(DefElem);
					$$->defname = "increment";
					$$->arg = (Node *)$2;
				}
			| MAXVALUE NumericOnly
				{
					$$ = makeNode(DefElem);
					$$->defname = "maxvalue";
					$$->arg = (Node *)$2;
				}
			| MINVALUE NumericOnly
				{
					$$ = makeNode(DefElem);
					$$->defname = "minvalue";
					$$->arg = (Node *)$2;
				}
			| START NumericOnly
				{
					$$ = makeNode(DefElem);
					$$->defname = "start";
					$$->arg = (Node *)$2;
				}
		;

NumericOnly:  FloatOnly					{ $$ = $1; }
			| IntegerOnly				{ $$ = $1; }
		;

FloatOnly:  FCONST
				{
					$$ = makeFloat($1);
				}
			| '-' FCONST
				{
					$$ = makeFloat($2);
					doNegateFloat($$);
				}
		;

IntegerOnly:  Iconst
				{
					$$ = makeInteger($1);
				}
			| '-' Iconst
				{
					$$ = makeInteger($2);
					$$->val.ival = - $$->val.ival;
				}
		;

/*****************************************************************************
 *
 *		QUERIES :
 *				CREATE PROCEDURAL LANGUAGE ...
 *				DROP PROCEDURAL LANGUAGE ...
 *
 *****************************************************************************/

CreatePLangStmt:  CREATE opt_trusted opt_procedural LANGUAGE ColId_or_Sconst
			HANDLER func_name opt_lancompiler
			{
				CreatePLangStmt *n = makeNode(CreatePLangStmt);
				n->plname = $5;
				n->plhandler = $7;
				n->plcompiler = $8;
				n->pltrusted = $2;
				$$ = (Node *)n;
			}
		;

opt_trusted:  TRUSTED			{ $$ = TRUE; }
			| /*EMPTY*/			{ $$ = FALSE; }
		;

opt_lancompiler: LANCOMPILER Sconst { $$ = $2; }
			| /*EMPTY*/			{ $$ = ""; }
		;

DropPLangStmt:  DROP opt_procedural LANGUAGE ColId_or_Sconst
			{
				DropPLangStmt *n = makeNode(DropPLangStmt);
				n->plname = $4;
				$$ = (Node *)n;
			}
		;

opt_procedural: PROCEDURAL		{ $$ = TRUE; }
			| /*EMPTY*/			{ $$ = TRUE; }
		;
		
/*****************************************************************************
 *
 *		QUERIES :
 *				CREATE TRIGGER ...
 *				DROP TRIGGER ...
 *
 *****************************************************************************/

CreateTrigStmt:  CREATE TRIGGER name TriggerActionTime TriggerEvents ON
				qualified_name TriggerForSpec EXECUTE PROCEDURE
				name '(' TriggerFuncArgs ')'
				{
					CreateTrigStmt *n = makeNode(CreateTrigStmt);
					n->trigname = $3;
					n->relation = $7;
					n->funcname = $11;
					n->args = $13;
					n->before = $4;
					n->row = $8;
					memcpy (n->actions, $5, 4);
					n->lang = NULL;		/* unused */
					n->text = NULL;		/* unused */
					n->attr = NULL;		/* unused */
					n->when = NULL;		/* unused */

					n->isconstraint  = FALSE;
					n->deferrable    = FALSE;
					n->initdeferred  = FALSE;
					n->constrrel = NULL;
					$$ = (Node *)n;
				}
		| CREATE CONSTRAINT TRIGGER name AFTER TriggerEvents ON
				qualified_name OptConstrFromTable 
				ConstraintAttributeSpec
				FOR EACH ROW EXECUTE PROCEDURE name '(' TriggerFuncArgs ')'
				{
					CreateTrigStmt *n = makeNode(CreateTrigStmt);
					n->trigname = $4;
					n->relation = $8;
					n->funcname = $16;
					n->args = $18;
					n->before = FALSE;
					n->row = TRUE;
					memcpy (n->actions, $6, 4);
					n->lang = NULL;		/* unused */
					n->text = NULL;		/* unused */
					n->attr = NULL;		/* unused */
					n->when = NULL;		/* unused */

					n->isconstraint  = TRUE;
					n->deferrable = ($10 & 1) != 0;
					n->initdeferred = ($10 & 2) != 0;

					n->constrrel = $9;
					$$ = (Node *)n;
				}
		;

TriggerActionTime:  BEFORE						{ $$ = TRUE; }
			| AFTER								{ $$ = FALSE; }
		;

TriggerEvents:	TriggerOneEvent
				{
					char *e = palloc (4);
					e[0] = $1; e[1] = 0; $$ = e;
				}
			| TriggerOneEvent OR TriggerOneEvent
				{
					char *e = palloc (4);
					e[0] = $1; e[1] = $3; e[2] = 0; $$ = e;
				}
			| TriggerOneEvent OR TriggerOneEvent OR TriggerOneEvent
				{
					char *e = palloc (4);
					e[0] = $1; e[1] = $3; e[2] = $5; e[3] = 0;
					$$ = e;
				}
		;

TriggerOneEvent:  INSERT					{ $$ = 'i'; }
			| DELETE						{ $$ = 'd'; }
			| UPDATE						{ $$ = 'u'; }
		;

TriggerForSpec:  FOR TriggerForOpt TriggerForType
				{
					$$ = $3;
				}
		;

TriggerForOpt:  EACH						{ $$ = TRUE; }
			| /*EMPTY*/						{ $$ = FALSE; }
		;

TriggerForType:  ROW						{ $$ = TRUE; }
			| STATEMENT						{ $$ = FALSE; }
		;

TriggerFuncArgs:  TriggerFuncArg
				{ $$ = makeList1($1); }
			| TriggerFuncArgs ',' TriggerFuncArg
				{ $$ = lappend($1, $3); }
			| /*EMPTY*/
				{ $$ = NIL; }
		;

TriggerFuncArg:  ICONST
				{
					char buf[64];
					sprintf (buf, "%d", $1);
					$$ = makeString(pstrdup(buf));
				}
			| FCONST
				{
					$$ = makeString($1);
				}
			| Sconst
				{
					$$ = makeString($1);
				}
			| BITCONST
				{
					$$ = makeString($1);
				}
			| ColId
				{
					$$ = makeString($1);
				}
		;

OptConstrFromTable:			/* Empty */
				{
					$$ = NULL;
				}
		| FROM qualified_name
				{
					$$ = $2;
				}
		;

ConstraintAttributeSpec:  ConstraintDeferrabilitySpec
			{ $$ = $1; }
		| ConstraintDeferrabilitySpec ConstraintTimeSpec
			{
				if ($1 == 0 && $2 != 0)
					elog(ERROR, "INITIALLY DEFERRED constraint must be DEFERRABLE");
				$$ = $1 | $2;
			}
		| ConstraintTimeSpec
			{
				if ($1 != 0)
					$$ = 3;
				else
					$$ = 0;
			}
		| ConstraintTimeSpec ConstraintDeferrabilitySpec
			{
				if ($2 == 0 && $1 != 0)
					elog(ERROR, "INITIALLY DEFERRED constraint must be DEFERRABLE");
				$$ = $1 | $2;
			}
		| /* Empty */
			{ $$ = 0; }
		;

ConstraintDeferrabilitySpec: NOT DEFERRABLE
			{ $$ = 0; }
		| DEFERRABLE
			{ $$ = 1; }
		;

ConstraintTimeSpec: INITIALLY IMMEDIATE
			{ $$ = 0; }
		| INITIALLY DEFERRED
			{ $$ = 2; }
		;


DropTrigStmt:  DROP TRIGGER name ON qualified_name
				{
					DropTrigStmt *n = makeNode(DropTrigStmt);
					n->trigname = $3;
					n->relation = $5;
					$$ = (Node *) n;
				}
		;


/*****************************************************************************
 *
 *		QUERY :
 *				define (aggregate,operator,type)
 *
 *****************************************************************************/

DefineStmt:  CREATE AGGREGATE func_name definition
				{
					DefineStmt *n = makeNode(DefineStmt);
					n->defType = AGGREGATE;
					n->defname = $3;
					n->definition = $4;
					$$ = (Node *)n;
				}
		| CREATE OPERATOR all_Op definition
				{
					DefineStmt *n = makeNode(DefineStmt);
					n->defType = OPERATOR;
					n->defname = $3;
					n->definition = $4;
					$$ = (Node *)n;
				}
		| CREATE TYPE_P name definition
				{
					DefineStmt *n = makeNode(DefineStmt);
					n->defType = TYPE_P;
					n->defname = $3;
					n->definition = $4;
					$$ = (Node *)n;
				}
		;

definition:  '(' def_list ')'				{ $$ = $2; }
		;

def_list:  def_elem							{ $$ = makeList1($1); }
		| def_list ',' def_elem				{ $$ = lappend($1, $3); }
		;

def_elem:  ColLabel '=' def_arg
				{
					$$ = makeNode(DefElem);
					$$->defname = $1;
					$$->arg = (Node *)$3;
				}
		| ColLabel
				{
					$$ = makeNode(DefElem);
					$$->defname = $1;
					$$->arg = (Node *)NULL;
				}
		;

/* Note: any simple identifier will be returned as a type name! */
def_arg:  func_return  					{  $$ = (Node *)$1; }
		| all_Op						{  $$ = (Node *)makeString($1); }
		| NumericOnly					{  $$ = (Node *)$1; }
		| Sconst						{  $$ = (Node *)makeString($1); }
		;


/*****************************************************************************
 *
 *		QUERY:
 *
 *		DROP itemtype itemname [, itemname ...]
 *
 *****************************************************************************/

/* DropStmt needs to use qualified_name_list as many of the objects
 * are relations or other schema objects (names can be schema-qualified) */
 
DropStmt:  DROP drop_type qualified_name_list opt_drop_behavior
				{
					DropStmt *n = makeNode(DropStmt);
					n->removeType = $2;
					n->objects = $3;
					n->behavior = $4;
					$$ = (Node *)n;
				}
		;

drop_type: TABLE								{ $$ = DROP_TABLE; }
		| SEQUENCE								{ $$ = DROP_SEQUENCE; }
		| VIEW									{ $$ = DROP_VIEW; }
		| INDEX									{ $$ = DROP_INDEX; }
		| RULE									{ $$ = DROP_RULE; }
		| TYPE_P								{ $$ = DROP_TYPE; }
		| DOMAIN_P								{ $$ = DROP_DOMAIN; }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				truncate table relname
 *
 *****************************************************************************/

TruncateStmt:  TRUNCATE opt_table qualified_name
				{
					TruncateStmt *n = makeNode(TruncateStmt);
					n->relation = $3;
					$$ = (Node *)n;
				}
			;

/*****************************************************************************
 *
 *  The COMMENT ON statement can take different forms based upon the type of
 *  the object associated with the comment. The form of the statement is:
 *
 *  COMMENT ON [ [ DATABASE | DOMAIN | INDEX | RULE | SEQUENCE | TABLE | TYPE | VIEW ] 
 *               <objname> | AGGREGATE <aggname> (<aggtype>) | FUNCTION 
 *		 <funcname> (arg1, arg2, ...) | OPERATOR <op> 
 *		 (leftoperand_typ rightoperand_typ) | TRIGGER <triggername> ON
 *		 <relname> ] IS 'text'
 *
 *****************************************************************************/
 
CommentStmt:	COMMENT ON comment_type name IS comment_text
			{
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = $3;
				n->objname = $4;
				n->objproperty = NULL;
				n->objlist = NULL;
				n->comment = $6;
				$$ = (Node *) n;
			}
		| COMMENT ON COLUMN ColId '.' attr_name IS comment_text
			{
				/*
				 * We can't use qualified_name here as the '.' causes a shift/red; 
				 * with ColId we do not test for NEW and OLD as table names, but it is OK
				 * as they would fail anyway as COMMENT cannot appear in a RULE.
				 * ColumnRef is also innapropriate as we don't take subscripts
				 * or '*' and have a very precise number of elements (2 or 3)
				 * so we do it from scratch.
				 */
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = COLUMN;
				n->objschema = NULL;
				n->objname = $4;
				n->objproperty = $6;
				n->objlist = NULL;
				n->comment = $8;
				$$ = (Node *) n;
			}
		| COMMENT ON COLUMN ColId '.' ColId '.' attr_name IS comment_text
			{
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = COLUMN;
				n->objschema = $4;
				n->objname = $6;
				n->objproperty = $8;
				n->objlist = NULL;
				n->comment = $10;
				$$ = (Node *) n;
			}
		| COMMENT ON AGGREGATE name '(' aggr_argtype ')' IS comment_text
			{
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = AGGREGATE;
				n->objschema = NULL;
				n->objname = $4;
				n->objproperty = NULL;
				n->objlist = makeList1($6);
				n->comment = $9;
				$$ = (Node *) n;
			}
		| COMMENT ON AGGREGATE name aggr_argtype IS comment_text
			{
				/* Obsolete syntax, but must support for awhile */
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = AGGREGATE;
				n->objschema = NULL;
				n->objname = $4;
				n->objproperty = NULL;
				n->objlist = makeList1($5);
				n->comment = $7;
				$$ = (Node *) n;
			}
		| COMMENT ON FUNCTION func_name func_args IS comment_text
			{
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = FUNCTION;
				n->objschema = NULL;
				n->objname = $4;
				n->objproperty = NULL;
				n->objlist = $5;
				n->comment = $7;
				$$ = (Node *) n;
			}
		| COMMENT ON OPERATOR all_Op '(' oper_argtypes ')' IS comment_text
			{
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = OPERATOR;
				n->objschema = NULL;
				n->objname = $4;
				n->objproperty = NULL;
				n->objlist = $6;
				n->comment = $9;
				$$ = (Node *) n;
			}
		| COMMENT ON TRIGGER name ON qualified_name IS comment_text
			{
				CommentStmt *n = makeNode(CommentStmt);
				n->objtype = TRIGGER;
				/* NOTE: schemaname here refers to the table in objproperty */
				n->objschema = $6->schemaname;
				n->objname = $4;
				n->objproperty = $6->relname;
				n->objlist = NULL;
				n->comment = $8;
				$$ = (Node *) n;
			}
		;

comment_type:	DATABASE { $$ = DATABASE; }
		| INDEX { $$ = INDEX; }
		| RULE { $$ = RULE; }
		| SEQUENCE { $$ = SEQUENCE; }
		| TABLE { $$ = TABLE; }
		| DOMAIN_P { $$ = TYPE_P; }
		| TYPE_P { $$ = TYPE_P; }
		| VIEW { $$ = VIEW; }
		;		

comment_text:	Sconst { $$ = $1; }
		| NULL_P { $$ = NULL; }
		;
		
/*****************************************************************************
 *
 *		QUERY:
 *			fetch/move [forward | backward] [ # | all ] [ in <portalname> ]
 *			fetch [ forward | backward | absolute | relative ]
 *			      [ # | all | next | prior ] [ [ in | from ] <portalname> ]
 *
 *****************************************************************************/

FetchStmt:  FETCH direction fetch_how_many from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					if ($2 == RELATIVE)
					{
						if ($3 == 0)
							elog(ERROR,"FETCH / RELATIVE at current position is not supported");
						$2 = FORWARD;
					}
					if ($3 < 0)
					{
						$3 = -$3;
						$2 = (($2 == FORWARD)? BACKWARD: FORWARD);
					}
					n->direction = $2;
					n->howMany = $3;
					n->portalname = $5;
					n->ismove = FALSE;
					$$ = (Node *)n;
				}
		| FETCH fetch_how_many from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					if ($2 < 0)
					{
						n->howMany = -$2;
						n->direction = BACKWARD;
					}
					else
					{
						n->direction = FORWARD;
						n->howMany = $2;
					}
					n->portalname = $4;
					n->ismove = FALSE;
					$$ = (Node *)n;
				}
		| FETCH direction from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					if ($2 == RELATIVE)
					{
						$2 = FORWARD;
					}
					n->direction = $2;
					n->howMany = 1;
					n->portalname = $4;
					n->ismove = FALSE;
					$$ = (Node *)n;
				}
		| FETCH from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					n->direction = FORWARD;
					n->howMany = 1;
					n->portalname = $3;
					n->ismove = FALSE;
					$$ = (Node *)n;
				}
		| FETCH name
				{
					FetchStmt *n = makeNode(FetchStmt);
					n->direction = FORWARD;
					n->howMany = 1;
					n->portalname = $2;
					n->ismove = FALSE;
					$$ = (Node *)n;
				}

		| MOVE direction fetch_how_many from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					if ($3 < 0)
					{
						$3 = -$3;
						$2 = (($2 == FORWARD)? BACKWARD: FORWARD);
					}
					n->direction = $2;
					n->howMany = $3;
					n->portalname = $5;
					n->ismove = TRUE;
					$$ = (Node *)n;
				}
		| MOVE fetch_how_many from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					if ($2 < 0)
					{
						n->howMany = -$2;
						n->direction = BACKWARD;
					}
					else
					{
						n->direction = FORWARD;
						n->howMany = $2;
					}
					n->portalname = $4;
					n->ismove = TRUE;
					$$ = (Node *)n;
				}
		| MOVE direction from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					n->direction = $2;
					n->howMany = 1;
					n->portalname = $4;
					n->ismove = TRUE;
					$$ = (Node *)n;
				}
		|	MOVE from_in name
				{
					FetchStmt *n = makeNode(FetchStmt);
					n->direction = FORWARD;
					n->howMany = 1;
					n->portalname = $3;
					n->ismove = TRUE;
					$$ = (Node *)n;
				}
		| MOVE name
				{
					FetchStmt *n = makeNode(FetchStmt);
					n->direction = FORWARD;
					n->howMany = 1;
					n->portalname = $2;
					n->ismove = TRUE;
					$$ = (Node *)n;
				}
		;

direction:	FORWARD					{ $$ = FORWARD; }
		| BACKWARD						{ $$ = BACKWARD; }
		| RELATIVE						{ $$ = RELATIVE; }
		| ABSOLUTE
			{
				elog(NOTICE,"FETCH / ABSOLUTE not supported, using RELATIVE");
				$$ = RELATIVE;
			}
		;

fetch_how_many:  Iconst					{ $$ = $1; }
		| '-' Iconst					{ $$ = - $2; }
		| ALL							{ $$ = 0; /* 0 means fetch all tuples*/ }
		| NEXT							{ $$ = 1; }
		| PRIOR							{ $$ = -1; }
		;

from_in:  IN 
	| FROM
	;


/*****************************************************************************
 *
 * GRANT and REVOKE statements
 *
 *****************************************************************************/

GrantStmt:  GRANT privileges ON privilege_target TO grantee_list opt_grant_grant_option
				{
					GrantStmt *n = makeNode(GrantStmt);
					n->is_grant = true;
					n->privileges = $2;
					n->objtype = ($4)->objtype;
					n->objects = ($4)->objs;
					n->grantees = $6;
					$$ = (Node*)n;
				}
		;

RevokeStmt:  REVOKE opt_revoke_grant_option privileges ON privilege_target FROM grantee_list
				{
					GrantStmt *n = makeNode(GrantStmt);
					n->is_grant = false;
					n->privileges = $3;
					n->objtype = ($5)->objtype;
					n->objects = ($5)->objs;
					n->grantees = $7;
					$$ = (Node *)n;
				}
		;


/* either ALL [PRIVILEGES] or a list of individual privileges */
privileges: privilege_list { $$ = $1; }
		| ALL { $$ = makeListi1(ALL); }
		| ALL PRIVILEGES { $$ = makeListi1(ALL); }
		;

privilege_list: privilege { $$ = makeListi1($1); }
		| privilege_list ',' privilege { $$ = lappendi($1, $3); }
		;

/* Not all of these privilege types apply to all objects, but that
   gets sorted out later. */
privilege: SELECT    { $$ = SELECT; }
		| INSERT     { $$ = INSERT; }
		| UPDATE     { $$ = UPDATE; }
		| DELETE     { $$ = DELETE; }
		| RULE       { $$ = RULE; }
		| REFERENCES { $$ = REFERENCES; }
		| TRIGGER    { $$ = TRIGGER; }
		| EXECUTE    { $$ = EXECUTE; }
		| USAGE      { $$ = USAGE; }
		;


/* Don't bother trying to fold the first two rules into one using
   opt_table.  You're going to get conflicts. */
privilege_target: qualified_name_list
				{
					PrivTarget *n = makeNode(PrivTarget);
					n->objtype = TABLE;
					n->objs = $1;
					$$ = n;
				}
			| TABLE qualified_name_list
				{
					PrivTarget *n = makeNode(PrivTarget);
					n->objtype = TABLE;
					n->objs = $2;
					$$ = n;
				}
			| FUNCTION function_with_argtypes_list
				{
					PrivTarget *n = makeNode(PrivTarget);
					n->objtype = FUNCTION;
					n->objs = $2;
					$$ = n;
				}
			| LANGUAGE name_list
				{
					PrivTarget *n = makeNode(PrivTarget);
					n->objtype = LANGUAGE;
					n->objs = $2;
					$$ = n;
				}
		;


grantee_list: grantee					{ $$ = makeList1($1); }
		| grantee_list ',' grantee		{ $$ = lappend($1, $3); }
		;

grantee:  PUBLIC
				{
					PrivGrantee *n = makeNode(PrivGrantee);
					n->username = NULL;
					n->groupname = NULL;
					$$ = (Node *)n;
				}
		| GROUP ColId
				{
					PrivGrantee *n = makeNode(PrivGrantee);
					n->username = NULL;
					n->groupname = $2;
					$$ = (Node *)n;
				}
		| ColId
				{
					PrivGrantee *n = makeNode(PrivGrantee);
					n->username = $1;
					n->groupname = NULL;
					$$ = (Node *)n;
				}
		;


opt_grant_grant_option: WITH GRANT OPTION
				{
					elog(ERROR, "grant options are not implemented");
				}
		| /*EMPTY*/
		;

opt_revoke_grant_option: GRANT OPTION FOR
				{
					elog(ERROR, "grant options are not implemented");
				}
		| /*EMPTY*/
		;


function_with_argtypes_list: function_with_argtypes
				{ $$ = makeList1($1); }
		| function_with_argtypes_list ',' function_with_argtypes
				{ $$ = lappend($1, $3); }
		;

function_with_argtypes: func_name func_args
				{
					FuncWithArgs *n = makeNode(FuncWithArgs);
					n->funcname = $1;
					n->funcargs = $2;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		QUERY:
 *				create index <indexname> on <relname>
 *				  [ using <access> ] "(" (<col> with <op>)+ ")"
 *				  [ where <predicate> ]
 *
 *****************************************************************************/

IndexStmt:	CREATE index_opt_unique INDEX index_name ON qualified_name
			access_method_clause '(' index_params ')' where_clause
				{
					IndexStmt *n = makeNode(IndexStmt);
					n->unique = $2;
					n->idxname = $4;
					n->relation = $6;
					n->accessMethod = $7;
					n->indexParams = $9;
					n->whereClause = $11;
					$$ = (Node *)n;
				}
		;

index_opt_unique:  UNIQUE						{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

access_method_clause:  USING access_method		{ $$ = $2; }
		/* If btree changes as our default, update pg_get_indexdef() */
		| /*EMPTY*/								{ $$ = DEFAULT_INDEX_TYPE; }
		;

index_params:  index_list						{ $$ = $1; }
		| func_index							{ $$ = makeList1($1); }
		;

index_list:  index_list ',' index_elem			{ $$ = lappend($1, $3); }
		| index_elem							{ $$ = makeList1($1); }
		;

func_index:  func_name '(' name_list ')' opt_class
				{
					$$ = makeNode(IndexElem);
					$$->name = $1;
					$$->args = $3;
					$$->class = $5;
				}
		  ;

index_elem:  attr_name opt_class
				{
					$$ = makeNode(IndexElem);
					$$->name = $1;
					$$->args = NIL;
					$$->class = $2;
				}
		;

opt_class:  class
				{
					/*
					 * Release 7.0 removed network_ops, timespan_ops, and
					 * datetime_ops, so we suppress it from being passed to
					 * the parser so the default *_ops is used.  This can be
					 * removed in some later release.  bjm 2000/02/07
					 *
					 * Release 7.1 removes lztext_ops, so suppress that too
					 * for a while.  tgl 2000/07/30
					 *
					 * Release 7.2 renames timestamp_ops to timestamptz_ops,
					 * so suppress that too for awhile.  I'm starting to
					 * think we need a better approach.  tgl 2000/10/01
					 */
					if (strcmp($1, "network_ops") != 0 &&
						strcmp($1, "timespan_ops") != 0 &&
						strcmp($1, "datetime_ops") != 0 &&
						strcmp($1, "lztext_ops") != 0 &&
						strcmp($1, "timestamp_ops") != 0)
						$$ = $1;
					else
						$$ = NULL;
				}
		| USING class							{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NULL; }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				execute recipe <recipeName>
 *
 *****************************************************************************/

/* NOT USED
RecipeStmt:  EXECUTE RECIPE recipe_name
				{
					RecipeStmt *n = makeNode(RecipeStmt);
					n->recipeName = $3;
					$$ = (Node *)n;
				}
		;
*/

/*****************************************************************************
 *
 *		QUERY:
 *				create [or replace] function <fname>
 *						[(<type-1> { , <type-n>})]
 *						returns <type-r>
 *						as <filename or code in language as appropriate>
 *						language <lang> [with parameters]
 *
 *****************************************************************************/

ProcedureStmt:	CREATE opt_or_replace FUNCTION func_name func_args
			 RETURNS func_return AS func_as LANGUAGE ColId_or_Sconst opt_with
				{
					ProcedureStmt *n = makeNode(ProcedureStmt);
					n->replace = $2;
					n->funcname = $4;
					n->argTypes = $5;
					n->returnType = (Node *) $7;
					n->withClause = $12;
					n->as = $9;
					n->language = $11;
					$$ = (Node *)n;
				};

opt_or_replace:  OR REPLACE						{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_with:  WITH definition						{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NIL; }
		;

func_args:  '(' func_args_list ')'				{ $$ = $2; }
		| '(' ')'								{ $$ = NIL; }
		;

func_args_list:  func_arg
				{	$$ = makeList1($1); }
		| func_args_list ',' func_arg
				{	$$ = lappend($1, $3); }
		;

func_arg:  opt_arg func_type
				{
					/* We can catch over-specified arguments here if we want to,
					 * but for now better to silently swallow typmod, etc.
					 * - thomas 2000-03-22
					 */
					$$ = $2;
				}
		| func_type
				{
					$$ = $1;
				}
		;

opt_arg:  IN
				{
					$$ = FALSE;
				}
		| OUT
				{
					elog(ERROR, "CREATE FUNCTION / OUT parameters are not supported");
					$$ = TRUE;
				}
		| INOUT
				{
					elog(ERROR, "CREATE FUNCTION / INOUT parameters are not supported");
					$$ = FALSE;
				}
		;

func_as: Sconst
				{   $$ = makeList1(makeString($1)); }
		| Sconst ',' Sconst
				{ 	$$ = makeList2(makeString($1), makeString($3)); }
		;

func_return:  func_type
				{
					/* We can catch over-specified arguments here if we want to,
					 * but for now better to silently swallow typmod, etc.
					 * - thomas 2000-03-22
					 */
					$$ = $1;
				}
		;

/*
 * We would like to make the second production here be ColId '.' ColId etc,
 * but that causes reduce/reduce conflicts.  type_name is next best choice.
 */
func_type:	Typename
				{
					$$ = $1;
				}
		| type_name '.' ColId '%' TYPE_P
				{
					$$ = makeNode(TypeName);
					$$->name = $1;
					$$->typmod = -1;
					$$->attrname = $3;
				}
		;

/*****************************************************************************
 *
 *		QUERY:
 *
 *		DROP FUNCTION funcname (arg1, arg2, ...)
 *		DROP AGGREGATE aggname (aggtype)
 *		DROP OPERATOR opname (leftoperand_typ rightoperand_typ)
 *
 *****************************************************************************/

RemoveFuncStmt:  DROP FUNCTION func_name func_args
				{
					RemoveFuncStmt *n = makeNode(RemoveFuncStmt);
					n->funcname = $3;
					n->args = $4;
					$$ = (Node *)n;
				}
		;

RemoveAggrStmt:  DROP AGGREGATE func_name '(' aggr_argtype ')'
				{
						RemoveAggrStmt *n = makeNode(RemoveAggrStmt);
						n->aggname = $3;
						n->aggtype = (Node *) $5;
						$$ = (Node *)n;
				}
		| DROP AGGREGATE func_name aggr_argtype
				{
						/* Obsolete syntax, but must support for awhile */
						RemoveAggrStmt *n = makeNode(RemoveAggrStmt);
						n->aggname = $3;
						n->aggtype = (Node *) $4;
						$$ = (Node *)n;
				}
		;

aggr_argtype:  Typename							{ $$ = $1; }
		| '*'									{ $$ = NULL; }
		;

RemoveOperStmt:  DROP OPERATOR all_Op '(' oper_argtypes ')'
				{
					RemoveOperStmt *n = makeNode(RemoveOperStmt);
					n->opname = $3;
					n->args = $5;
					$$ = (Node *)n;
				}
		;

oper_argtypes:	Typename
				{
				   elog(ERROR,"parser: argument type missing (use NONE for unary operators)");
				}
		| Typename ',' Typename
				{ $$ = makeList2($1, $3); }
		| NONE ',' Typename			/* left unary */
				{ $$ = makeList2(NULL, $3); }
		| Typename ',' NONE			/* right unary */
				{ $$ = makeList2($1, NULL); }
		;


/*****************************************************************************
 *
 *		QUERY:
 *
 *		REINDEX type <typename> [FORCE] [ALL]
 *
 *****************************************************************************/

ReindexStmt:  REINDEX reindex_type qualified_name opt_force
				{
					ReindexStmt *n = makeNode(ReindexStmt);
					n->reindexType = $2;
					n->relation = $3;
					n->name = NULL;
					n->force = $4;
					$$ = (Node *)n;
				}
		| REINDEX DATABASE name opt_force
				{
					ReindexStmt *n = makeNode(ReindexStmt);
					n->reindexType = DATABASE;
					n->name = $3;
					n->relation = NULL;
					n->force = $4;
					$$ = (Node *)n;
				}
		;

reindex_type:  INDEX								{  $$ = INDEX; }
		| TABLE										{  $$ = TABLE; }
		;

opt_force:	FORCE									{  $$ = TRUE; }
		| /* EMPTY */								{  $$ = FALSE; }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				rename <attrname1> in <relname> [*] to <attrname2>
 *				rename <relname1> to <relname2>
 *
 *****************************************************************************/

RenameStmt:  ALTER TABLE relation_expr RENAME opt_column opt_name TO name
				{
					RenameStmt *n = makeNode(RenameStmt);
					n->relation = $3;
					n->column = $6;
					n->newname = $8;
					$$ = (Node *)n;
				}
		;

opt_name:  name							{ $$ = $1; }
		| /*EMPTY*/						{ $$ = NULL; }
		;

opt_column:  COLUMN						{ $$ = COLUMN; }
		| /*EMPTY*/						{ $$ = 0; }
		;


/*****************************************************************************
 *
 *		QUERY:	Define Rewrite Rule
 *
 *****************************************************************************/

RuleStmt:  CREATE RULE name AS
		   { QueryIsRule=TRUE; }
		   ON event TO qualified_name where_clause
		   DO opt_instead RuleActionList
				{
					RuleStmt *n = makeNode(RuleStmt);
					n->relation = $9;
					n->rulename = $3;
					n->whereClause = $10;
					n->event = $7;
					n->instead = $12;
					n->actions = $13;
					$$ = (Node *)n;
					QueryIsRule=FALSE;
				}
		;

RuleActionList:  NOTHING				{ $$ = NIL; }
		| RuleActionStmt				{ $$ = makeList1($1); }
		| '(' RuleActionMulti ')'		{ $$ = $2; } 
		;

/* the thrashing around here is to discard "empty" statements... */
RuleActionMulti:  RuleActionMulti ';' RuleActionStmtOrEmpty
				{ if ($3 != (Node *) NULL)
					$$ = lappend($1, $3);
				  else
					$$ = $1;
				}
		| RuleActionStmtOrEmpty
				{ if ($1 != (Node *) NULL)
					$$ = makeList1($1);
				  else
					$$ = NIL;
				}
		;

RuleActionStmt:	SelectStmt
		| InsertStmt
		| UpdateStmt
		| DeleteStmt
		| NotifyStmt
		;

RuleActionStmtOrEmpty:	RuleActionStmt
		|	/*EMPTY*/
				{ $$ = (Node *)NULL; }
		;

/* change me to select, update, etc. some day */
event:	SELECT							{ $$ = CMD_SELECT; }
		| UPDATE						{ $$ = CMD_UPDATE; }
		| DELETE						{ $$ = CMD_DELETE; }
		| INSERT						{ $$ = CMD_INSERT; }
		 ;

opt_instead:  INSTEAD					{ $$ = TRUE; }
		| /*EMPTY*/						{ $$ = FALSE; }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				NOTIFY <qualified_name>	can appear both in rule bodies and
 *				as a query-level command
 *
 *****************************************************************************/

NotifyStmt:  NOTIFY qualified_name
				{
					NotifyStmt *n = makeNode(NotifyStmt);
					n->relation = $2;
					$$ = (Node *)n;
				}
		;

ListenStmt:  LISTEN qualified_name
				{
					ListenStmt *n = makeNode(ListenStmt);
					n->relation = $2;
					$$ = (Node *)n;
				}
		;

UnlistenStmt:  UNLISTEN qualified_name
				{
					UnlistenStmt *n = makeNode(UnlistenStmt);
					n->relation = $2;
					$$ = (Node *)n;
				}
		| UNLISTEN '*'
				{
					UnlistenStmt *n = makeNode(UnlistenStmt);
					n->relation = makeNode(RangeVar);
					n->relation->relname = "*";
					n->relation->schemaname = NULL;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		Transactions:
 *
 *      BEGIN / COMMIT / ROLLBACK
 *      (also older versions END / ABORT)
 *
 *****************************************************************************/

TransactionStmt: ABORT_TRANS opt_trans
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = ROLLBACK;
					$$ = (Node *)n;
				}
		| BEGIN_TRANS opt_trans
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = BEGIN_TRANS;
					$$ = (Node *)n;
				}
		| COMMIT opt_trans
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = COMMIT;
					$$ = (Node *)n;
				}
		| COMMIT opt_trans opt_chain
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = COMMIT;
					$$ = (Node *)n;
				}
		| END_TRANS opt_trans
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = COMMIT;
					$$ = (Node *)n;
				}
		| ROLLBACK opt_trans
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = ROLLBACK;
					$$ = (Node *)n;
				}
		| ROLLBACK opt_trans opt_chain
				{
					TransactionStmt *n = makeNode(TransactionStmt);
					n->command = ROLLBACK;
					$$ = (Node *)n;
				}
		;

opt_trans: WORK									{ $$ = TRUE; }
		| TRANSACTION							{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = TRUE; }
		;

opt_chain: AND NO CHAIN
				{ $$ = FALSE; }
		| AND CHAIN
				{
					/* SQL99 asks that conforming dbs reject AND CHAIN
					 * if they don't support it. So we can't just ignore it.
					 * - thomas 2000-08-06
					 */
					elog(ERROR, "COMMIT / CHAIN not yet supported");
					$$ = TRUE;
				}
		;


/*****************************************************************************
 *
 *		QUERY:
 *				define view <viewname> '('target-list ')' [where <quals> ]
 *
 *****************************************************************************/

ViewStmt:  CREATE VIEW qualified_name opt_column_list AS SelectStmt
				{
					ViewStmt *n = makeNode(ViewStmt);
					n->view = $3;
					n->aliases = $4;
					n->query = (Query *) $6;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		QUERY:
 *				load "filename"
 *
 *****************************************************************************/

LoadStmt:  LOAD file_name
				{
					LoadStmt *n = makeNode(LoadStmt);
					n->filename = $2;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		CREATE DATABASE
 *
 *****************************************************************************/

CreatedbStmt:  CREATE DATABASE database_name WITH createdb_opt_list
				{
					CreatedbStmt *n = makeNode(CreatedbStmt);
					List   *l;

					n->dbname = $3;
					/* set default options */
					n->dbowner = NULL;
					n->dbpath = NULL;
					n->dbtemplate = NULL;
					n->encoding = -1;
					/* process additional options */
					foreach(l, $5)
					{
						List   *optitem = (List *) lfirst(l);

						switch (lfirsti(optitem))
						{
							case 1:
								n->dbpath = (char *) lsecond(optitem);
								break;
							case 2:
								n->dbtemplate = (char *) lsecond(optitem);
								break;
							case 3:
								n->encoding = lfirsti(lnext(optitem));
								break;
							case 4:
								n->dbowner = (char *) lsecond(optitem);
								break;
						}
					}
					$$ = (Node *)n;
				}
		| CREATE DATABASE database_name
				{
					CreatedbStmt *n = makeNode(CreatedbStmt);
					n->dbname = $3;
					n->dbowner = NULL;
					n->dbpath = NULL;
					n->dbtemplate = NULL;
					n->encoding = -1;
					$$ = (Node *)n;
				}
		;

createdb_opt_list:  createdb_opt_item
				{ $$ = makeList1($1); }
		| createdb_opt_list createdb_opt_item
				{ $$ = lappend($1, $2); }
		;

/*
 * createdb_opt_item returns 2-element lists, with the first element
 * being an integer code to indicate which item was specified.
 */
createdb_opt_item:  LOCATION opt_equal Sconst
				{
					$$ = lconsi(1, makeList1($3));
				}
		| LOCATION opt_equal DEFAULT
				{
					$$ = lconsi(1, makeList1(NULL));
				}
		| TEMPLATE opt_equal name
				{
					$$ = lconsi(2, makeList1($3));
				}
		| TEMPLATE opt_equal DEFAULT
				{
					$$ = lconsi(2, makeList1(NULL));
				}
		| ENCODING opt_equal Sconst
				{
					int		encoding;
#ifdef MULTIBYTE
					encoding = pg_char_to_encoding($3);
					if (encoding == -1)
						elog(ERROR, "%s is not a valid encoding name", $3);
#else
					if (strcasecmp($3, GetStandardEncodingName()) != 0)
						elog(ERROR, "Multi-byte support is not enabled");
					encoding = GetStandardEncoding();
#endif
					$$ = lconsi(3, makeListi1(encoding));
				}
		| ENCODING opt_equal Iconst
				{
#ifdef MULTIBYTE
					if (!pg_get_enconv_by_encoding($3))
						elog(ERROR, "%d is not a valid encoding code", $3);
#else
					if ($3 != GetStandardEncoding())
						elog(ERROR, "Multi-byte support is not enabled");
#endif
					$$ = lconsi(3, makeListi1($3));
				}
		| ENCODING opt_equal DEFAULT
				{
					$$ = lconsi(3, makeListi1(-1));
				}
		| OWNER opt_equal name 
				{
					$$ = lconsi(4, makeList1($3));
				}
		| OWNER opt_equal DEFAULT
				{
					$$ = lconsi(4, makeList1(NULL));
				}
		;

/*
 *	Though the equals sign doesn't match other WITH options, pg_dump uses
 *  equals for backward compability, and it doesn't seem worth remove it.
 */
opt_equal: '='								{ $$ = TRUE; }
		| /*EMPTY*/							{ $$ = FALSE; }
		;


/*****************************************************************************
 *
 *		ALTER DATABASE
 *
 *****************************************************************************/

AlterDatabaseSetStmt: ALTER DATABASE database_name VariableSetStmt
				{
					AlterDatabaseSetStmt *n = makeNode(AlterDatabaseSetStmt);
					n->dbname = $3;
					n->variable = ((VariableSetStmt *)$4)->name;
					n->value = ((VariableSetStmt *)$4)->args;
					$$ = (Node *)n;
				}
				| ALTER DATABASE database_name VariableResetStmt
				{
					AlterDatabaseSetStmt *n = makeNode(AlterDatabaseSetStmt);
					n->dbname = $3;
					n->variable = ((VariableResetStmt *)$4)->name;
					n->value = NULL;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		DROP DATABASE
 *
 *****************************************************************************/

DropdbStmt:	DROP DATABASE database_name
				{
					DropdbStmt *n = makeNode(DropdbStmt);
					n->dbname = $3;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 * Manipulate a domain
 *
 *****************************************************************************/

CreateDomainStmt:  CREATE DOMAIN_P name opt_as Typename ColQualList opt_collate
				{
					CreateDomainStmt *n = makeNode(CreateDomainStmt);
					n->domainname = $3;
					n->typename = $5;
					n->constraints = $6;
					
					if ($7 != NULL)
						elog(NOTICE,"CREATE DOMAIN / COLLATE %s not yet "
							"implemented; clause ignored", $7);
					$$ = (Node *)n;
				}
		;

opt_as:	AS	{$$ = TRUE; }
	| /* EMPTY */	{$$ = FALSE; }
	;


/*****************************************************************************
 *
 *		QUERY:
 *				cluster <index_name> on <qualified_name>
 *
 *****************************************************************************/

ClusterStmt:  CLUSTER index_name ON qualified_name
				{
				   ClusterStmt *n = makeNode(ClusterStmt);
				   n->relation = $4;
				   n->indexname = $2;
				   $$ = (Node*)n;
				}
		;

/*****************************************************************************
 *
 *		QUERY:
 *				vacuum
 *				analyze
 *
 *****************************************************************************/

VacuumStmt:  VACUUM opt_full opt_freeze opt_verbose
				{
					VacuumStmt *n = makeNode(VacuumStmt);
					n->vacuum = true;
					n->analyze = false;
					n->full = $2;
					n->freeze = $3;
					n->verbose = $4;
					n->relation = NULL;
					n->va_cols = NIL;
					$$ = (Node *)n;
				}
		| VACUUM opt_full opt_freeze opt_verbose qualified_name
				{
					VacuumStmt *n = makeNode(VacuumStmt);
					n->vacuum = true;
					n->analyze = false;
					n->full = $2;
					n->freeze = $3;
					n->verbose = $4;
					n->relation = $5;
					n->va_cols = NIL;
					$$ = (Node *)n;
				}
		| VACUUM opt_full opt_freeze opt_verbose AnalyzeStmt
				{
					VacuumStmt *n = (VacuumStmt *) $5;
					n->vacuum = true;
					n->full = $2;
					n->freeze = $3;
					n->verbose |= $4;
					$$ = (Node *)n;
				}
		;

AnalyzeStmt:  analyze_keyword opt_verbose
				{
					VacuumStmt *n = makeNode(VacuumStmt);
					n->vacuum = false;
					n->analyze = true;
					n->full = false;
					n->freeze = false;
					n->verbose = $2;
					n->relation = NULL;
					n->va_cols = NIL;
					$$ = (Node *)n;
				}
		| analyze_keyword opt_verbose qualified_name opt_name_list
				{
					VacuumStmt *n = makeNode(VacuumStmt);
					n->vacuum = false;
					n->analyze = true;
					n->full = false;
					n->freeze = false;
					n->verbose = $2;
					n->relation = $3;
					n->va_cols = $4;
					$$ = (Node *)n;
				}
		;

analyze_keyword:  ANALYZE						{ $$ = TRUE; }
		|	  ANALYSE /* British */				{ $$ = TRUE; }
		;

opt_verbose:  VERBOSE							{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_full:  FULL									{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_freeze:  FREEZE								{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_name_list:  '(' name_list ')'				{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NIL; }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				EXPLAIN query
 *				EXPLAIN ANALYZE query
 *
 *****************************************************************************/

ExplainStmt:  EXPLAIN opt_verbose OptimizableStmt
				{
					ExplainStmt *n = makeNode(ExplainStmt);
					n->verbose = $2;
					n->analyze = FALSE;
					n->query = (Query*)$3;
					$$ = (Node *)n;
				}
			| EXPLAIN analyze_keyword opt_verbose OptimizableStmt
				{
					ExplainStmt *n = makeNode(ExplainStmt);
					n->verbose = $3;
					n->analyze = TRUE;
					n->query = (Query*)$4;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *																			 *
 *		Optimizable Stmts:													 *
 *																			 *
 *		one of the five queries processed by the planner					 *
 *																			 *
 *		[ultimately] produces query-trees as specified						 *
 *		in the query-spec document in ~postgres/ref							 *
 *																			 *
 *****************************************************************************/

OptimizableStmt:  SelectStmt
		| CursorStmt
		| UpdateStmt
		| InsertStmt
		| DeleteStmt					/* by default all are $$=$1 */
		;


/*****************************************************************************
 *
 *		QUERY:
 *				INSERT STATEMENTS
 *
 *****************************************************************************/

InsertStmt:  INSERT INTO qualified_name insert_rest
				{
 					$4->relation = $3;
					$$ = (Node *) $4;
				}
		;

insert_rest:  VALUES '(' target_list ')'
				{
					$$ = makeNode(InsertStmt);
					$$->cols = NIL;
					$$->targetList = $3;
					$$->selectStmt = NULL;
				}
		| DEFAULT VALUES
				{
					$$ = makeNode(InsertStmt);
					$$->cols = NIL;
					$$->targetList = NIL;
					$$->selectStmt = NULL;
				}
		| SelectStmt
				{
					$$ = makeNode(InsertStmt);
					$$->cols = NIL;
					$$->targetList = NIL;
					$$->selectStmt = $1;
				}
		| '(' insert_column_list ')' VALUES '(' target_list ')'
				{
					$$ = makeNode(InsertStmt);
					$$->cols = $2;
					$$->targetList = $6;
					$$->selectStmt = NULL;
				}
		| '(' insert_column_list ')' SelectStmt
				{
					$$ = makeNode(InsertStmt);
					$$->cols = $2;
					$$->targetList = NIL;
					$$->selectStmt = $4;
				}
		;

insert_column_list:  insert_column_list ',' insert_column_item
				{ $$ = lappend($1, $3); }
		| insert_column_item
				{ $$ = makeList1($1); }
		;

insert_column_item:  ColId opt_indirection
				{
					ResTarget *n = makeNode(ResTarget);
					n->name = $1;
					n->indirection = $2;
					n->val = NULL;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		QUERY:
 *				DELETE STATEMENTS
 *
 *****************************************************************************/

DeleteStmt:  DELETE FROM relation_expr where_clause
				{
					DeleteStmt *n = makeNode(DeleteStmt);
					n->relation = $3;
					n->whereClause = $4;
					$$ = (Node *)n;
				}
		;

LockStmt:	LOCK_P opt_table qualified_name_list opt_lock
				{
					LockStmt *n = makeNode(LockStmt);

					n->relations = $3;
					n->mode = $4;
					$$ = (Node *)n;
				}
		;

opt_lock:  IN lock_type MODE	{ $$ = $2; }
		| /*EMPTY*/				{ $$ = AccessExclusiveLock; }
		;

lock_type:  ACCESS SHARE		{ $$ = AccessShareLock; }
		| ROW SHARE				{ $$ = RowShareLock; }
		| ROW EXCLUSIVE			{ $$ = RowExclusiveLock; }
		| SHARE UPDATE EXCLUSIVE { $$ = ShareUpdateExclusiveLock; }
		| SHARE					{ $$ = ShareLock; }
		| SHARE ROW EXCLUSIVE	{ $$ = ShareRowExclusiveLock; }
		| EXCLUSIVE				{ $$ = ExclusiveLock; }
		| ACCESS EXCLUSIVE		{ $$ = AccessExclusiveLock; }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				UpdateStmt (UPDATE)
 *
 *****************************************************************************/

UpdateStmt:  UPDATE relation_expr
			  SET update_target_list
			  from_clause
			  where_clause
				{
					UpdateStmt *n = makeNode(UpdateStmt);
					n->relation = $2;
					n->targetList = $4;
					n->fromClause = $5;
					n->whereClause = $6;
					$$ = (Node *)n;
				}
		;


/*****************************************************************************
 *
 *		QUERY:
 *				CURSOR STATEMENTS
 *
 *****************************************************************************/
CursorStmt:  DECLARE name opt_cursor CURSOR FOR SelectStmt
  				{
 					SelectStmt *n = (SelectStmt *)$6;
					n->portalname = $2;
					n->binary = $3;
					$$ = $6;
				}
		;

opt_cursor:  BINARY						{ $$ = TRUE; }
		| INSENSITIVE					{ $$ = FALSE; }
		| SCROLL						{ $$ = FALSE; }
		| INSENSITIVE SCROLL			{ $$ = FALSE; }
		| /*EMPTY*/						{ $$ = FALSE; }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				SELECT STATEMENTS
 *
 *****************************************************************************/

/* A complete SELECT statement looks like this.
 *
 * The rule returns either a single SelectStmt node or a tree of them,
 * representing a set-operation tree.
 *
 * There is an ambiguity when a sub-SELECT is within an a_expr and there
 * are excess parentheses: do the parentheses belong to the sub-SELECT or
 * to the surrounding a_expr?  We don't really care, but yacc wants to know.
 * To resolve the ambiguity, we are careful to define the grammar so that
 * the decision is staved off as long as possible: as long as we can keep
 * absorbing parentheses into the sub-SELECT, we will do so, and only when
 * it's no longer possible to do that will we decide that parens belong to
 * the expression.  For example, in "SELECT (((SELECT 2)) + 3)" the extra
 * parentheses are treated as part of the sub-select.  The necessity of doing
 * it that way is shown by "SELECT (((SELECT 2)) UNION SELECT 2)".  Had we
 * parsed "((SELECT 2))" as an a_expr, it'd be too late to go back to the
 * SELECT viewpoint when we see the UNION.
 *
 * This approach is implemented by defining a nonterminal select_with_parens,
 * which represents a SELECT with at least one outer layer of parentheses,
 * and being careful to use select_with_parens, never '(' SelectStmt ')',
 * in the expression grammar.  We will then have shift-reduce conflicts
 * which we can resolve in favor of always treating '(' <select> ')' as
 * a select_with_parens.  To resolve the conflicts, the productions that
 * conflict with the select_with_parens productions are manually given
 * precedences lower than the precedence of ')', thereby ensuring that we
 * shift ')' (and then reduce to select_with_parens) rather than trying to
 * reduce the inner <select> nonterminal to something else.  We use UMINUS
 * precedence for this, which is a fairly arbitrary choice.
 *
 * To be able to define select_with_parens itself without ambiguity, we need
 * a nonterminal select_no_parens that represents a SELECT structure with no
 * outermost parentheses.  This is a little bit tedious, but it works.
 *
 * In non-expression contexts, we use SelectStmt which can represent a SELECT
 * with or without outer parentheses.
 */

SelectStmt: select_no_parens			%prec UMINUS
		| select_with_parens			%prec UMINUS
		;

select_with_parens: '(' select_no_parens ')'
			{
				$$ = $2;
			}
		| '(' select_with_parens ')'
			{
				$$ = $2;
			}
		;

select_no_parens: simple_select
			{
				$$ = $1;
			}
		| select_clause sort_clause opt_for_update_clause opt_select_limit
			{
				insertSelectOptions((SelectStmt *) $1, $2, $3,
									nth(0, $4), nth(1, $4));
				$$ = $1;
			}
		| select_clause for_update_clause opt_select_limit
			{
				insertSelectOptions((SelectStmt *) $1, NIL, $2,
									nth(0, $3), nth(1, $3));
				$$ = $1;
			}
		| select_clause select_limit
			{
				insertSelectOptions((SelectStmt *) $1, NIL, NIL,
									nth(0, $2), nth(1, $2));
				$$ = $1;
			}
		;

select_clause: simple_select
		| select_with_parens
		;

/*
 * This rule parses SELECT statements that can appear within set operations,
 * including UNION, INTERSECT and EXCEPT.  '(' and ')' can be used to specify
 * the ordering of the set operations.  Without '(' and ')' we want the
 * operations to be ordered per the precedence specs at the head of this file.
 *
 * As with select_no_parens, simple_select cannot have outer parentheses,
 * but can have parenthesized subclauses.
 *
 * Note that sort clauses cannot be included at this level --- SQL92 requires
 *		SELECT foo UNION SELECT bar ORDER BY baz
 * to be parsed as
 *		(SELECT foo UNION SELECT bar) ORDER BY baz
 * not
 *		SELECT foo UNION (SELECT bar ORDER BY baz)
 * Likewise FOR UPDATE and LIMIT.  Therefore, those clauses are described
 * as part of the select_no_parens production, not simple_select.
 * This does not limit functionality, because you can reintroduce sort and
 * limit clauses inside parentheses.
 *
 * NOTE: only the leftmost component SelectStmt should have INTO.
 * However, this is not checked by the grammar; parse analysis must check it.
 */
simple_select: SELECT opt_distinct target_list
			 into_clause from_clause where_clause
			 group_clause having_clause
				{
					SelectStmt *n = makeNode(SelectStmt);
					n->distinctClause = $2;
					n->targetList = $3;
					n->into = $4;
					n->intoColNames = NIL;
					n->fromClause = $5;
					n->whereClause = $6;
					n->groupClause = $7;
					n->havingClause = $8;
					$$ = (Node *)n;
				}
		| select_clause UNION opt_all select_clause
			{	
				$$ = makeSetOp(SETOP_UNION, $3, $1, $4);
			}
		| select_clause INTERSECT opt_all select_clause
			{
				$$ = makeSetOp(SETOP_INTERSECT, $3, $1, $4);
			}
		| select_clause EXCEPT opt_all select_clause
			{
				$$ = makeSetOp(SETOP_EXCEPT, $3, $1, $4);
			}
		; 

into_clause:  INTO OptTempTableName		{ $$ = $2; }
		| /*EMPTY*/		{ $$ = NULL; }
		;

/*
 * Redundancy here is needed to avoid shift/reduce conflicts,
 * since TEMP is not a reserved word.  See also OptTemp.
 */
OptTempTableName:  TEMPORARY opt_table qualified_name
				{ 
					$$ = $3;
					$$->istemp = true;
				}
			| TEMP opt_table qualified_name
				{ 
					$$ = $3;
					$$->istemp = true;
				}
			| LOCAL TEMPORARY opt_table qualified_name
				{ 
					$$ = $4;
					$$->istemp = true;
				}
			| LOCAL TEMP opt_table qualified_name
				{ 
					$$ = $4;
					$$->istemp = true;
				}
			| GLOBAL TEMPORARY opt_table qualified_name
				{
					elog(ERROR, "GLOBAL TEMPORARY TABLE is not currently supported");
					$$ = $4;
					$$->istemp = true;
				}
			| GLOBAL TEMP opt_table qualified_name
				{
					elog(ERROR, "GLOBAL TEMPORARY TABLE is not currently supported");
					$$ = $4;
					$$->istemp = true;
				}
			| TABLE qualified_name
				{ 
					$$ = $2;
					$$->istemp = false;
				}
			| qualified_name
				{ 
					$$ = $1;
					$$->istemp = false;
				}
		;

opt_table:  TABLE								{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_all:  ALL									{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

/* We use (NIL) as a placeholder to indicate that all target expressions
 * should be placed in the DISTINCT list during parsetree analysis.
 */
opt_distinct:  DISTINCT							{ $$ = makeList1(NIL); }
		| DISTINCT ON '(' expr_list ')'			{ $$ = $4; }
		| ALL									{ $$ = NIL; }
		| /*EMPTY*/								{ $$ = NIL; }
		;

sort_clause:  ORDER BY sortby_list				{ $$ = $3; }
		;

sortby_list:  sortby							{ $$ = makeList1($1); }
		| sortby_list ',' sortby				{ $$ = lappend($1, $3); }
		;

sortby: a_expr OptUseOp
				{
					$$ = makeNode(SortGroupBy);
					$$->node = $1;
					$$->useOp = $2;
				}
		;

OptUseOp:  USING all_Op							{ $$ = $2; }
		| ASC									{ $$ = "<"; }
		| DESC									{ $$ = ">"; }
		| /*EMPTY*/								{ $$ = "<"; /*default*/ }
		;


select_limit:	LIMIT select_limit_value OFFSET select_offset_value
			{ $$ = makeList2($4, $2); }
		| OFFSET select_offset_value LIMIT select_limit_value
			{ $$ = makeList2($2, $4); }
		| LIMIT select_limit_value
			{ $$ = makeList2(NULL, $2); }
		| OFFSET select_offset_value
			{ $$ = makeList2($2, NULL); }
		| LIMIT select_limit_value ',' select_offset_value
			/* Disabled because it was too confusing, bjm 2002-02-18 */
			{ elog(ERROR, "LIMIT #,# syntax not supported.\n\tUse separate LIMIT and OFFSET clauses."); }
		;


opt_select_limit:	select_limit				{ $$ = $1; }
		| /* EMPTY */							{ $$ = makeList2(NULL,NULL); }
		;

select_limit_value:  Iconst
			{
				Const	*n = makeNode(Const);

				if ($1 < 0)
					elog(ERROR, "LIMIT must not be negative");

				n->consttype	= INT4OID;
				n->constlen		= sizeof(int4);
				n->constvalue	= Int32GetDatum($1);
				n->constisnull	= FALSE;
				n->constbyval	= TRUE;
				n->constisset	= FALSE;
				n->constiscast	= FALSE;
				$$ = (Node *)n;
			}
		| ALL
			{
				/* LIMIT ALL is represented as a NULL constant */
				Const	*n = makeNode(Const);

				n->consttype	= INT4OID;
				n->constlen		= sizeof(int4);
				n->constvalue	= (Datum) 0;
				n->constisnull	= TRUE;
				n->constbyval	= TRUE;
				n->constisset	= FALSE;
				n->constiscast	= FALSE;
				$$ = (Node *)n;
			}
		| PARAM
			{
				Param	*n = makeNode(Param);

				n->paramkind	= PARAM_NUM;
				n->paramid		= $1;
				n->paramtype	= INT4OID;
				$$ = (Node *)n;
			}
		;

select_offset_value:	Iconst
			{
				Const	*n = makeNode(Const);

				if ($1 < 0)
					elog(ERROR, "OFFSET must not be negative");

				n->consttype	= INT4OID;
				n->constlen		= sizeof(int4);
				n->constvalue	= Int32GetDatum($1);
				n->constisnull	= FALSE;
				n->constbyval	= TRUE;
				n->constisset	= FALSE;
				n->constiscast	= FALSE;
				$$ = (Node *)n;
			}
		| PARAM
			{
				Param	*n = makeNode(Param);

				n->paramkind	= PARAM_NUM;
				n->paramid		= $1;
				n->paramtype	= INT4OID;
				$$ = (Node *)n;
			}
		;

/*
 *	jimmy bell-style recursive queries aren't supported in the
 *	current system.
 *
 *	...however, recursive addattr and rename supported.  make special
 *	cases for these.
 */

group_clause:  GROUP BY expr_list				{ $$ = $3; }
		| /*EMPTY*/								{ $$ = NIL; }
		;

having_clause:  HAVING a_expr
				{
					$$ = $2;
				}
		| /*EMPTY*/								{ $$ = NULL; }
		;

for_update_clause:  FOR UPDATE update_list		{ $$ = $3; }
		| FOR READ ONLY							{ $$ = NULL; }
		;

opt_for_update_clause:	for_update_clause		{ $$ = $1; }
		| /* EMPTY */							{ $$ = NULL; }
		;

update_list:  OF name_list						{ $$ = $2; }
		| /* EMPTY */							{ $$ = makeList1(NULL); }
		;

/*****************************************************************************
 *
 *	clauses common to all Optimizable Stmts:
 *		from_clause		- allow list of both JOIN expressions and table names
 *		where_clause	- qualifications for joins or restrictions
 *
 *****************************************************************************/

from_clause:  FROM from_list					{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NIL; }
		;

from_list:  from_list ',' table_ref				{ $$ = lappend($1, $3); }
		| table_ref								{ $$ = makeList1($1); }
		;

/*
 * table_ref is where an alias clause can be attached.  Note we cannot make
 * alias_clause have an empty production because that causes parse conflicts
 * between table_ref := '(' joined_table ')' alias_clause
 * and joined_table := '(' joined_table ')'.  So, we must have the
 * redundant-looking productions here instead.
 */
table_ref:  relation_expr
				{
					$$ = (Node *) $1;
				}
		| relation_expr alias_clause
				{
					$1->alias = $2;
					$$ = (Node *) $1;
				}
		| select_with_parens
				{
					/*
					 * The SQL spec does not permit a subselect
					 * (<derived_table>) without an alias clause,
					 * so we don't either.  This avoids the problem
					 * of needing to invent a unique refname for it.
					 * That could be surmounted if there's sufficient
					 * popular demand, but for now let's just implement
					 * the spec and see if anyone complains.
					 * However, it does seem like a good idea to emit
					 * an error message that's better than "parse error".
					 */
					elog(ERROR, "sub-SELECT in FROM must have an alias"
						 "\n\tFor example, FROM (SELECT ...) [AS] foo");
					$$ = NULL;
				}
		| select_with_parens alias_clause
				{
					RangeSubselect *n = makeNode(RangeSubselect);
					n->subquery = $1;
					n->alias = $2;
					$$ = (Node *) n;
				}
		| joined_table
				{
					$$ = (Node *) $1;
				}
		| '(' joined_table ')' alias_clause
				{
					$2->alias = $4;
					$$ = (Node *) $2;
				}
		;

/*
 * It may seem silly to separate joined_table from table_ref, but there is
 * method in SQL92's madness: if you don't do it this way you get reduce-
 * reduce conflicts, because it's not clear to the parser generator whether
 * to expect alias_clause after ')' or not.  For the same reason we must
 * treat 'JOIN' and 'join_type JOIN' separately, rather than allowing
 * join_type to expand to empty; if we try it, the parser generator can't
 * figure out when to reduce an empty join_type right after table_ref.
 *
 * Note that a CROSS JOIN is the same as an unqualified
 * INNER JOIN, and an INNER JOIN/ON has the same shape
 * but a qualification expression to limit membership.
 * A NATURAL JOIN implicitly matches column names between
 * tables and the shape is determined by which columns are
 * in common. We'll collect columns during the later transformations.
 */

joined_table:  '(' joined_table ')'
				{
					$$ = $2;
				}
		| table_ref CROSS JOIN table_ref
				{
					/* CROSS JOIN is same as unqualified inner join */
					JoinExpr *n = makeNode(JoinExpr);
					n->jointype = JOIN_INNER;
					n->isNatural = FALSE;
					n->larg = $1;
					n->rarg = $4;
					n->using = NIL;
					n->quals = NULL;
					$$ = n;
				}
		| table_ref UNIONJOIN table_ref
				{
					/* UNION JOIN is made into 1 token to avoid shift/reduce
					 * conflict against regular UNION keyword.
					 */
					JoinExpr *n = makeNode(JoinExpr);
					n->jointype = JOIN_UNION;
					n->isNatural = FALSE;
					n->larg = $1;
					n->rarg = $3;
					n->using = NIL;
					n->quals = NULL;
					$$ = n;
				}
		| table_ref join_type JOIN table_ref join_qual
				{
					JoinExpr *n = makeNode(JoinExpr);
					n->jointype = $2;
					n->isNatural = FALSE;
					n->larg = $1;
					n->rarg = $4;
					if ($5 != NULL && IsA($5, List))
						n->using = (List *) $5;	/* USING clause */
					else
						n->quals = $5; /* ON clause */
					$$ = n;
				}
		| table_ref JOIN table_ref join_qual
				{
					/* letting join_type reduce to empty doesn't work */
					JoinExpr *n = makeNode(JoinExpr);
					n->jointype = JOIN_INNER;
					n->isNatural = FALSE;
					n->larg = $1;
					n->rarg = $3;
					if ($4 != NULL && IsA($4, List))
						n->using = (List *) $4;	/* USING clause */
					else
						n->quals = $4; /* ON clause */
					$$ = n;
				}
		| table_ref NATURAL join_type JOIN table_ref
				{
					JoinExpr *n = makeNode(JoinExpr);
					n->jointype = $3;
					n->isNatural = TRUE;
					n->larg = $1;
					n->rarg = $5;
					n->using = NIL; /* figure out which columns later... */
					n->quals = NULL; /* fill later */
					$$ = n;
				}
		| table_ref NATURAL JOIN table_ref
				{
					/* letting join_type reduce to empty doesn't work */
					JoinExpr *n = makeNode(JoinExpr);
					n->jointype = JOIN_INNER;
					n->isNatural = TRUE;
					n->larg = $1;
					n->rarg = $4;
					n->using = NIL; /* figure out which columns later... */
					n->quals = NULL; /* fill later */
					$$ = n;
				}
		;

alias_clause:  AS ColId '(' name_list ')'
				{
					$$ = makeNode(Alias);
					$$->aliasname = $2;
					$$->colnames = $4;
				}
		| AS ColId
				{
					$$ = makeNode(Alias);
					$$->aliasname = $2;
				}
		| ColId '(' name_list ')'
				{
					$$ = makeNode(Alias);
					$$->aliasname = $1;
					$$->colnames = $3;
				}
		| ColId
				{
					$$ = makeNode(Alias);
					$$->aliasname = $1;
				}
		;

join_type:  FULL join_outer						{ $$ = JOIN_FULL; }
		| LEFT join_outer						{ $$ = JOIN_LEFT; }
		| RIGHT join_outer						{ $$ = JOIN_RIGHT; }
		| INNER_P								{ $$ = JOIN_INNER; }
		;

/* OUTER is just noise... */
join_outer:  OUTER_P							{ $$ = NULL; }
		| /*EMPTY*/								{ $$ = NULL; }
		;

/* JOIN qualification clauses
 * Possibilities are:
 *  USING ( column list ) allows only unqualified column names,
 *                        which must match between tables.
 *  ON expr allows more general qualifications.
 *
 * We return USING as a List node, while an ON-expr will not be a List.
 */

join_qual:  USING '(' name_list ')'				{ $$ = (Node *) $3; }
		| ON a_expr								{ $$ = $2; }
		;


relation_expr:	qualified_name
				{
					/* default inheritance */
					$$ = $1;
					$$->inhOpt = INH_DEFAULT;
					$$->alias = NULL;
				}
		| qualified_name '*'
				{
					/* inheritance query */
					$$ = $1;
					$$->inhOpt = INH_YES;
					$$->alias = NULL;
				}
		| ONLY qualified_name
				{
					/* no inheritance */
					$$ = $2;
					$$->inhOpt = INH_NO;
					$$->alias = NULL;
                }
		;

where_clause:  WHERE a_expr						{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NULL;  /* no qualifiers */ }
		;


/*****************************************************************************
 *
 *	Type syntax
 *		SQL92 introduces a large amount of type-specific syntax.
 *		Define individual clauses to handle these cases, and use
 *		 the generic case to handle regular type-extensible Postgres syntax.
 *		- thomas 1997-10-10
 *
 *****************************************************************************/

Typename:  SimpleTypename opt_array_bounds
				{
					$$ = $1;
					$$->arrayBounds = $2;
				}
		| SETOF SimpleTypename
				{
					$$ = $2;
					$$->setof = TRUE;
				}
		;

opt_array_bounds:	opt_array_bounds '[' ']'
				{  $$ = lappend($1, makeInteger(-1)); }
		| opt_array_bounds '[' Iconst ']'
				{  $$ = lappend($1, makeInteger($3)); }
		| /*EMPTY*/
				{  $$ = NIL; }
		;

SimpleTypename:  ConstTypename
		| ConstInterval opt_interval
				{
					$$ = $1;
					if ($2 != -1)
						$$->typmod = ((($2 & 0x7FFF) << 16) | 0xFFFF);
				}
		| ConstInterval '(' Iconst ')' opt_interval
				{
					$$ = $1;
					$$->typmod = ((($5 & 0x7FFF) << 16) | $3);
				}
		;

ConstTypename:  GenericType
		| Numeric
		| Bit
		| Character
		| ConstDatetime
		;

GenericType:  type_name
				{
					$$ = makeNode(TypeName);
					$$->name = xlateSqlType($1);
					$$->typmod = -1;
				}
		;

/* SQL92 numeric data types
 * Check FLOAT() precision limits assuming IEEE floating types.
 * Provide real DECIMAL() and NUMERIC() implementations now - Jan 1998-12-30
 * - thomas 1997-09-18
 */
Numeric:  FLOAT opt_float
				{
					$$ = makeNode(TypeName);
					$$->name = $2; /* already xlated */
					$$->typmod = -1;
				}
		| DOUBLE PRECISION
				{
					$$ = makeNode(TypeName);
					$$->name = xlateSqlType("float8");
					$$->typmod = -1;
				}
		| DECIMAL opt_decimal
				{
					$$ = makeNode(TypeName);
					$$->name = xlateSqlType("decimal");
					$$->typmod = $2;
				}
		| DEC opt_decimal
				{
					$$ = makeNode(TypeName);
					$$->name = xlateSqlType("decimal");
					$$->typmod = $2;
				}
		| NUMERIC opt_numeric
				{
					$$ = makeNode(TypeName);
					$$->name = xlateSqlType("numeric");
					$$->typmod = $2;
				}
		;

opt_float:  '(' Iconst ')'
				{
					if ($2 < 1)
						elog(ERROR,"precision for FLOAT must be at least 1");
					else if ($2 < 7)
						$$ = xlateSqlType("float4");
					else if ($2 < 16)
						$$ = xlateSqlType("float8");
					else
						elog(ERROR,"precision for FLOAT must be less than 16");
				}
		| /*EMPTY*/
				{
					$$ = xlateSqlType("float8");
				}
		;

opt_numeric:  '(' Iconst ',' Iconst ')'
				{
					if ($2 < 1 || $2 > NUMERIC_MAX_PRECISION)
						elog(ERROR,"NUMERIC precision %d must be between 1 and %d",
							 $2, NUMERIC_MAX_PRECISION);
					if ($4 < 0 || $4 > $2)
						elog(ERROR,"NUMERIC scale %d must be between 0 and precision %d",
							 $4,$2);

					$$ = (($2 << 16) | $4) + VARHDRSZ;
				}
		| '(' Iconst ')'
				{
					if ($2 < 1 || $2 > NUMERIC_MAX_PRECISION)
						elog(ERROR,"NUMERIC precision %d must be between 1 and %d",
							 $2, NUMERIC_MAX_PRECISION);

					$$ = ($2 << 16) + VARHDRSZ;
				}
		| /*EMPTY*/
				{
					/* Insert "-1" meaning "no limit" */
					$$ = -1;
				}
		;

opt_decimal:  '(' Iconst ',' Iconst ')'
				{
					if ($2 < 1 || $2 > NUMERIC_MAX_PRECISION)
						elog(ERROR,"DECIMAL precision %d must be between 1 and %d",
									$2, NUMERIC_MAX_PRECISION);
					if ($4 < 0 || $4 > $2)
						elog(ERROR,"DECIMAL scale %d must be between 0 and precision %d",
									$4,$2);

					$$ = (($2 << 16) | $4) + VARHDRSZ;
				}
		| '(' Iconst ')'
				{
					if ($2 < 1 || $2 > NUMERIC_MAX_PRECISION)
						elog(ERROR,"DECIMAL precision %d must be between 1 and %d",
									$2, NUMERIC_MAX_PRECISION);

					$$ = ($2 << 16) + VARHDRSZ;
				}
		| /*EMPTY*/
				{
					/* Insert "-1" meaning "no limit" */
					$$ = -1;
				}
		;


/*
 * SQL92 bit-field data types
 * The following implements BIT() and BIT VARYING().
 */
Bit:  bit '(' Iconst ')'
				{
					$$ = makeNode(TypeName);
					$$->name = $1;
					if ($3 < 1)
						elog(ERROR,"length for type '%s' must be at least 1",
							 $1);
					else if ($3 > (MaxAttrSize * BITS_PER_BYTE))
						elog(ERROR,"length for type '%s' cannot exceed %d",
							 $1, (MaxAttrSize * BITS_PER_BYTE));
					$$->typmod = $3;
				}
		| bit
				{
					$$ = makeNode(TypeName);
					$$->name = $1;
					/* bit defaults to bit(1), varbit to no limit */
					if (strcmp($1, "bit") == 0)
						$$->typmod = 1;
					else
						$$->typmod = -1;
				}
		;

bit:  BIT opt_varying
				{
					char *type;

					if ($2) type = xlateSqlType("varbit");
					else type = xlateSqlType("bit");
					$$ = type;
				}
		;


/*
 * SQL92 character data types
 * The following implements CHAR() and VARCHAR().
 */
Character:  character '(' Iconst ')' opt_charset
				{
					$$ = makeNode(TypeName);
					$$->name = $1;
					if ($3 < 1)
						elog(ERROR,"length for type '%s' must be at least 1",
							 $1);
					else if ($3 > MaxAttrSize)
						elog(ERROR,"length for type '%s' cannot exceed %d",
							 $1, MaxAttrSize);

					/* we actually implement these like a varlen, so
					 * the first 4 bytes is the length. (the difference
					 * between these and "text" is that we blank-pad and
					 * truncate where necessary)
					 */
					$$->typmod = VARHDRSZ + $3;

					if (($5 != NULL) && (strcmp($5, "sql_text") != 0)) {
						char *type;

						type = palloc(strlen($$->name) + 1 + strlen($5) + 1);
						strcpy(type, $$->name);
						strcat(type, "_");
						strcat(type, $5);
						$$->name = xlateSqlType(type);
					};
				}
		| character opt_charset
				{
					$$ = makeNode(TypeName);
					$$->name = $1;
					/* char defaults to char(1), varchar to no limit */
					if (strcmp($1, "bpchar") == 0)
						$$->typmod = VARHDRSZ + 1;
					else
						$$->typmod = -1;

					if (($2 != NULL) && (strcmp($2, "sql_text") != 0)) {
						char *type;

						type = palloc(strlen($$->name) + 1 + strlen($2) + 1);
						strcpy(type, $$->name);
						strcat(type, "_");
						strcat(type, $2);
						$$->name = xlateSqlType(type);
					};
				}
		;

character:  CHARACTER opt_varying				{ $$ = xlateSqlType($2 ? "varchar": "bpchar"); }
		| CHAR opt_varying						{ $$ = xlateSqlType($2 ? "varchar": "bpchar"); }
		| VARCHAR								{ $$ = xlateSqlType("varchar"); }
		| NATIONAL CHARACTER opt_varying		{ $$ = xlateSqlType($3 ? "varchar": "bpchar"); }
		| NATIONAL CHAR opt_varying				{ $$ = xlateSqlType($3 ? "varchar": "bpchar"); }
		| NCHAR opt_varying						{ $$ = xlateSqlType($2 ? "varchar": "bpchar"); }
		;

opt_varying:  VARYING							{ $$ = TRUE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_charset:  CHARACTER SET ColId				{ $$ = $3; }
		| /*EMPTY*/								{ $$ = NULL; }
		;

opt_collate:  COLLATE ColId						{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NULL; }
		;

ConstDatetime:  TIMESTAMP '(' Iconst ')' opt_timezone_x
				{
					$$ = makeNode(TypeName);
					if ($5)
						$$->name = xlateSqlType("timestamptz");
					else
						$$->name = xlateSqlType("timestamp");
					/* XXX the timezone field seems to be unused
					 * - thomas 2001-09-06
					 */
					$$->timezone = $5;
					if (($3 < 0) || ($3 > 13))
						elog(ERROR,"TIMESTAMP(%d)%s precision must be between %d and %d",
							 $3, ($5 ? " WITH TIME ZONE": ""), 0, 13);
					$$->typmod = $3;
				}
		| TIMESTAMP opt_timezone_x
				{
					$$ = makeNode(TypeName);
					if ($2)
						$$->name = xlateSqlType("timestamptz");
					else
						$$->name = xlateSqlType("timestamp");
					/* XXX the timezone field seems to be unused
					 * - thomas 2001-09-06
					 */
					$$->timezone = $2;
					/* SQL99 specified a default precision of six
					 * for schema definitions. But for timestamp
					 * literals we don't want to throw away precision
					 * so leave this as unspecified for now.
					 * Later, we may want a different production
					 * for schemas. - thomas 2001-12-07
					 */
					$$->typmod = -1;
				}
		| TIME '(' Iconst ')' opt_timezone
				{
					$$ = makeNode(TypeName);
					if ($5)
						$$->name = xlateSqlType("timetz");
					else
						$$->name = xlateSqlType("time");
					if (($3 < 0) || ($3 > 13))
						elog(ERROR,"TIME(%d)%s precision must be between %d and %d",
							 $3, ($5 ? " WITH TIME ZONE": ""), 0, 13);
					$$->typmod = $3;
				}
		| TIME opt_timezone
				{
					$$ = makeNode(TypeName);
					if ($2)
						$$->name = xlateSqlType("timetz");
					else
						$$->name = xlateSqlType("time");
					/* SQL99 specified a default precision of zero.
					 * See comments for timestamp above on why we will
					 * leave this unspecified for now. - thomas 2001-12-07
					 */
					$$->typmod = -1;
				}
		;

ConstInterval:  INTERVAL
				{
					$$ = makeNode(TypeName);
					$$->name = xlateSqlType("interval");
					$$->typmod = -1;
				}
		;

/* XXX Make the default be WITH TIME ZONE for 7.2 to help with database upgrades
 * but revert this back to WITHOUT TIME ZONE for 7.3.
 * Do this by simply reverting opt_timezone_x to opt_timezone - thomas 2001-09-06
 */

opt_timezone_x:  WITH TIME ZONE					{ $$ = TRUE; }
		| WITHOUT TIME ZONE						{ $$ = FALSE; }
		| /*EMPTY*/								{ $$ = TRUE; }
		;

opt_timezone:  WITH TIME ZONE					{ $$ = TRUE; }
		| WITHOUT TIME ZONE						{ $$ = FALSE; }
		| /*EMPTY*/								{ $$ = FALSE; }
		;

opt_interval:  YEAR_P							{ $$ = MASK(YEAR); }
		| MONTH_P								{ $$ = MASK(MONTH); }
		| DAY_P									{ $$ = MASK(DAY); }
		| HOUR_P								{ $$ = MASK(HOUR); }
		| MINUTE_P								{ $$ = MASK(MINUTE); }
		| SECOND_P								{ $$ = MASK(SECOND); }
		| YEAR_P TO MONTH_P						{ $$ = MASK(YEAR) | MASK(MONTH); }
		| DAY_P TO HOUR_P						{ $$ = MASK(DAY) | MASK(HOUR); }
		| DAY_P TO MINUTE_P						{ $$ = MASK(DAY) | MASK(HOUR) | MASK(MINUTE); }
		| DAY_P TO SECOND_P						{ $$ = MASK(DAY) | MASK(HOUR) | MASK(MINUTE) | MASK(SECOND); }
		| HOUR_P TO MINUTE_P					{ $$ = MASK(HOUR) | MASK(MINUTE); }
		| HOUR_P TO SECOND_P					{ $$ = MASK(HOUR) | MASK(MINUTE) | MASK(SECOND); }
		| MINUTE_P TO SECOND_P					{ $$ = MASK(MINUTE) | MASK(SECOND); }
		| /*EMPTY*/								{ $$ = -1; }
		;


/*****************************************************************************
 *
 *	expression grammar
 *
 *****************************************************************************/

/* Expressions using row descriptors
 * Define row_descriptor to allow yacc to break the reduce/reduce conflict
 *  with singleton expressions.
 */
row_expr: '(' row_descriptor ')' IN select_with_parens
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = $2;
					n->oper = (List *) makeA_Expr(OP, "=", NULL, NULL);
					n->useor = FALSE;
					n->subLinkType = ANY_SUBLINK;
					n->subselect = $5;
					$$ = (Node *)n;
				}
		| '(' row_descriptor ')' NOT IN select_with_parens
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = $2;
					n->oper = (List *) makeA_Expr(OP, "<>", NULL, NULL);
					n->useor = TRUE;
					n->subLinkType = ALL_SUBLINK;
					n->subselect = $6;
					$$ = (Node *)n;
				}
		| '(' row_descriptor ')' all_Op sub_type select_with_parens
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = $2;
					n->oper = (List *) makeA_Expr(OP, $4, NULL, NULL);
					if (strcmp($4, "<>") == 0)
						n->useor = TRUE;
					else
						n->useor = FALSE;
					n->subLinkType = $5;
					n->subselect = $6;
					$$ = (Node *)n;
				}
		| '(' row_descriptor ')' all_Op select_with_parens
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = $2;
					n->oper = (List *) makeA_Expr(OP, $4, NULL, NULL);
					if (strcmp($4, "<>") == 0)
						n->useor = TRUE;
					else
						n->useor = FALSE;
					n->subLinkType = MULTIEXPR_SUBLINK;
					n->subselect = $5;
					$$ = (Node *)n;
				}
		| '(' row_descriptor ')' all_Op '(' row_descriptor ')'
				{
					$$ = makeRowExpr($4, $2, $6);
				}
		| '(' row_descriptor ')' OVERLAPS '(' row_descriptor ')'
				{
					FuncCall *n = makeNode(FuncCall);
					List *largs = $2;
					List *rargs = $6;
					n->funcname = xlateSqlFunc("overlaps");
					if (length(largs) == 1)
						largs = lappend(largs, $2);
					else if (length(largs) != 2)
						elog(ERROR, "Wrong number of parameters"
							 " on left side of OVERLAPS expression");
					if (length(rargs) == 1)
						rargs = lappend(rargs, $6);
					else if (length(rargs) != 2)
						elog(ERROR, "Wrong number of parameters"
							 " on right side of OVERLAPS expression");
					n->args = nconc(largs, rargs);
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		;

row_descriptor:  row_list ',' a_expr
				{
					$$ = lappend($1, $3);
				}
		;

row_list:  row_list ',' a_expr
				{
					$$ = lappend($1, $3);
				}
		| a_expr
				{
					$$ = makeList1($1);
				}
		;

sub_type:  ANY								{ $$ = ANY_SUBLINK; }
		| SOME								{ $$ = ANY_SUBLINK; }
		| ALL								{ $$ = ALL_SUBLINK; }
		;

all_Op:  Op | MathOp;

MathOp:  '+'			{ $$ = "+"; }
		| '-'			{ $$ = "-"; }
		| '*'			{ $$ = "*"; }
		| '/'			{ $$ = "/"; }
		| '%'			{ $$ = "%"; }
		| '^'			{ $$ = "^"; }
		| '<'			{ $$ = "<"; }
		| '>'			{ $$ = ">"; }
		| '='			{ $$ = "="; }
		;

/*
 * General expressions
 * This is the heart of the expression syntax.
 *
 * We have two expression types: a_expr is the unrestricted kind, and
 * b_expr is a subset that must be used in some places to avoid shift/reduce
 * conflicts.  For example, we can't do BETWEEN as "BETWEEN a_expr AND a_expr"
 * because that use of AND conflicts with AND as a boolean operator.  So,
 * b_expr is used in BETWEEN and we remove boolean keywords from b_expr.
 *
 * Note that '(' a_expr ')' is a b_expr, so an unrestricted expression can
 * always be used by surrounding it with parens.
 *
 * c_expr is all the productions that are common to a_expr and b_expr;
 * it's factored out just to eliminate redundant coding.
 */
a_expr:  c_expr
				{	$$ = $1;  }
		| a_expr TYPECAST Typename
				{	$$ = makeTypeCast($1, $3); }
		| a_expr AT TIME ZONE c_expr
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "timezone";
					n->args = makeList2($5, $1);
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *) n;
				}
		/*
		 * These operators must be called out explicitly in order to make use
		 * of yacc/bison's automatic operator-precedence handling.  All other
		 * operator names are handled by the generic productions using "Op",
		 * below; and all those operators will have the same precedence.
		 *
		 * If you add more explicitly-known operators, be sure to add them
		 * also to b_expr and to the MathOp list above.
		 */
		| '+' a_expr					%prec UMINUS
				{	$$ = makeA_Expr(OP, "+", NULL, $2); }
		| '-' a_expr					%prec UMINUS
				{	$$ = doNegate($2); }
		| '%' a_expr
				{	$$ = makeA_Expr(OP, "%", NULL, $2); }
		| '^' a_expr
				{	$$ = makeA_Expr(OP, "^", NULL, $2); }
		| a_expr '%'
				{	$$ = makeA_Expr(OP, "%", $1, NULL); }
		| a_expr '^'
				{	$$ = makeA_Expr(OP, "^", $1, NULL); }
		| a_expr '+' a_expr
				{	$$ = makeA_Expr(OP, "+", $1, $3); }
		| a_expr '-' a_expr
				{	$$ = makeA_Expr(OP, "-", $1, $3); }
		| a_expr '*' a_expr
				{	$$ = makeA_Expr(OP, "*", $1, $3); }
		| a_expr '/' a_expr
				{	$$ = makeA_Expr(OP, "/", $1, $3); }
		| a_expr '%' a_expr
				{	$$ = makeA_Expr(OP, "%", $1, $3); }
		| a_expr '^' a_expr
				{	$$ = makeA_Expr(OP, "^", $1, $3); }
		| a_expr '<' a_expr
				{	$$ = makeA_Expr(OP, "<", $1, $3); }
		| a_expr '>' a_expr
				{	$$ = makeA_Expr(OP, ">", $1, $3); }
		| a_expr '=' a_expr
				{	$$ = makeA_Expr(OP, "=", $1, $3); }

		| a_expr Op a_expr
				{	$$ = makeA_Expr(OP, $2, $1, $3); }
		| Op a_expr
				{	$$ = makeA_Expr(OP, $1, NULL, $2); }
		| a_expr Op					%prec POSTFIXOP
				{	$$ = makeA_Expr(OP, $2, $1, NULL); }

		| a_expr AND a_expr
				{	$$ = makeA_Expr(AND, NULL, $1, $3); }
		| a_expr OR a_expr
				{	$$ = makeA_Expr(OR, NULL, $1, $3); }
		| NOT a_expr
				{	$$ = makeA_Expr(NOT, NULL, NULL, $2); }

		| a_expr LIKE a_expr
				{	$$ = makeA_Expr(OP, "~~", $1, $3); }
		| a_expr LIKE a_expr ESCAPE a_expr
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "like_escape";
					n->args = makeList2($3, $5);
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = makeA_Expr(OP, "~~", $1, (Node *) n);
				}
		| a_expr NOT LIKE a_expr
				{	$$ = makeA_Expr(OP, "!~~", $1, $4); }
		| a_expr NOT LIKE a_expr ESCAPE a_expr
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "like_escape";
					n->args = makeList2($4, $6);
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = makeA_Expr(OP, "!~~", $1, (Node *) n);
				}
		| a_expr ILIKE a_expr
				{	$$ = makeA_Expr(OP, "~~*", $1, $3); }
		| a_expr ILIKE a_expr ESCAPE a_expr
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "like_escape";
					n->args = makeList2($3, $5);
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = makeA_Expr(OP, "~~*", $1, (Node *) n);
				}
		| a_expr NOT ILIKE a_expr
				{	$$ = makeA_Expr(OP, "!~~*", $1, $4); }
		| a_expr NOT ILIKE a_expr ESCAPE a_expr
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "like_escape";
					n->args = makeList2($4, $6);
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = makeA_Expr(OP, "!~~*", $1, (Node *) n);
				}
		/* NullTest clause
		 * Define SQL92-style Null test clause.
		 * Allow two forms described in the standard:
		 *  a IS NULL
		 *  a IS NOT NULL
		 * Allow two SQL extensions
		 *  a ISNULL
		 *  a NOTNULL
		 * NOTE: this is not yet fully SQL-compatible, since SQL92
		 * allows a row constructor as argument, not just a scalar.
		 */
		| a_expr ISNULL
				{
					NullTest *n = makeNode(NullTest);
					n->arg = $1;
					n->nulltesttype = IS_NULL;
					$$ = (Node *)n;
				}
		| a_expr IS NULL_P
				{
					NullTest *n = makeNode(NullTest);
					n->arg = $1;
					n->nulltesttype = IS_NULL;
					$$ = (Node *)n;
				}
		| a_expr NOTNULL
				{
					NullTest *n = makeNode(NullTest);
					n->arg = $1;
					n->nulltesttype = IS_NOT_NULL;
					$$ = (Node *)n;
				}
		| a_expr IS NOT NULL_P
				{
					NullTest *n = makeNode(NullTest);
					n->arg = $1;
					n->nulltesttype = IS_NOT_NULL;
					$$ = (Node *)n;
				}
		/* IS TRUE, IS FALSE, etc used to be function calls
		 *  but let's make them expressions to allow the optimizer
		 *  a chance to eliminate them if a_expr is a constant string.
		 * - thomas 1997-12-22
		 *
		 *  Created BooleanTest Node type, and changed handling
		 *  for NULL inputs
		 * - jec 2001-06-18
		 */
		| a_expr IS TRUE_P
				{
					BooleanTest *b = makeNode(BooleanTest);
					b->arg = $1;
					b->booltesttype = IS_TRUE;
					$$ = (Node *)b;
				}
		| a_expr IS NOT TRUE_P
				{
					BooleanTest *b = makeNode(BooleanTest);
					b->arg = $1;
					b->booltesttype = IS_NOT_TRUE;
					$$ = (Node *)b;
				}
		| a_expr IS FALSE_P
				{
					BooleanTest *b = makeNode(BooleanTest);
					b->arg = $1;
					b->booltesttype = IS_FALSE;
					$$ = (Node *)b;
				}
		| a_expr IS NOT FALSE_P
				{
					BooleanTest *b = makeNode(BooleanTest);
					b->arg = $1;
					b->booltesttype = IS_NOT_FALSE;
					$$ = (Node *)b;
				}
		| a_expr IS UNKNOWN
				{
					BooleanTest *b = makeNode(BooleanTest);
					b->arg = $1;
					b->booltesttype = IS_UNKNOWN;
					$$ = (Node *)b;
				}
		| a_expr IS NOT UNKNOWN
				{
					BooleanTest *b = makeNode(BooleanTest);
					b->arg = $1;
					b->booltesttype = IS_NOT_UNKNOWN;
					$$ = (Node *)b;
				}
		| a_expr BETWEEN b_expr AND b_expr			%prec BETWEEN
				{
					$$ = makeA_Expr(AND, NULL,
						makeA_Expr(OP, ">=", $1, $3),
						makeA_Expr(OP, "<=", $1, $5));
				}
		| a_expr NOT BETWEEN b_expr AND b_expr		%prec BETWEEN
				{
					$$ = makeA_Expr(OR, NULL,
						makeA_Expr(OP, "<", $1, $4),
						makeA_Expr(OP, ">", $1, $6));
				}
		| a_expr IN in_expr
				{
					/* in_expr returns a SubLink or a list of a_exprs */
					if (IsA($3, SubLink))
					{
							SubLink *n = (SubLink *)$3;
							n->lefthand = makeList1($1);
							n->oper = (List *) makeA_Expr(OP, "=", NULL, NULL);
							n->useor = FALSE;
							n->subLinkType = ANY_SUBLINK;
							$$ = (Node *)n;
					}
					else
					{
						Node *n = NULL;
						List *l;
						foreach(l, (List *) $3)
						{
							Node *cmp = makeA_Expr(OP, "=", $1, lfirst(l));
							if (n == NULL)
								n = cmp;
							else
								n = makeA_Expr(OR, NULL, n, cmp);
						}
						$$ = n;
					}
				}
		| a_expr NOT IN in_expr
				{
					/* in_expr returns a SubLink or a list of a_exprs */
					if (IsA($4, SubLink))
					{
						SubLink *n = (SubLink *)$4;
						n->lefthand = makeList1($1);
						n->oper = (List *) makeA_Expr(OP, "<>", NULL, NULL);
						n->useor = FALSE;
						n->subLinkType = ALL_SUBLINK;
						$$ = (Node *)n;
					}
					else
					{
						Node *n = NULL;
						List *l;
						foreach(l, (List *) $4)
						{
							Node *cmp = makeA_Expr(OP, "<>", $1, lfirst(l));
							if (n == NULL)
								n = cmp;
							else
								n = makeA_Expr(AND, NULL, n, cmp);
						}
						$$ = n;
					}
				}
		| a_expr all_Op sub_type select_with_parens		%prec Op
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = makeList1($1);
					n->oper = (List *) makeA_Expr(OP, $2, NULL, NULL);
					n->useor = FALSE; /* doesn't matter since only one col */
					n->subLinkType = $3;
					n->subselect = $4;
					$$ = (Node *)n;
				}
		| row_expr
				{	$$ = $1;  }
		;

/*
 * Restricted expressions
 *
 * b_expr is a subset of the complete expression syntax defined by a_expr.
 *
 * Presently, AND, NOT, IS, and IN are the a_expr keywords that would
 * cause trouble in the places where b_expr is used.  For simplicity, we
 * just eliminate all the boolean-keyword-operator productions from b_expr.
 */
b_expr:  c_expr
				{	$$ = $1;  }
		| b_expr TYPECAST Typename
				{	$$ = makeTypeCast($1, $3); }
		| '+' b_expr					%prec UMINUS
				{	$$ = makeA_Expr(OP, "+", NULL, $2); }
		| '-' b_expr					%prec UMINUS
				{	$$ = doNegate($2); }
		| '%' b_expr
				{	$$ = makeA_Expr(OP, "%", NULL, $2); }
		| '^' b_expr
				{	$$ = makeA_Expr(OP, "^", NULL, $2); }
		| b_expr '%'
				{	$$ = makeA_Expr(OP, "%", $1, NULL); }
		| b_expr '^'
				{	$$ = makeA_Expr(OP, "^", $1, NULL); }
		| b_expr '+' b_expr
				{	$$ = makeA_Expr(OP, "+", $1, $3); }
		| b_expr '-' b_expr
				{	$$ = makeA_Expr(OP, "-", $1, $3); }
		| b_expr '*' b_expr
				{	$$ = makeA_Expr(OP, "*", $1, $3); }
		| b_expr '/' b_expr
				{	$$ = makeA_Expr(OP, "/", $1, $3); }
		| b_expr '%' b_expr
				{	$$ = makeA_Expr(OP, "%", $1, $3); }
		| b_expr '^' b_expr
				{	$$ = makeA_Expr(OP, "^", $1, $3); }
		| b_expr '<' b_expr
				{	$$ = makeA_Expr(OP, "<", $1, $3); }
		| b_expr '>' b_expr
				{	$$ = makeA_Expr(OP, ">", $1, $3); }
		| b_expr '=' b_expr
				{	$$ = makeA_Expr(OP, "=", $1, $3); }

		| b_expr Op b_expr
				{	$$ = makeA_Expr(OP, $2, $1, $3); }
		| Op b_expr
				{	$$ = makeA_Expr(OP, $1, NULL, $2); }
		| b_expr Op					%prec POSTFIXOP
				{	$$ = makeA_Expr(OP, $2, $1, NULL); }
		;

/*
 * Productions that can be used in both a_expr and b_expr.
 *
 * Note: productions that refer recursively to a_expr or b_expr mostly
 * cannot appear here.  However, it's OK to refer to a_exprs that occur
 * inside parentheses, such as function arguments; that cannot introduce
 * ambiguity to the b_expr syntax.
 */
c_expr:  columnref
				{	$$ = (Node *) $1;  }
		| AexprConst
				{	$$ = $1;  }
		| PARAM attrs opt_indirection
				{
					/*
					 * PARAM without field names is considered a constant,
					 * but with 'em, it is not.  Not very consistent ...
					 */
					ParamRef *n = makeNode(ParamRef);
					n->number = $1;
					n->fields = $2;
					n->indirection = $3;
					$$ = (Node *)n;
				}
		| '(' a_expr ')'
				{	$$ = $2; }
		| '(' a_expr ')' attrs opt_indirection
				{
					ExprFieldSelect *n = makeNode(ExprFieldSelect);
					n->arg = $2;
					n->fields = $4;
					n->indirection = $5;
					$$ = (Node *)n;
				}
		| CAST '(' a_expr AS Typename ')'
				{	$$ = makeTypeCast($3, $5); }
		| case_expr
				{	$$ = $1; }
		| func_name '(' ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = $1;
					n->args = NIL;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| func_name '(' expr_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = $1;
					n->args = $3;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| func_name '(' ALL expr_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = $1;
					n->args = $4;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					/* Ideally we'd mark the FuncCall node to indicate
					 * "must be an aggregate", but there's no provision
					 * for that in FuncCall at the moment.
					 */
					$$ = (Node *)n;
				}
		| func_name '(' DISTINCT expr_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = $1;
					n->args = $4;
					n->agg_star = FALSE;
					n->agg_distinct = TRUE;
					$$ = (Node *)n;
				}
		| func_name '(' '*' ')'
				{
					/*
					 * For now, we transform AGGREGATE(*) into AGGREGATE(1).
					 *
					 * This does the right thing for COUNT(*) (in fact,
					 * any certainly-non-null expression would do for COUNT),
					 * and there are no other aggregates in SQL92 that accept
					 * '*' as parameter.
					 *
					 * The FuncCall node is also marked agg_star = true,
					 * so that later processing can detect what the argument
					 * really was.
					 */
					FuncCall *n = makeNode(FuncCall);
					A_Const *star = makeNode(A_Const);

					star->val.type = T_Integer;
					star->val.val.ival = 1;
					n->funcname = $1;
					n->args = makeList1(star);
					n->agg_star = TRUE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| CURRENT_DATE opt_empty_parentheses
				{
					/*
					 * Translate as "date('now'::text)".
					 *
					 * We cannot use "'now'::date" because coerce_type() will
					 * immediately reduce that to a constant representing
					 * today's date.  We need to delay the conversion until
					 * runtime, else the wrong things will happen when
					 * CURRENT_DATE is used in a column default value or rule.
					 *
					 * This could be simplified if we had a way to generate
					 * an expression tree representing runtime application
					 * of type-input conversion functions...
					 */
					A_Const *s = makeNode(A_Const);
					TypeName *t = makeNode(TypeName);
					TypeName *d = makeNode(TypeName);

					s->val.type = T_String;
					s->val.val.str = "now";
					s->typename = t;

					t->name = xlateSqlType("text");
					t->setof = FALSE;
					t->typmod = -1;

					d->name = xlateSqlType("date");
					d->setof = FALSE;
					d->typmod = -1;

					$$ = (Node *)makeTypeCast((Node *)s, d);
				}
		| CURRENT_TIME opt_empty_parentheses
				{
					/*
					 * Translate as "timetz('now'::text)".
					 * See comments for CURRENT_DATE.
					 */
					A_Const *s = makeNode(A_Const);
					TypeName *t = makeNode(TypeName);
					TypeName *d = makeNode(TypeName);

					s->val.type = T_String;
					s->val.val.str = "now";
					s->typename = t;

					t->name = xlateSqlType("text");
					t->setof = FALSE;
					t->typmod = -1;

					d->name = xlateSqlType("timetz");
					d->setof = FALSE;
					/* SQL99 mandates a default precision of zero for TIME
					 * fields in schemas. However, for CURRENT_TIME
					 * let's preserve the microsecond precision we
					 * might see from the system clock. - thomas 2001-12-07
					 */
					d->typmod = 6;

					$$ = (Node *)makeTypeCast((Node *)s, d);
				}
		| CURRENT_TIME '(' Iconst ')'
				{
					/*
					 * Translate as "timetz('now'::text)".
					 * See comments for CURRENT_DATE.
					 */
					A_Const *s = makeNode(A_Const);
					TypeName *t = makeNode(TypeName);
					TypeName *d = makeNode(TypeName);

					s->val.type = T_String;
					s->val.val.str = "now";
					s->typename = t;

					t->name = xlateSqlType("text");
					t->setof = FALSE;
					t->typmod = -1;

					d->name = xlateSqlType("timetz");
					d->setof = FALSE;
					if (($3 < 0) || ($3 > 13))
						elog(ERROR,"CURRENT_TIME(%d) precision must be between %d and %d",
							 $3, 0, 13);
					d->typmod = $3;

					$$ = (Node *)makeTypeCast((Node *)s, d);
				}
		| CURRENT_TIMESTAMP opt_empty_parentheses
				{
					/*
					 * Translate as "timestamptz('now'::text)".
					 * See comments for CURRENT_DATE.
					 */
					A_Const *s = makeNode(A_Const);
					TypeName *t = makeNode(TypeName);
					TypeName *d = makeNode(TypeName);

					s->val.type = T_String;
					s->val.val.str = "now";
					s->typename = t;

					t->name = xlateSqlType("text");
					t->setof = FALSE;
					t->typmod = -1;

					d->name = xlateSqlType("timestamptz");
					d->setof = FALSE;
					/* SQL99 mandates a default precision of 6 for timestamp.
					 * Also, that is about as precise as we will get since
					 * we are using a microsecond time interface.
					 * - thomas 2001-12-07
					 */
					d->typmod = 6;

					$$ = (Node *)makeTypeCast((Node *)s, d);
				}
		| CURRENT_TIMESTAMP '(' Iconst ')'
				{
					/*
					 * Translate as "timestamptz('now'::text)".
					 * See comments for CURRENT_DATE.
					 */
					A_Const *s = makeNode(A_Const);
					TypeName *t = makeNode(TypeName);
					TypeName *d = makeNode(TypeName);

					s->val.type = T_String;
					s->val.val.str = "now";
					s->typename = t;

					t->name = xlateSqlType("text");
					t->setof = FALSE;
					t->typmod = -1;

					d->name = xlateSqlType("timestamptz");
					d->setof = FALSE;
					if (($3 < 0) || ($3 > 13))
						elog(ERROR,"CURRENT_TIMESTAMP(%d) precision must be between %d and %d",
							 $3, 0, 13);
					d->typmod = $3;

					$$ = (Node *)makeTypeCast((Node *)s, d);
				}
		| CURRENT_USER opt_empty_parentheses
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "current_user";
					n->args = NIL;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| SESSION_USER opt_empty_parentheses
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "session_user";
					n->args = NIL;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| USER opt_empty_parentheses
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "current_user";
					n->args = NIL;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| EXTRACT '(' extract_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "date_part";
					n->args = $3;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| POSITION '(' position_list ')'
				{
					/* position(A in B) is converted to position(B, A) */
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "position";
					n->args = $3;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| SUBSTRING '(' substr_list ')'
				{
					/* substring(A from B for C) is converted to
					 * substring(A, B, C) - thomas 2000-11-28
					 */
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "substring";
					n->args = $3;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| TRIM '(' BOTH trim_list ')'
				{
					/* various trim expressions are defined in SQL92
					 * - thomas 1997-07-19
					 */
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "btrim";
					n->args = $4;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| TRIM '(' LEADING trim_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "ltrim";
					n->args = $4;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| TRIM '(' TRAILING trim_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "rtrim";
					n->args = $4;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| TRIM '(' trim_list ')'
				{
					FuncCall *n = makeNode(FuncCall);
					n->funcname = "btrim";
					n->args = $3;
					n->agg_star = FALSE;
					n->agg_distinct = FALSE;
					$$ = (Node *)n;
				}
		| select_with_parens			%prec UMINUS
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = NIL;
					n->oper = NIL;
					n->useor = FALSE;
					n->subLinkType = EXPR_SUBLINK;
					n->subselect = $1;
					$$ = (Node *)n;
				}
		| EXISTS select_with_parens
				{
					SubLink *n = makeNode(SubLink);
					n->lefthand = NIL;
					n->oper = NIL;
					n->useor = FALSE;
					n->subLinkType = EXISTS_SUBLINK;
					n->subselect = $2;
					$$ = (Node *)n;
				}
		;

/*
 * Supporting nonterminals for expressions.
 */

opt_indirection:	opt_indirection '[' a_expr ']'
				{
					A_Indices *ai = makeNode(A_Indices);
					ai->lidx = NULL;
					ai->uidx = $3;
					$$ = lappend($1, ai);
				}
		| opt_indirection '[' a_expr ':' a_expr ']'
				{
					A_Indices *ai = makeNode(A_Indices);
					ai->lidx = $3;
					ai->uidx = $5;
					$$ = lappend($1, ai);
				}
		| /*EMPTY*/
				{	$$ = NIL; }
		;

expr_list:  a_expr
				{ $$ = makeList1($1); }
		| expr_list ',' a_expr
				{ $$ = lappend($1, $3); }
		| expr_list USING a_expr
				{ $$ = lappend($1, $3); }
		;

extract_list:  extract_arg FROM a_expr
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_String;
					n->val.val.str = $1;
					$$ = makeList2((Node *) n, $3);
				}
		| /*EMPTY*/
				{	$$ = NIL; }
		;

/* Allow delimited string SCONST in extract_arg as an SQL extension.
 * - thomas 2001-04-12
 */

extract_arg:  IDENT						{ $$ = $1; }
		| YEAR_P						{ $$ = "year"; }
		| MONTH_P						{ $$ = "month"; }
		| DAY_P							{ $$ = "day"; }
		| HOUR_P						{ $$ = "hour"; }
		| MINUTE_P						{ $$ = "minute"; }
		| SECOND_P						{ $$ = "second"; }
		| SCONST						{ $$ = $1; }
		;

/* position_list uses b_expr not a_expr to avoid conflict with general IN */

position_list:  b_expr IN b_expr
				{	$$ = makeList2($3, $1); }
		| /*EMPTY*/
				{	$$ = NIL; }
		;

/* SUBSTRING() arguments
 * SQL9x defines a specific syntax for arguments to SUBSTRING():
 * o substring(text from int for int)
 * o substring(text from int) get entire string from starting point "int"
 * o substring(text for int) get first "int" characters of string
 * We also want to implement generic substring functions which accept
 * the usual generic list of arguments. So we will accept both styles
 * here, and convert the SQL9x style to the generic list for further
 * processing. - thomas 2000-11-28
 */
substr_list:  a_expr substr_from substr_for
				{
					$$ = makeList3($1, $2, $3);
				}
		| a_expr substr_for substr_from
				{
					$$ = makeList3($1, $3, $2);
				}
		| a_expr substr_from
				{
					$$ = makeList2($1, $2);
				}
		| a_expr substr_for
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_Integer;
					n->val.val.ival = 1;
					$$ = makeList3($1, (Node *)n, $2);
				}
		| expr_list
				{
					$$ = $1;
				}
		| /*EMPTY*/
				{	$$ = NIL; }
		;

substr_from:  FROM a_expr
				{	$$ = $2; }
		;

substr_for:  FOR a_expr
				{	$$ = $2; }
		;

trim_list:  a_expr FROM expr_list
				{ $$ = lappend($3, $1); }
		| FROM expr_list
				{ $$ = $2; }
		| expr_list
				{ $$ = $1; }
		;

in_expr:  select_with_parens
				{
					SubLink *n = makeNode(SubLink);
					n->subselect = $1;
					$$ = (Node *)n;
				}
		| '(' in_expr_nodes ')'
				{	$$ = (Node *)$2; }
		;

in_expr_nodes:  a_expr
				{	$$ = makeList1($1); }
		| in_expr_nodes ',' a_expr
				{	$$ = lappend($1, $3); }
		;

/* Case clause
 * Define SQL92-style case clause.
 * Allow all four forms described in the standard:
 * - Full specification
 *  CASE WHEN a = b THEN c ... ELSE d END
 * - Implicit argument
 *  CASE a WHEN b THEN c ... ELSE d END
 * - Conditional NULL
 *  NULLIF(x,y)
 *  same as CASE WHEN x = y THEN NULL ELSE x END
 * - Conditional substitution from list, use first non-null argument
 *  COALESCE(a,b,...)
 * same as CASE WHEN a IS NOT NULL THEN a WHEN b IS NOT NULL THEN b ... END
 * - thomas 1998-11-09
 */
case_expr:  CASE case_arg when_clause_list case_default END_TRANS
				{
					CaseExpr *c = makeNode(CaseExpr);
					c->arg = $2;
					c->args = $3;
					c->defresult = $4;
					$$ = (Node *)c;
				}
		| NULLIF '(' a_expr ',' a_expr ')'
				{
					CaseExpr *c = makeNode(CaseExpr);
					CaseWhen *w = makeNode(CaseWhen);
/*
					A_Const *n = makeNode(A_Const);
					n->val.type = T_Null;
					w->result = (Node *)n;
*/
					w->expr = makeA_Expr(OP, "=", $3, $5);
					c->args = makeList1(w);
					c->defresult = $3;
					$$ = (Node *)c;
				}
		| COALESCE '(' expr_list ')'
				{
					CaseExpr *c = makeNode(CaseExpr);
					List *l;
					foreach (l,$3)
					{
						CaseWhen *w = makeNode(CaseWhen);
						NullTest *n = makeNode(NullTest);
						n->arg = lfirst(l);
						n->nulltesttype = IS_NOT_NULL;
						w->expr = (Node *) n;
						w->result = lfirst(l);
						c->args = lappend(c->args, w);
					}
					$$ = (Node *)c;
				}
		;

when_clause_list:  when_clause_list when_clause
				{ $$ = lappend($1, $2); }
		| when_clause
				{ $$ = makeList1($1); }
		;

when_clause:  WHEN a_expr THEN a_expr
				{
					CaseWhen *w = makeNode(CaseWhen);
					w->expr = $2;
					w->result = $4;
					$$ = (Node *)w;
				}
		;

case_default:  ELSE a_expr						{ $$ = $2; }
		| /*EMPTY*/								{ $$ = NULL; }
		;

case_arg:  a_expr
				{	$$ = $1; }
		| /*EMPTY*/
				{	$$ = NULL; }
		;

/*
 * columnref starts with relation_name not ColId, so that OLD and NEW
 * references can be accepted.  Note that when there are more than two
 * dotted names, the first name is not actually a relation name...
 */
columnref: relation_name opt_indirection
				{
					$$ = makeNode(ColumnRef);
					$$->fields = makeList1(makeString($1));
					$$->indirection = $2;
				}
		| relation_name attrs opt_indirection
				{
					$$ = makeNode(ColumnRef);
					$$->fields = lcons(makeString($1), $2);
					$$->indirection = $3;
				}
		;

attrs:	  opt_attrs '.' attr_name
				{ $$ = lappend($1, makeString($3)); }
		| opt_attrs '.' '*'
				{ $$ = lappend($1, makeString("*")); }
		;

opt_attrs: /*EMPTY*/
				{ $$ = NIL; }
		| opt_attrs '.' attr_name
				{ $$ = lappend($1, makeString($3)); }
		;

opt_empty_parentheses: '(' ')' { $$ = TRUE; }
					| /*EMPTY*/ { $$ = TRUE; }
		;

/*****************************************************************************
 *
 *	target lists
 *
 *****************************************************************************/

/* Target lists as found in SELECT ... and INSERT VALUES ( ... ) */

target_list:  target_list ',' target_el
				{	$$ = lappend($1, $3);  }
		| target_el
				{	$$ = makeList1($1);  }
		;

/* AS is not optional because shift/red conflict with unary ops */
target_el:  a_expr AS ColLabel
				{
					$$ = makeNode(ResTarget);
					$$->name = $3;
					$$->indirection = NIL;
					$$->val = (Node *)$1;
				}
		| a_expr
				{
					$$ = makeNode(ResTarget);
					$$->name = NULL;
					$$->indirection = NIL;
					$$->val = (Node *)$1;
				}
		| '*'
				{
					ColumnRef *n = makeNode(ColumnRef);
					n->fields = makeList1(makeString("*"));
					n->indirection = NIL;
					$$ = makeNode(ResTarget);
					$$->name = NULL;
					$$->indirection = NIL;
					$$->val = (Node *)n;
				}
		;

/* Target list as found in UPDATE table SET ... */

update_target_list:  update_target_list ',' update_target_el
				{	$$ = lappend($1,$3);  }
		| update_target_el
				{	$$ = makeList1($1);  }
		;

update_target_el:  ColId opt_indirection '=' a_expr
				{
					$$ = makeNode(ResTarget);
					$$->name = $1;
					$$->indirection = $2;
					$$->val = (Node *)$4;
				}
		;

/*****************************************************************************
 *
 *	Names and constants
 *
 *****************************************************************************/

relation_name:	SpecialRuleRelation
				{
					$$ = $1;
				}
		| ColId
				{
					$$ = $1;
				}
		;
		
qualified_name_list:  qualified_name
				{	$$ = makeList1($1); }
		| qualified_name_list ',' qualified_name
				{	$$ = lappend($1, $3); }
		;

qualified_name: ColId
				{
					$$ = makeNode(RangeVar);
					$$->catalogname = NULL;
					$$->schemaname = NULL;
					$$->relname = $1;
				}
		| ColId '.' ColId
				{
					$$ = makeNode(RangeVar);
					$$->catalogname = NULL;
					$$->schemaname = $1;
					$$->relname = $3;
				}
		| ColId '.' ColId '.' ColId
				{
					$$ = makeNode(RangeVar);
					$$->catalogname = $1;
					$$->schemaname = $3;
					$$->relname = $5;
				}
		;

name_list:  name
				{	$$ = makeList1(makeString($1)); }
		| name_list ',' name
				{	$$ = lappend($1, makeString($3)); }
		;


name:					ColId			{ $$ = $1; };
database_name:			ColId			{ $$ = $1; };
access_method:			ColId			{ $$ = $1; };
attr_name:				ColId			{ $$ = $1; };
class:					ColId			{ $$ = $1; };
index_name:				ColId			{ $$ = $1; };
file_name:				Sconst			{ $$ = $1; };

/* Constants
 * Include TRUE/FALSE for SQL3 support. - thomas 1997-10-24
 */
AexprConst:  Iconst
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_Integer;
					n->val.val.ival = $1;
					$$ = (Node *)n;
				}
		| FCONST
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_Float;
					n->val.val.str = $1;
					$$ = (Node *)n;
				}
		| Sconst
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_String;
					n->val.val.str = $1;
					$$ = (Node *)n;
				}
		| BITCONST
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_BitString;
					n->val.val.str = $1;
					$$ = (Node *)n;
				}
		/* This rule formerly used Typename,
		 * but that causes reduce conflicts with subscripted column names.
		 * Now, separate into ConstTypename and ConstInterval,
		 * to allow implementing the SQL92 syntax for INTERVAL literals.
		 * - thomas 2000-06-24
		 */
		| ConstTypename Sconst
				{
					A_Const *n = makeNode(A_Const);
					n->typename = $1;
					n->val.type = T_String;
					n->val.val.str = $2;
					$$ = (Node *)n;
				}
		| ConstInterval Sconst opt_interval
				{
					A_Const *n = makeNode(A_Const);
					n->typename = $1;
					n->val.type = T_String;
					n->val.val.str = $2;
					/* precision is not specified, but fields may be... */
					if ($3 != -1)
						n->typename->typmod = ((($3 & 0x7FFF) << 16) | 0xFFFF);
					$$ = (Node *)n;
				}
		| ConstInterval '(' Iconst ')' Sconst opt_interval
				{
					A_Const *n = makeNode(A_Const);
					n->typename = $1;
					n->val.type = T_String;
					n->val.val.str = $5;
					/* precision specified, and fields may be... */
					n->typename->typmod = ((($6 & 0x7FFF) << 16) | $3);

					$$ = (Node *)n;
				}
		| PARAM opt_indirection
				{
					ParamRef *n = makeNode(ParamRef);
					n->number = $1;
					n->fields = NIL;
					n->indirection = $2;
					$$ = (Node *)n;
				}
		| TRUE_P
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_String;
					n->val.val.str = "t";
					n->typename = makeNode(TypeName);
					n->typename->name = xlateSqlType("bool");
					n->typename->typmod = -1;
					$$ = (Node *)n;
				}
		| FALSE_P
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_String;
					n->val.val.str = "f";
					n->typename = makeNode(TypeName);
					n->typename->name = xlateSqlType("bool");
					n->typename->typmod = -1;
					$$ = (Node *)n;
				}
		| NULL_P
				{
					A_Const *n = makeNode(A_Const);
					n->val.type = T_Null;
					$$ = (Node *)n;
				}
		;

Iconst:  ICONST							{ $$ = $1; };
Sconst:  SCONST							{ $$ = $1; };
UserId:  ColId							{ $$ = $1; };

/*
 * Name classification hierarchy.
 *
 * IDENT is the lexeme returned by the lexer for identifiers that match
 * no known keyword.  In most cases, we can accept certain keywords as
 * names, not only IDENTs.  We prefer to accept as many such keywords
 * as possible to minimize the impact of "reserved words" on programmers.
 * So, we divide names into several possible classes.  The classification
 * is chosen in part to make keywords acceptable as names wherever possible.
 */

/* Column identifier --- names that can be column, table, etc names.
 */
ColId:  IDENT							{ $$ = $1; }
		| unreserved_keyword			{ $$ = $1; }
		| col_name_keyword				{ $$ = $1; }
		;

/* Type identifier --- names that can be type names.
 */
type_name:  IDENT						{ $$ = $1; }
		| unreserved_keyword			{ $$ = $1; }
		;

/* Function identifier --- names that can be function names.
 */
func_name:  IDENT						{ $$ = xlateSqlFunc($1); }
		| unreserved_keyword			{ $$ = xlateSqlFunc($1); }
		| func_name_keyword				{ $$ = xlateSqlFunc($1); }
		;

/* Column label --- allowed labels in "AS" clauses.
 * This presently includes *all* Postgres keywords.
 */
ColLabel:  IDENT						{ $$ = $1; }
		| unreserved_keyword			{ $$ = $1; }
		| col_name_keyword				{ $$ = $1; }
		| func_name_keyword				{ $$ = $1; }
		| reserved_keyword				{ $$ = $1; }
		;


/*
 * Keyword classification lists.  Generally, every keyword present in
 * the Postgres grammar should appear in exactly one of these lists.
 *
 * Put a new keyword into the first list that it can go into without causing
 * shift or reduce conflicts.  The earlier lists define "less reserved"
 * categories of keywords.
 */

/* "Unreserved" keywords --- available for use as any kind of name.
 */
unreserved_keyword:
		  ABORT_TRANS					{ $$ = "abort"; }
		| ABSOLUTE						{ $$ = "absolute"; }
		| ACCESS						{ $$ = "access"; }
		| ACTION						{ $$ = "action"; }
		| ADD							{ $$ = "add"; }
		| AFTER							{ $$ = "after"; }
		| AGGREGATE						{ $$ = "aggregate"; }
		| ALTER							{ $$ = "alter"; }
		| AT							{ $$ = "at"; }
		| BACKWARD						{ $$ = "backward"; }
		| BEFORE						{ $$ = "before"; }
		| BEGIN_TRANS					{ $$ = "begin"; }
		| BY							{ $$ = "by"; }
		| CACHE							{ $$ = "cache"; }
		| CASCADE						{ $$ = "cascade"; }
		| CHAIN							{ $$ = "chain"; }
		| CHARACTERISTICS				{ $$ = "characteristics"; }
		| CHECKPOINT					{ $$ = "checkpoint"; }
		| CLOSE							{ $$ = "close"; }
		| CLUSTER						{ $$ = "cluster"; }
		| COMMENT						{ $$ = "comment"; }
		| COMMIT						{ $$ = "commit"; }
		| COMMITTED						{ $$ = "committed"; }
		| CONSTRAINTS					{ $$ = "constraints"; }
		| COPY							{ $$ = "copy"; }
		| CREATEDB						{ $$ = "createdb"; }
		| CREATEUSER					{ $$ = "createuser"; }
		| CURSOR						{ $$ = "cursor"; }
		| CYCLE							{ $$ = "cycle"; }
		| DATABASE						{ $$ = "database"; }
		| DAY_P							{ $$ = "day"; }
		| DECLARE						{ $$ = "declare"; }
		| DEFERRED						{ $$ = "deferred"; }
		| DELETE						{ $$ = "delete"; }
		| DELIMITERS					{ $$ = "delimiters"; }
		| DOMAIN_P						{ $$ = "domain"; }
		| DOUBLE						{ $$ = "double"; }
		| DROP							{ $$ = "drop"; }
		| EACH							{ $$ = "each"; }
		| ENCODING						{ $$ = "encoding"; }
		| ENCRYPTED						{ $$ = "encrypted"; }
		| ESCAPE						{ $$ = "escape"; }
		| EXCLUSIVE						{ $$ = "exclusive"; }
		| EXECUTE						{ $$ = "execute"; }
		| EXPLAIN						{ $$ = "explain"; }
		| FETCH							{ $$ = "fetch"; }
		| FORCE							{ $$ = "force"; }
		| FORWARD						{ $$ = "forward"; }
		| FUNCTION						{ $$ = "function"; }
		| GLOBAL						{ $$ = "global"; }
		| HANDLER						{ $$ = "handler"; }
		| HOUR_P						{ $$ = "hour"; }
		| IMMEDIATE						{ $$ = "immediate"; }
		| INCREMENT						{ $$ = "increment"; }
		| INDEX							{ $$ = "index"; }
		| INHERITS						{ $$ = "inherits"; }
		| INOUT							{ $$ = "inout"; }
		| INSENSITIVE					{ $$ = "insensitive"; }
		| INSERT						{ $$ = "insert"; }
		| INSTEAD						{ $$ = "instead"; }
		| ISOLATION						{ $$ = "isolation"; }
		| KEY							{ $$ = "key"; }
		| LANGUAGE						{ $$ = "language"; }
		| LANCOMPILER					{ $$ = "lancompiler"; }
		| LEVEL							{ $$ = "level"; }
		| LISTEN						{ $$ = "listen"; }
		| LOAD							{ $$ = "load"; }
		| LOCAL							{ $$ = "local"; }
		| LOCATION						{ $$ = "location"; }
		| LOCK_P						{ $$ = "lock"; }
		| MATCH							{ $$ = "match"; }
		| MAXVALUE						{ $$ = "maxvalue"; }
		| MINUTE_P						{ $$ = "minute"; }
		| MINVALUE						{ $$ = "minvalue"; }
		| MODE							{ $$ = "mode"; }
		| MONTH_P						{ $$ = "month"; }
		| MOVE							{ $$ = "move"; }
		| NAMES							{ $$ = "names"; }
		| NATIONAL						{ $$ = "national"; }
		| NEXT							{ $$ = "next"; }
		| NO							{ $$ = "no"; }
		| NOCREATEDB					{ $$ = "nocreatedb"; }
		| NOCREATEUSER					{ $$ = "nocreateuser"; }
		| NOTHING						{ $$ = "nothing"; }
		| NOTIFY						{ $$ = "notify"; }
		| OF							{ $$ = "of"; }
		| OIDS							{ $$ = "oids"; }
		| OPERATOR						{ $$ = "operator"; }
		| OPTION						{ $$ = "option"; }
		| OUT							{ $$ = "out"; }
		| OWNER							{ $$ = "owner"; }
		| PARTIAL						{ $$ = "partial"; }
		| PASSWORD						{ $$ = "password"; }
		| PATH_P						{ $$ = "path"; }
		| PENDANT						{ $$ = "pendant"; }
		| PRECISION						{ $$ = "precision"; }
		| PRIOR							{ $$ = "prior"; }
		| PRIVILEGES					{ $$ = "privileges"; }
		| PROCEDURAL					{ $$ = "procedural"; }
		| PROCEDURE						{ $$ = "procedure"; }
		| READ							{ $$ = "read"; }
		| REINDEX						{ $$ = "reindex"; }
		| RELATIVE						{ $$ = "relative"; }
		| RENAME						{ $$ = "rename"; }
		| REPLACE						{ $$ = "replace"; }
		| RESET							{ $$ = "reset"; }
		| RESTRICT						{ $$ = "restrict"; }
		| RETURNS						{ $$ = "returns"; }
		| REVOKE						{ $$ = "revoke"; }
		| ROLLBACK						{ $$ = "rollback"; }
		| ROW							{ $$ = "row"; }
		| RULE							{ $$ = "rule"; }
		| SCHEMA						{ $$ = "schema"; }
		| SCROLL						{ $$ = "scroll"; }
		| SECOND_P						{ $$ = "second"; }
		| SESSION						{ $$ = "session"; }
		| SEQUENCE						{ $$ = "sequence"; }
		| SERIALIZABLE					{ $$ = "serializable"; }
		| SET							{ $$ = "set"; }
		| SHARE							{ $$ = "share"; }
		| SHOW							{ $$ = "show"; }
		| START							{ $$ = "start"; }
		| STATEMENT						{ $$ = "statement"; }
		| STATISTICS					{ $$ = "statistics"; }
		| STDIN							{ $$ = "stdin"; }
		| STDOUT						{ $$ = "stdout"; }
        | STORAGE                       { $$ = "storage"; }
		| SYSID							{ $$ = "sysid"; }
		| TEMP							{ $$ = "temp"; }
		| TEMPLATE						{ $$ = "template"; }
		| TEMPORARY						{ $$ = "temporary"; }
		| TOAST							{ $$ = "toast"; }
		| TRANSACTION					{ $$ = "transaction"; }
		| TRIGGER						{ $$ = "trigger"; }
		| TRUNCATE						{ $$ = "truncate"; }
		| TRUSTED						{ $$ = "trusted"; }
		| TYPE_P						{ $$ = "type"; }
		| UNENCRYPTED					{ $$ = "unencrypted"; }
		| UNKNOWN						{ $$ = "unknown"; }
		| UNLISTEN						{ $$ = "unlisten"; }
		| UNTIL							{ $$ = "until"; }
		| UPDATE						{ $$ = "update"; }
		| USAGE							{ $$ = "usage"; }
		| VACUUM						{ $$ = "vacuum"; }
		| VALID							{ $$ = "valid"; }
		| VALUES						{ $$ = "values"; }
		| VARYING						{ $$ = "varying"; }
		| VERSION						{ $$ = "version"; }
		| VIEW							{ $$ = "view"; }
		| WITH							{ $$ = "with"; }
		| WITHOUT						{ $$ = "without"; }
		| WORK							{ $$ = "work"; }
		| YEAR_P						{ $$ = "year"; }
		| ZONE							{ $$ = "zone"; }
		;

/* Column identifier --- keywords that can be column, table, etc names.
 *
 * Many of these keywords will in fact be recognized as type or function
 * names too; but they have special productions for the purpose, and so
 * can't be treated as "generic" type or function names.
 *
 * The type names appearing here are not usable as function names
 * because they can be followed by '(' in typename productions, which
 * looks too much like a function call for an LR(1) parser.
 */
col_name_keyword:
		  BIT							{ $$ = "bit"; }
		| CHAR							{ $$ = "char"; }
		| CHARACTER						{ $$ = "character"; }
		| COALESCE						{ $$ = "coalesce"; }
		| DEC							{ $$ = "dec"; }
		| DECIMAL						{ $$ = "decimal"; }
		| EXISTS						{ $$ = "exists"; }
		| EXTRACT						{ $$ = "extract"; }
		| FLOAT							{ $$ = "float"; }
		| INTERVAL						{ $$ = "interval"; }
		| NCHAR							{ $$ = "nchar"; }
		| NONE							{ $$ = "none"; }
		| NULLIF						{ $$ = "nullif"; }
		| NUMERIC						{ $$ = "numeric"; }
		| POSITION						{ $$ = "position"; }
		| SETOF							{ $$ = "setof"; }
		| SUBSTRING						{ $$ = "substring"; }
		| TIME							{ $$ = "time"; }
		| TIMESTAMP						{ $$ = "timestamp"; }
		| TRIM							{ $$ = "trim"; }
		| VARCHAR						{ $$ = "varchar"; }
		;

/* Function identifier --- keywords that can be function names.
 *
 * Most of these are keywords that are used as operators in expressions;
 * in general such keywords can't be column names because they would be
 * ambiguous with variables, but they are unambiguous as function identifiers.
 *
 * Do not include POSITION, SUBSTRING, etc here since they have explicit
 * productions in a_expr to support the goofy SQL9x argument syntax.
 *  - thomas 2000-11-28
 */
func_name_keyword:
		  AUTHORIZATION					{ $$ = "authorization"; }
		| BETWEEN						{ $$ = "between"; }
		| BINARY						{ $$ = "binary"; }
		| CROSS							{ $$ = "cross"; }
		| FREEZE						{ $$ = "freeze"; }
		| FULL							{ $$ = "full"; }
		| ILIKE							{ $$ = "ilike"; }
		| IN							{ $$ = "in"; }
		| INNER_P						{ $$ = "inner"; }
		| IS							{ $$ = "is"; }
		| ISNULL						{ $$ = "isnull"; }
		| JOIN							{ $$ = "join"; }
		| LEFT							{ $$ = "left"; }
		| LIKE							{ $$ = "like"; }
		| NATURAL						{ $$ = "natural"; }
		| NOTNULL						{ $$ = "notnull"; }
		| OUTER_P						{ $$ = "outer"; }
		| OVERLAPS						{ $$ = "overlaps"; }
		| PUBLIC						{ $$ = "public"; }
		| RIGHT							{ $$ = "right"; }
		| VERBOSE						{ $$ = "verbose"; }
		;

/* Reserved keyword --- these keywords are usable only as a ColLabel.
 *
 * Keywords appear here if they could not be distinguished from variable,
 * type, or function names in some contexts.  Don't put things here unless
 * forced to.
 */
reserved_keyword:
		  ALL							{ $$ = "all"; }
		| ANALYSE						{ $$ = "analyse"; } /* British */
		| ANALYZE						{ $$ = "analyze"; }
		| AND							{ $$ = "and"; }
		| ANY							{ $$ = "any"; }
		| AS							{ $$ = "as"; }
		| ASC							{ $$ = "asc"; }
		| BOTH							{ $$ = "both"; }
		| CASE							{ $$ = "case"; }
		| CAST							{ $$ = "cast"; }
		| CHECK							{ $$ = "check"; }
		| COLLATE						{ $$ = "collate"; }
		| COLUMN						{ $$ = "column"; }
		| CONSTRAINT					{ $$ = "constraint"; }
		| CREATE						{ $$ = "create"; }
		| CURRENT_DATE					{ $$ = "current_date"; }
		| CURRENT_TIME					{ $$ = "current_time"; }
		| CURRENT_TIMESTAMP				{ $$ = "current_timestamp"; }
		| CURRENT_USER					{ $$ = "current_user"; }
		| DEFAULT						{ $$ = "default"; }
		| DEFERRABLE					{ $$ = "deferrable"; }
		| DESC							{ $$ = "desc"; }
		| DISTINCT						{ $$ = "distinct"; }
		| DO							{ $$ = "do"; }
		| ELSE							{ $$ = "else"; }
		| END_TRANS						{ $$ = "end"; }
		| EXCEPT						{ $$ = "except"; }
		| FALSE_P						{ $$ = "false"; }
		| FOR							{ $$ = "for"; }
		| FOREIGN						{ $$ = "foreign"; }
		| FROM							{ $$ = "from"; }
		| GRANT							{ $$ = "grant"; }
		| GROUP							{ $$ = "group"; }
		| HAVING						{ $$ = "having"; }
		| INITIALLY						{ $$ = "initially"; }
		| INTERSECT						{ $$ = "intersect"; }
		| INTO							{ $$ = "into"; }
		| LEADING						{ $$ = "leading"; }
		| LIMIT							{ $$ = "limit"; }
		| NEW							{ $$ = "new"; }
		| NOT							{ $$ = "not"; }
		| NULL_P						{ $$ = "null"; }
		| OFF							{ $$ = "off"; }
		| OFFSET						{ $$ = "offset"; }
		| OLD							{ $$ = "old"; }
		| ON							{ $$ = "on"; }
		| ONLY							{ $$ = "only"; }
		| OR							{ $$ = "or"; }
		| ORDER							{ $$ = "order"; }
		| PRIMARY						{ $$ = "primary"; }
		| REFERENCES					{ $$ = "references"; }
		| SELECT						{ $$ = "select"; }
		| SESSION_USER					{ $$ = "session_user"; }
		| SOME							{ $$ = "some"; }
		| TABLE							{ $$ = "table"; }
		| THEN							{ $$ = "then"; }
		| TO							{ $$ = "to"; }
		| TRAILING						{ $$ = "trailing"; }
		| TRUE_P						{ $$ = "true"; }
		| UNION							{ $$ = "union"; }
		| UNIQUE						{ $$ = "unique"; }
		| USER							{ $$ = "user"; }
		| USING							{ $$ = "using"; }
		| WHEN							{ $$ = "when"; }
		| WHERE							{ $$ = "where"; }
		;


SpecialRuleRelation:  OLD
				{
					if (QueryIsRule)
						$$ = "*OLD*";
					else
						elog(ERROR,"OLD used in non-rule query");
				}
		| NEW
				{
					if (QueryIsRule)
						$$ = "*NEW*";
					else
						elog(ERROR,"NEW used in non-rule query");
				}
		;

%%

static Node *
makeA_Expr(int oper, char *opname, Node *lexpr, Node *rexpr)
{
	A_Expr *a = makeNode(A_Expr);
	a->oper = oper;
	a->opname = opname;
	a->lexpr = lexpr;
	a->rexpr = rexpr;
	return (Node *)a;
}

static Node *
makeTypeCast(Node *arg, TypeName *typename)
{
	/*
	 * If arg is an A_Const, just stick the typename into the
	 * field reserved for it --- unless there's something there already!
	 * (We don't want to collapse x::type1::type2 into just x::type2.)
	 * Otherwise, generate a TypeCast node.
	 */
	if (IsA(arg, A_Const) &&
		((A_Const *) arg)->typename == NULL)
	{
		((A_Const *) arg)->typename = typename;
		return arg;
	}
	else
	{
		TypeCast *n = makeNode(TypeCast);
		n->arg = arg;
		n->typename = typename;
		return (Node *) n;
	}
}

static Node *
makeStringConst(char *str, TypeName *typename)
{
	A_Const *n = makeNode(A_Const);
	n->val.type = T_String;
	n->val.val.str = str;
	n->typename = typename;

	return (Node *)n;
}

static Node *
makeFloatConst(char *str)
{
	A_Const *n = makeNode(A_Const);
	TypeName *t = makeNode(TypeName);
	n->val.type = T_Float;
	n->val.val.str = str;
	t->name = xlateSqlType("float");
	t->typmod = -1;
	n->typename = t;

	return (Node *)n;
}

/* makeRowExpr()
 * Generate separate operator nodes for a single row descriptor expression.
 * Perhaps this should go deeper in the parser someday...
 * - thomas 1997-12-22
 */
static Node *
makeRowExpr(char *opr, List *largs, List *rargs)
{
	Node *expr = NULL;
	Node *larg, *rarg;

	if (length(largs) != length(rargs))
		elog(ERROR,"Unequal number of entries in row expression");

	if (lnext(largs) != NIL)
		expr = makeRowExpr(opr,lnext(largs),lnext(rargs));

	larg = lfirst(largs);
	rarg = lfirst(rargs);

	if ((strcmp(opr, "=") == 0)
	 || (strcmp(opr, "<") == 0)
	 || (strcmp(opr, "<=") == 0)
	 || (strcmp(opr, ">") == 0)
	 || (strcmp(opr, ">=") == 0))
	{
		if (expr == NULL)
			expr = makeA_Expr(OP, opr, larg, rarg);
		else
			expr = makeA_Expr(AND, NULL, expr, makeA_Expr(OP, opr, larg, rarg));
	}
	else if (strcmp(opr, "<>") == 0)
	{
		if (expr == NULL)
			expr = makeA_Expr(OP, opr, larg, rarg);
		else
			expr = makeA_Expr(OR, NULL, expr, makeA_Expr(OP, opr, larg, rarg));
	}
	else
	{
		elog(ERROR,"Operator '%s' not implemented for row expressions",opr);
	}

	return expr;
}

/* findLeftmostSelect()
 *		Find the leftmost component SelectStmt in a set-operation parsetree.
 */
static SelectStmt *
findLeftmostSelect(SelectStmt *node)
{
	while (node && node->op != SETOP_NONE)
		node = node->larg;
	Assert(node && IsA(node, SelectStmt) && node->larg == NULL);
	return node;
}

/* insertSelectOptions()
 *		Insert ORDER BY, etc into an already-constructed SelectStmt.
 *
 * This routine is just to avoid duplicating code in SelectStmt productions.
 */
static void
insertSelectOptions(SelectStmt *stmt,
					List *sortClause, List *forUpdate,
					Node *limitOffset, Node *limitCount)
{
	/*
	 * Tests here are to reject constructs like
	 *	(SELECT foo ORDER BY bar) ORDER BY baz
	 */
	if (sortClause)
	{
		if (stmt->sortClause)
			elog(ERROR, "Multiple ORDER BY clauses not allowed");
		stmt->sortClause = sortClause;
	}
	if (forUpdate)
	{
		if (stmt->forUpdate)
			elog(ERROR, "Multiple FOR UPDATE clauses not allowed");
		stmt->forUpdate = forUpdate;
	}
	if (limitOffset)
	{
		if (stmt->limitOffset)
			elog(ERROR, "Multiple OFFSET clauses not allowed");
		stmt->limitOffset = limitOffset;
	}
	if (limitCount)
	{
		if (stmt->limitCount)
			elog(ERROR, "Multiple LIMIT clauses not allowed");
		stmt->limitCount = limitCount;
	}
}

static Node *
makeSetOp(SetOperation op, bool all, Node *larg, Node *rarg)
{
	SelectStmt *n = makeNode(SelectStmt);

	n->op = op;
	n->all = all;
	n->larg = (SelectStmt *) larg;
	n->rarg = (SelectStmt *) rarg;
	return (Node *) n;
}


/* xlateSqlFunc()
 * Convert alternate function names to internal Postgres functions.
 *
 * Do not convert "float", since that is handled elsewhere
 *  for FLOAT(p) syntax.
 *
 * Converting "datetime" to "timestamp" and "timespan" to "interval"
 * is a temporary expedient for pre-7.0 to 7.0 compatibility;
 * these should go away for v7.1.
 */
char *
xlateSqlFunc(char *name)
{
	if (strcmp(name,"character_length") == 0)
		return "char_length";
	else if (strcmp(name,"datetime") == 0)
		return "timestamp";
	else if (strcmp(name,"timespan") == 0)
		return "interval";
	else
		return name;
} /* xlateSqlFunc() */

/* xlateSqlType()
 * Convert alternate type names to internal Postgres types.
 *
 * NB: do NOT put "char" -> "bpchar" here, because that renders it impossible
 * to refer to our single-byte char type, even with quotes.  (Without quotes,
 * CHAR is a keyword, and the code above produces "bpchar" for it.)
 *
 * Convert "datetime" and "timespan" to allow a transition to SQL92 type names.
 * Remove this translation for v7.1 - thomas 2000-03-25
 *
 * Convert "lztext" to "text" to allow forward compatibility for anyone using
 * the undocumented "lztext" type in 7.0.  This can go away in 7.2 or later
 * - tgl 2000-07-30
 */
char *
xlateSqlType(char *name)
{
	if ((strcmp(name,"int") == 0)
		|| (strcmp(name,"integer") == 0))
		return "int4";
	else if (strcmp(name, "smallint") == 0)
		return "int2";
	else if (strcmp(name, "bigint") == 0)
		return "int8";
	else if (strcmp(name, "real") == 0)
		return "float4";
	else if (strcmp(name, "float") == 0)
		return "float8";
	else if (strcmp(name, "decimal") == 0)
		return "numeric";
	else if (strcmp(name, "datetime") == 0)
		return "timestamp";
	else if (strcmp(name, "timespan") == 0)
		return "interval";
	else if (strcmp(name, "lztext") == 0)
		return "text";
	else if (strcmp(name, "boolean") == 0)
		return "bool";
	else
		return name;
} /* xlateSqlType() */


void parser_init(Oid *typev, int nargs)
{
	QueryIsRule = FALSE;
	/*
	 * Keep enough information around to fill out the type of param nodes
	 * used in postquel functions
	 */
	param_type_info = typev;
	pfunc_num_args = nargs;
}

Oid param_type(int t)
{
	if ((t > pfunc_num_args) || (t <= 0))
		return InvalidOid;
	return param_type_info[t - 1];
}

/*
 * Test whether an a_expr is a plain NULL constant or not.
 */
bool
exprIsNullConstant(Node *arg)
{
	if (arg && IsA(arg, A_Const))
	{
		A_Const *con = (A_Const *) arg;

		if (con->val.type == T_Null &&
			con->typename == NULL)
			return TRUE;
	}
	return FALSE;
}

/*
 * doNegate --- handle negation of a numeric constant.
 *
 * Formerly, we did this here because the optimizer couldn't cope with
 * indexquals that looked like "var = -4" --- it wants "var = const"
 * and a unary minus operator applied to a constant didn't qualify.
 * As of Postgres 7.0, that problem doesn't exist anymore because there
 * is a constant-subexpression simplifier in the optimizer.  However,
 * there's still a good reason for doing this here, which is that we can
 * postpone committing to a particular internal representation for simple
 * negative constants.  It's better to leave "-123.456" in string form
 * until we know what the desired type is.
 */
static Node *
doNegate(Node *n)
{
	if (IsA(n, A_Const))
	{
		A_Const *con = (A_Const *)n;

		if (con->val.type == T_Integer)
		{
			con->val.val.ival = -con->val.val.ival;
			return n;
		}
		if (con->val.type == T_Float)
		{
			doNegateFloat(&con->val);
			return n;
		}
	}

	return makeA_Expr(OP, "-", NULL, n);
}

static void
doNegateFloat(Value *v)
{
	char   *oldval = v->val.str;

	Assert(IsA(v, Float));
	if (*oldval == '+')
		oldval++;
	if (*oldval == '-')
		v->val.str = oldval+1;	/* just strip the '-' */
	else
	{
		char   *newval = (char *) palloc(strlen(oldval) + 2);

		*newval = '-';
		strcpy(newval+1, oldval);
		v->val.str = newval;
	}
}
