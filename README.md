hds-import-documents
=====================

This HYSCRIPT imports documents into the Hydstra documents tree.

## Version

Version 0.01

## Synopsis

Define your document naming convention as follows:

```
<STATIONID>_<DATETIME>_<MISC>.<FILETYPE>
HYDSYS01_20140101_SOMECONVENTION.JPG
```

The "MISC", label is currently not implemented and does nothing. The DATETIME, also has no relevance for the import since the import creates an entry in the HISTORY table against the datetime that the document was successfully imported. 


## Parameter screen

![Parameter screen](/images/psc.png)

## INI configuration

![INI file](/images/ini.png)
  
## Bugs

Please report any bugs in the issues wiki.

