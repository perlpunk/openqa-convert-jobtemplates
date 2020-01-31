Helper to convert openQA testsuites into inline definitions in jobtemplates

## Usage

```
 jobtemplate-inline-testsuite.pl [long options...] <jobtemplate-id> <testsuite-ids>
 jobtemplate-inline-testsuite.pl [long options...] <local-jobtemplate-file> <testsuite-ids>

 e.g.
 jobtemplate-inline-testsuite.pl --host o3 34 1195 1196
 jobtemplate-inline-testsuite.pl --host o3 34 name1 name2
 jobtemplate-inline-testsuite.pl --host o3 34 name1 name2 --update
 jobtemplate-inline-testsuite.pl --host o3 /path/to/local/jobtemplate.yaml name1 name2

	--host STR       OpenQA host (e.g. o3, osd or localhost)
	--apikey STR     API Key
	--apisecret STR  API Secret
	--convert-multi  Also convert if testsuite is contained multiple times
	--empty-only     Only convert plain "- name" testsuite entries, not
	                 existing settings
	--update         Actually post the updated template to the server
	--help           print usage message and exit
```
