Todo
====

## Task
Make auto packaging more easily extendable

### Milestones

* ~Make a core module for new packages~ **See InstallFunctions.psm1**
* ~Support sequencing appv apps~ **See VLC Example**
* Support custom EXE/MSI
* Write generic version checker and url downloader

## Progress InstallFunctions module
* Downloader
* Get version from strings
* Make a sequencer script
* Intrinsic package name/targeting
* Test suite

## Done Tasks
~Depreciate AD Group Functionality~

USC are moving away from AD Group targeting in USC.

### Milestones

* ~Remove Creation of AD Groups~
* ~All deployments should be created to 2 targets. A Pilot and a Production.~
* ~If a deployment is restricted it should go to All USC Staff and Students with 'Requires Administrative approval'~
* ~Otherwise a deployment should be deployed to machine collection.~
_Notes_ 
Deployments should be targeted to Pilot for 1-2 weeks prior to becoming available to production deployment.
Production deployments should become available for 1-2 weeks prior to deadlining. This will allow seekers to get the latest updates asap.


## Progress

* ~Remove Creation of AD Group~
* ~Add creation of pilot collections (per app?)~
* ~Setup specific deployments for pilot and prod~
