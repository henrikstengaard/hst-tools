# IIS

This directory contains powershell scripts for Internet Information Services.

## IIS-List

A powershell script to list running IIS sites with process id for application pool. Following parameters can be used:

* -full: Display full information about IIS site with physical path, application pool and bindings.
* -all: Display all sites covering both running and not running sites.

Example 1: List running IIS sites with application pool's process id.

###
    > iis-list.ps1

Example 2: List all IIS sites running and not running. Running IIS sites are listed with application pool's process id.

###
    > iis-list.ps1 -all

Example 3: List running IIS sites with full information about physical path, application pool and bindings.

###
    > iis-list.ps1 -full

Example 4: List all IIS sites with full information about physical path, application pool and bindings.

###
    > iis-list.ps1 -all -full
