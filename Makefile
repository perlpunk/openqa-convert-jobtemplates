.PHONY: update

update: README.md

README.md: bin/jobtemplate-convert.pl
	perl bin/update-readme.pl
