
RUNNER=/home/felix/build/dunstwolke-Desktop-Debug/examples/dunstblick-layout-tester/dunstblick-layout-tester
COMPILER=/home/felix/build/dunstwolke-Desktop-Debug/dunstblick-compiler/dunstblick-compiler

all: contact.uit.dat development.uit.dat

run: development.uit.dat
	$(RUNNER) $<

%.uit.dat: %.uit
	$(COMPILER) -o $@ -c common.json $<

.PHONY: %.test
