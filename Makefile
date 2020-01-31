.PHONY: test testv update

update: README.md

README.md: bin/jobtemplate-inline-testsuite.pl
	perl bin/update-readme.pl

test:
	prove -l t
testv:
	prove -lv t
