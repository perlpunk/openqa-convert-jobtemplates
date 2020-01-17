.PHONY: update

update: README.md

README.md:
	perl bin/update-readme.pl
