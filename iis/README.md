# IIS

This directory contains powershell scripts for Internet Information Services.

## IIS-Site-List

A powershell script to list running IIS sites with process id for application pool. Following parameters can be used:

* -full: Display full information about IIS site with physical path, application pool and bindings.
* -all: Display all sites covering both running and not running sites.

Example 1: List running IIS sites with application pool's process id.

###
    > iis-site-list.ps1

Example 2: List all IIS sites running and not running. Running IIS sites are listed with application pool's process id.

###
    > iis-site-list.ps1 -all

Example 3: List running IIS sites with full information about physical path, application pool and bindings.

###
    > iis-site-list.ps1 -full

Example 4: List all IIS sites with full information about physical path, application pool and bindings.

###
    > iis-site-list.ps1 -all -full

## IIS-Site-Start

A powershell script to start IIS Site and application pool with physical path matching current directory.

Example: Start IIS site and application pool at current directory.

###
    > iis-site-start.ps1

## IIS-Site-Stop

A powershell script to stop IIS Site and application pool with physical path matching current directory.

Example: Stop IIS site and application pool at current directory.

###
    > iis-site-stop.ps1

## IIS-Site-Restart

A powershell script to restart IIS Site and application pool with physical path matching current directory.

Example: Restart IIS site and application pool at current directory.

###
    > iis-site-restart.ps1
