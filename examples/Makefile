VERSION?=$(shell cat ../language-cfamily.cabal | grep '^Version:' | sed  -E 's/[ \t]+/ /g' | cut -sd' ' -f2)

EXAMPLES=ParseAndPrint ScanFile SearchDef TypeCheck ComputeSize DumpAst MkCallTree
all: $(EXAMPLES)
%: %.hs
	ghc -package language-cfamily-$(VERSION) --make -O $*.hs
clean:
	rm -f *.o *.hi $(EXAMPLES)
clean_tmp:
	rm -f *.o *.hi
