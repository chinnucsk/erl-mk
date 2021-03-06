all: deps app
.PHONY: all

### DEPS -- Fetches & compiles deps recursively then moves every dep to deps/

deps : $(patsubst %,deps/%/,$(DEPS))
	$(if $(wildcard deps/*/deps/), \
	    mv -v deps/*/deps/* deps/ && rmdir $(wildcard deps/*/deps/))
.PHONY: deps

deps/%/:
	$(if $(wildcard deps/),,mkdir deps/)
	git clone -n -- $(word 1,$(dep_$*)) $@
	cd $@ && git checkout -q $(word 2,$(dep_$*)) && cd ../..
	$(if $(wildcard $@/Makefile), \
	    make -C $@ all, \
	    cd $@ && rebar get-deps compile && cd ../..)

### APP -- Compiles src/ into ebin/

app: $(patsubst src/%.app.src,  ebin/%.app,     $(wildcard src/*.app.src  )) \
     $(patsubst src/%.erl,      ebin/%.beam,    $(wildcard src/*.erl      )) \
     $(patsubst src/%.xrl,      ebin/%.beam,    $(wildcard src/*.xrl      )) \
     $(patsubst src/%.yrl,      ebin/%.beam,    $(wildcard src/*.yrl      )) \
     $(patsubst src/%.S,        ebin/%.beam,    $(wildcard src/*.S        )) \
     $(patsubst src/%.core,     ebin/%.beam,    $(wildcard src/*.core     )) \
     $(patsubst templates/%.dtl,ebin/%_dtl.beam,$(wildcard templates/*.dtl))
.PHONY: app

ebin/%.app: src/%.app.src    | ebin/
	cp $< $@

ebin/%.beam: src/%.erl       | ebin/
	erlc -o ebin/ $(ERLCFLAGS) -v -Iinclude/ -Ideps/ $<

ebin/%.beam: src/%.xrl       | ebin/
	erlc -o ebin/ $<
	erlc -o ebin/ ebin/$*.erl

ebin/%.beam: src/%.yrl       | ebin/
	erlc -o ebin/ $<
	erlc -o ebin/ ebin/$*.erl

ebin/%.beam: src/%.S         | ebin/
	erlc -o ebin/ $(ERLCFLAGS) -v +from_asm -Iinclude/ -Ideps/ $<

ebin/%.beam: src/%.core      | ebin/
	erlc -o ebin/ $(ERLCFLAGS) -v +from_core -Iinclude/ -Ideps/ $<

ebin/%_dtl.beam: templates/%.dtl | ebin/
	$(if $(shell [[ ! -d deps/erlydtl ]] && echo y), \
	    $(error Error compiling $<: deps/erlydtl/ not found))
	@erl -noshell -pa ebin/ -pa deps/*/ebin/ \
	     -eval 'io:format("Compiling ErlyDTL template $<\n").' \
	     -eval 'erlydtl:compile("$<", $*_dtl, [{out_dir,"ebin/"}]).' \
	     -s init stop

ebin/:
	mkdir ebin/

### EUNIT -- Compiles (into ebin/) & run EUnit tests (test/*_test.erl files).

eunit: $(patsubst test/%_tests.erl, eunit.%, $(wildcard test/*_tests.erl))
.PHONY: eunit

eunit.%: #ebin/%_tests.beam
	@erlc -o ebin/ -DTEST=1 -DEUNIT $(ERLCFLAGS) -v -Iinclude/ -Ideps/ test/$*_tests.erl
	@erl -noshell -pa ebin/ -pa deps/*/ebin/ \
	     -eval 'io:format("Module $*_tests:\n"), eunit:test($*_tests).' \
	     -s init stop
.PHONY: eunit.%

#ebin/%_tests.beam: test/%_tests.erl     | all #TODO fix something so that this can be used instead of the @erlc line above
#	erlc -o ebin/ -DTEST=1 -DEUNIT $(ERLCFLAGS) -v -Iinclude/ -Ideps/ $<
#.PRECIOUS: ebin/%_tests.beam

### CT -- Compiles (into ebin/) & run Common Test tests (test/*_SUITE.erl).

ct: $(patsubst test/%_SUITE.erl, ct.%, $(wildcard test/*_SUITE.erl))
.PHONY: ct

ct.%: ebin/%_SUITE.beam                 | logs/
#	Todo: use -no_auto_compile and ebin/%_SUITE.beam properly.
	@ct_run -noshell -dir test/ -logdir logs/ \
	        -pa ebin/ -pa $(wildcard $(shell pwd)/deps/*/ebin/) \
	        -suite $*_SUITE || true
.PHONY: ct.%

ebin/%_SUITE.beam: test/%_SUITE.erl     | ebin/
	erlc -o ebin/ $(ERLCFLAGS) -v -Iinclude/ -Ideps/ $<
.PRECIOUS: ebin/%_SUITE.beam

logs/:
	mkdir logs/

### DOCS -- Compiles the app's documentation into doc/

docs: $(foreach ext,app.src erl xrl yrl S core, $(wildcard src/*.$(ext))) \
                                                $(wildcard doc/overview.edoc)
	$(eval $@_APP = $(patsubst src/%.app.src,%,$(wildcard src/*.app.src)))
	@erl -noshell \
	     -eval 'io:format("Compiling documentation for $($@_APP).\n").' \
	     -eval 'edoc:application($($@_APP), ".", [$(EDOC_OPTS)]).' \
	     -s init stop
.PHONY: docs

### CLEAN-DOCS -- Removes generated doc/ stuff.

clean-docs:
	$(if $(wildcard doc/*.css),     rm doc/*.css)
	$(if $(wildcard doc/*.html),    rm doc/*.html)
	$(if $(wildcard doc/*.png),     rm doc/*.png)
	$(if $(wildcard doc/edoc-info), rm doc/edoc-info)
	@[[ -d doc/ ]] && [[ 'doc/*' = "`echo doc/*`" ]] && rmdir doc/ || true
.PHONY: clean-docs

### CLEAN -- Removes ebin/

clean:
	$(if $(wildcard ebin/),rm -r ebin/)
.PHONY: clean

### DISTCLEAN -- Removes ebin/ & deps/

distclean: clean clean-docs
	$(if $(wildcard deps/),rm -rf deps/)
	$(if $(wildcard logs/),rm -rf logs/)
.PHONY: distclean
