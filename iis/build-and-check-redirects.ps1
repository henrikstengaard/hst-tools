# Build and check redirects
# -------------------------
#
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2017-03-27
#
# A Powershell script to build redirects web.config for IIS and can check status of redirect and new urls after web.config is deployed. 
# Following parameters can be used:
# -redirectsCsvFile "[FILE.CSV]" (Required): Comma-separated file with redirects containing "OldUrl" and "NewUrl" columns.
# -redirectsReportCsvFile "[FILE.CSV]" (Optional): Comma-separated report file generated for building and checking redirects. If not defined, report file will be same as redirects csv file with ".report.csv" appended.
# -buildRedirectsWebConfig (Optional): Switch to enable build redirects web config.
# -redirectsWebConfigFile "[WEB.CONFIG]" (Optional): Output redirects web config file for IIS. If not defined, redirects web config file will be same as redirects csv file with ".web.config" appended.
# -checkNewUrls (Optional): Switch to enable checking new urls in redirects csv file.
# -redirectTestDomain "http://www.example.com/" (Optional): Domain to check old url redirects. This will replace the domain in old urls in redirects csv file. If not defined, old url is used to check redirect.
# -checkRedirectUrls (Optional): Switch to enable checking old urls in redirects csv file.


Param(
	[Parameter(Mandatory=$true)]
	[string]$redirectsCsvFile,
	[Parameter(Mandatory=$false)]
	[string]$redirectsReportCsvFile,
	[Parameter(Mandatory=$false)]
	[switch]$buildRedirectsWebConfig,
	[Parameter(Mandatory=$false)]
	[string]$redirectsWebConfigFile,
	[Parameter(Mandatory=$false)]
	[switch]$checkNewUrls,
	[Parameter(Mandatory=$false)]
	[string]$redirectTestDomain,
	[Parameter(Mandatory=$false)]
	[switch]$checkRedirectUrls
)


# execute request
function ExecuteRequest
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$url
    )

    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect = $false

    $location = ""

    try {
        $response = $request.GetResponse()
        $statusCode = $response.StatusCode
        $location = $response.Headers["Location"]
    }
    catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = $response.StatusCode
    }

    $response.Close()
    $response.Dispose()    

    return @{ "StatusCode" = $statusCode; "Location" = $location }
}


# redirects web config template
$redirectsWebConfigTemplate = @'
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
{0}
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
'@

# rewrite rule template
$rewriteRuleTemplate = @'
<rule name="{0}" stopProcessing="true">
    <match url="{1}" />
    <action type="Redirect" url="{2}" redirectType="Permanent" />
</rule>
'@


# default redirects report csv file
if (!$redirectsReportCsvFile)
{
    $redirectsReportCsvFile = $redirectsCsvFile + '.report.csv'
}


# default redirects web config file
if ($buildRedirectsWebConfig -and !$redirectsWebConfigFile)
{
    $redirectsWebConfigFile = $redirectsCsvFile + '.web.config'
}


# fail, if redirects csv file doesn't exist
if (!(test-path $redirectsCsvFile))
{
    Write-Error "Redirects csv file '$redirectsCsvFile' doesn't exist"
    exit 1
}


# read redirects csv file
$redirects = @()
$redirects += Import-Csv -Delimiter ';' $redirectsCsvFile | Foreach-Object { @{ "OldUrl" = $_.OldUrl.Trim(); "NewUrl" = $_.NewUrl.Trim() } }


# process redirects
Write-Host ("Processing " + $redirects.Count + " redirects...") -ForegroundColor "Green"

foreach ($redirect in $redirects)
{
    $redirect.UrlsValid = $false

    # skip, if oldurl is invalid
    if (!$redirect.OldUrl -or $redirect.OldUrl -notmatch '^https?://')
    {
        $redirect.OldUrlStatus = "Invalid OldUrl"
        continue
    }

    # skip, if newurl is invalid
    if (!$redirect.NewUrl -or $redirect.NewUrl -notmatch '^https?://')
    {
        $redirect.NewUrlStatus = "Invalid NewUrl"
        continue
    }

    $redirect.UrlsValid = $true

    # set redirect path
    $redirect.RedirectPath = ($redirect.OldUrl -replace '^https?://[^/]+/', '' -replace '/$', '').Trim()
}


# sort redirects by redirect path, so most specific redirects comes first and make list unique
$redirectsSortedByRedirectPath = $redirects | Sort-Object @{expression={$_.RedirectPath};Ascending=$false} -Unique


# build redirects web config 
if ($buildRedirectsWebConfig)
{
    $redirectsWebConfig = $redirectsWebConfigTemplate -f (($redirectsSortedByRedirectPath | Where-Object { $_.UrlsValid } | Foreach-Object { $rewriteRuleTemplate -f [guid]::NewGuid(), ('^' + $_.RedirectPath), $_.NewUrl -replace '&', '&amp;' }) -join [System.Environment]::NewLine)
    $redirectsWebConfig | Out-File -filepath $redirectsWebConfigFile
}


# check new urls
if ($checkNewUrls)
{
    foreach ($redirect in $redirects)
    {
        # skip, if urls aren't valid
        if (!$redirect.UrlsValid)
        {
            $redirect.NewUrlStatus = 'Warning: Url''s not valid, skipped!'
            continue
        }

        # execute request to check new url
        $response = ExecuteRequest -url $redirect.NewUrl

        # add new url status column with response status code
        $redirect.NewUrlStatus = $response.StatusCode
    }
}


# check redirect urls
if ($checkRedirectUrls)
{
    foreach ($redirect in $redirectsSortedByRedirectPath)
    {
        # skip, if urls aren't valid
        if (!$redirect.UrlsValid)
        {
            $redirect.RedirectTestUrlStatus = 'Warning: Url''s not valid, skipped!'
            continue
        }

        # build redirect test url from redirect test domain and redirect path, if redirect test domain is defined. Otherwise use old url.
        if ($redirectTestDomain)
        {
            $redirectTestUrl = ($redirectTestDomain + $redirect.RedirectPath)
        }
        else
        {
            $redirectTestUrl = $redirect.OldUrl
        }

        # add redirect test url column
        $redirect.RedirectTestUrl = $redirectTestUrl

        # execute request to check redirect test url
        $response = ExecuteRequest -url $redirectTestUrl

        # add redirect test url status column with redirect result
        if ($redirect.NewUrl -eq $response.Location)
        {
            $redirect.RedirectTestUrlStatus = "OK"
        }
        elseif (!$response.Location -or $response.Location -eq '')
        {
            $redirect.RedirectTestUrlStatus = ("Error: No redirect with status code " + $response.StatusCode)
        }
        else
        {
            $redirect.RedirectTestUrlStatus = ("Error: Redirected to '" + $response.Location + "'")
        }
    }
}


# write redirects report csv file
$redirects | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $redirectsReportCsvFile -NoTypeInformation -Encoding UTF8

# done
Write-Host "Done" -ForegroundColor "Green"
