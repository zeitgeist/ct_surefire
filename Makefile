REBAR=./rebar
CT_DIR=../../logs
REPORT_DIR=.
DEPS_DIR=..

all: deps
	${REBAR} compile

deps:
	${REBAR} get-deps

#simple but sufficient for now
test:
	${MAKE}	xmlify CT_DIR=test/t001 REPORT_DIR=test DEPS_DIR=deps

xmlify:
	erl -noshell -pa ebin ${DEPS_DIR}/*/ebin -run ct_surefire to_surefire_xml ${CT_DIR} ${REPORT_DIR} -s init stop

.PHONY: test