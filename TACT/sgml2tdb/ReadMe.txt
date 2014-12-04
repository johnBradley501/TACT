                    SGML2TDB Version 1.0 Beta(a)
                         released May 1997

This readme file accompanies the 2nd release of the sgml2tdb program.
The first release was June 1996.

Acquiring and installing sgml2tdb
=================================

sgml2tdb is not of any use to you unless you have other TACT
components already. Thus, the sgml2tdb installation package is
set up to be installed in the context of other TACT programs.

* sgml2tdb is available via anonymous ftp from
  tactweb.humanities.mcmaster.ca. Look for the directory /pub/sgml2tdb.

* It is packaged as a ZIP file called "sgml2tdb.zip".  To install
  it you will need the program PKUNZIP or equivalent.

* Once you have downloaded the ZIP file, place it in the
  directory in which you have installed the other TACT programs.
  Usually, this is "c:\tact\".

* The ZIP file contains a directory structure that you should
  preserve when unzipping. In the version of PKUNZIP I have
  (2.04g), this is the -d option. Thus, the command to install
  the sgml2tdb components would be: 

  c:\tact> pkunzip -d sgml2tdb.zip

* pkunzip will install the basic set of files that permits
  sgml2tdb to run in the current directory. These files include
  sgml2tdb.exe, tactjb.res, sgml2tdb.xdt and the extended memory
  management files rtm.exe and dpmi16bi.ovl.

* pkunzip will also install a basic set of sgml files required
  to process TEIlite documents in a subdirectory "sgmls".

* pkunzip will also install an sgml2tdb User's Guide (encoded
  in HTML) in subdirectory doc.

* Finally, pkunzip will install a sample file marked up using
  TEIlite, and the files that are necessary to allow sgml2tdb
  to process it in subdirectory sample. All the files needed to
  process this sample text and create a TDB are present.  To
  test it out use the MAKECRIT.BAT file.

Make sure that both the environment variables TACTPATH and
SGML_PATH are set appropriately.

The HTML version of the sgml2tdb User's Guide is in the
doc subdirectory of this one. 


sgml2tdb is Beta
================

This version of sgml2tdb is still Beta-level software. You should
expect that the software may contain bugs and design
imperfections. Furthermore, as more experience is gained by the
author in processing SGML-based texts, expect the feature list to
grow and perhaps the ways existing features are invoked to
change.

Although sgml2tdb is beta-level software, I have no resources
other than myself available to rapidly enhance it, and I can 
only allot a small amount of time to this task. However, I welcome 
your comments and suggestions, and will update the software based 
on your comments as time permits. Of course, I will not be able to 
guarantee that a problem will be fixed in any particular timeframe.

Please send your thoughts to <john.bradley@kcl.ac.uk>.


License issues for sgml2tdb and its components
==============================================

sgml2tdb contains almost all of sgmls -- an SGML parser that was
developed by James Clark (jjc@jclark.com). Without his code
sgml2tdb would have been too difficult for me to write. Parts of
sgmls in turn are dervied from arcsgml which was written by
Charles F. Goldfarb. Contained within sgmls are also SGML Parser
materials provided free by the Standard Generalized Markup
Language Users' Group (SGMLUG). The parts that were written by
James Clark are in the public domain. The portions of sgml2tdb
that are written by me are copyright, but may be freely
distributed as long as acknowledgement of their original source
is preserved.

                                    ... john bradley
                                        May 1997