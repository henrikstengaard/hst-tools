# IIS

This directory contains powershell scripts for Internet Information Services.

## IIS-Site-List

A powershell script to list running IIS sites with process id for application pool. 

Following parameters can be used:

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

## Build and check redirects

A Powershell script to build redirects web.config for IIS and can check status of redirect and new urls after web.config is deployed.

Following parameters can be used:

* -redirectsCsvFiles "[FILE1.CSV],[FILE2.CSV]" (Required): Comma-separated files with redirects containing "OldUrl" and "NewUrl" columns.
* -redirectsReportCsvFile "[FILE.CSV]" (Optional): Comma-separated report file generated for building and checking redirects. If not defined, report file will be same as first redirects csv file.
* -oldUrlDomain "http://www.example.com/" (Optional): This will replace the old urls domain in redirects csv file, if defined.
* -newUrlDomain "http://www.example.com/" (Optional): This will replace the new urls domain in redirects csv file, if defined.
with ".report.csv" appended.
* -buildRedirectsWebConfig (Optional): Switch to enable build redirects web config.
* -redirectsWebConfigFile "[WEB.CONFIG]" (Optional): Output redirects web config file for IIS. If not defined, redirects web config file will be same as redirects csv file with ".web.config" appended.
* -checkNewUrls (Optional): Switch to enable checking new urls in redirects csv file.
* -checkOldUrls (Optional): Switch to enable checking old urls in redirects csv file.

Redirects csv file example content:

###
    OldUrl;NewUrl
    http://www.olddomain.com/a/page;http://www.newdomain.com/same/page

Example 1: Build redirects web config file:

```powershell
build-and-check-redirects.ps1 -redirectsCsvFiles "redirects.csv" -buildRedirectsWebConfig
```

Example 2: Build redirects web config file with redirects web config file:

```powershell
build-and-check-redirects.ps1 -redirectsCsvFiles "redirects.csv" -buildRedirectsWebConfig -redirectsWebConfigFile "web.config"
```

Example 3: Check new urls:

```powershell
build-and-check-redirects.ps1 -redirectsCsvFiles "redirects.csv" -checkNewUrls
```

Example 4: Check old urls with replaced domain in old and new urls:

```powershell
build-and-check-redirects.ps1 -redirectsCsvFiles "redirects.csv" -oldUrlDomain "http://www.example.com/" -newUrlDomain "http://www.example.com/" -checkOldUrls
```

## Increase web.config file size limit

When building web.config files with lot of redirects, then can exceed the default file size limit set by IIS.

Increase web.config file size limit to 15MB with following steps for large web.config's:

1. Double-click "iis_max_webconfig_size_15mb.reg" registry file to import it.
2. Restart IIS to apply web.config file size limit to increased 15MB.