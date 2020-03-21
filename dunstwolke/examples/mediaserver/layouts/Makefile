

COMPILER=/home/felix/build/dunstwolke-Desktop-Debug/dunstblick-compiler/dunstblick-compiler
RUNNER=/home/felix/build/dunstwolke-Desktop-Debug/examples/dunstblick-layout-tester/dunstblick-layout-tester
LAYOUTS=$(wildcard *.ui)
COMPILED=$(LAYOUTS:.ui=.cui)

all: $(COMPILED)

test: $(LAYOUT:.ui=.cui)
	$(RUNNER) $< 

clean:
	rm $(COMPILED)

%.cui: %.ui server.json
	$(COMPILER) -o $@ -c server.json $<

.PHONY: test clean
.SUFFIXES: 