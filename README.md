Helper to convert openQA testsuites into inline definitions in jobtemplates

## Usage

```
./bin/jobtemplate-convert.pl [long options...] <jobtemplate-id> <testsuite-id>
	--host STR       OpenQA host (e.g. o3, osd or localhost)
	--apikey STR     API Key
	--apisecret STR  API Secret
	--convert-multi  Also convert if testsuite is contained multiple times
	--help           print usage message and exit
```
