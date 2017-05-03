# Build and check redirects
# -------------------------
#
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2017-05-03
#
# A Powershell script to build redirects web.config for IIS and can check status of redirect and new urls after web.config is deployed. 
# Following parameters can be used:
# -redirectsCsvFile "[FILE.CSV]" (Required): Comma-separated file with redirects containing "OldUrl" and "NewUrl" columns.
# -redirectsReportCsvFile "[FILE.CSV]" (Optional): Comma-separated report file generated for building and checking redirects. If not defined, report file will be same as redirects csv file with ".report.csv" appended.
# -oldUrlDomain "http://www.example.com/" (Optional): This will replace the old urls domain in redirects csv file, if defined.
# -newUrlDomain "http://www.example.com/" (Optional): This will replace the new urls domain in redirects csv file, if defined.
# -buildRedirectsWebConfig (Optional): Switch to enable build redirects web config.
# -redirectsWebConfigFile "[WEB.CONFIG]" (Optional): Output redirects web config file for IIS. If not defined, redirects web config file will be same as redirects csv file with ".web.config" appended.
# -checkNewUrls (Optional): Switch to enable checking new urls in redirects csv file.
# -checkOldUrls (Optional): Switch to enable checking old urls in redirects csv file.


Param(
	[Parameter(Mandatory=$true)]
	[string]$redirectsCsvFile,
	[Parameter(Mandatory=$false)]
	[string]$redirectsReportCsvFile,
	[Parameter(Mandatory=$false)]
	[string]$oldUrlDomain,
	[Parameter(Mandatory=$false)]
	[string]$newUrlDomain,
	[Parameter(Mandatory=$false)]
	[switch]$buildRedirectsWebConfig,
	[Parameter(Mandatory=$false)]
	[string]$redirectsWebConfigFile,
	[Parameter(Mandatory=$false)]
	[switch]$checkNewUrls,
	[Parameter(Mandatory=$false)]
	[switch]$checkOldUrls
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
        $statusCode = [int]$response.StatusCode
        $location = $response.Headers["Location"]
    }
    catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = [int]$response.StatusCode
    }

    if (!$location)
    {
        $location = ''
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
    <action type="Redirect" url="{2}" redirectType="Permanent" appendQueryString="{3}" />
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

    # skip, if old url is invalid
    if (!$redirect.OldUrl -or $redirect.OldUrl -notmatch '^https?://')
    {
        $redirect.OldUrlStatus = "Invalid OldUrl"
        continue
    }

    # skip, if new url is invalid
    if (!$redirect.NewUrl -or $redirect.NewUrl -notmatch '^https?://')
    {
        $redirect.NewUrlStatus = "Invalid NewUrl"
        continue
    }

    $redirect.UrlsValid = $true

    # get old and new path
    $redirect.OldPath = $redirect.OldUrl -replace '^https?://[^/]+/?', '' -replace '/$', ''
    $redirect.NewPath = $redirect.NewUrl -replace '^https?://[^/]+/?', '' -replace '/$', ''

    # set urls identical, if old and new path are identical
    $redirect.UrlsIdentical = $redirect.OldPath -like $redirect.NewPath

    # replace old url domain, if defined
    if ($oldUrlDomain)
    {
        $redirect.OldUrl = $oldUrlDomain + $redirect.OldPath
    }

    # replace new url domain, if defined
    if ($newUrlDomain)
    {
        $redirect.NewUrl = $newUrlDomain + $redirect.NewPath
    }

    # strip trailing slash from old and new url
    $redirect.OldUrl = $redirect.OldUrl -replace '/$', ''
    $redirect.NewUrl = $redirect.NewUrl -replace '/$', ''
}


# sort redirects by redirect path, so most specific redirects comes first and make list unique
$redirectsSortedByRedirectPath = $redirects | Sort-Object @{expression={$_.OldUrl};Ascending=$false} -Unique


# build redirects web config 
if ($buildRedirectsWebConfig)
{
    $validRedirects = @()
    $validRedirects += $redirectsSortedByRedirectPath | Where-Object { $_.UrlsValid -and !$_.UrlsIdentical }

    Write-Host ("Writing {0} redirects to web.config" -f $validRedirects.Count)

    $redirectsWebConfig = $redirectsWebConfigTemplate -f (($validRedirects | Foreach-Object { $rewriteRuleTemplate -f [guid]::NewGuid(), ('^' + $_.OldPath), ($_.NewUrl -replace '&', '&amp;'), ($_.NewPath -match '\?') }) -join [System.Environment]::NewLine)
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
            $redirect.NewUrlStatus = 'WARNING: Url''s not valid, skipped!'
            continue
        }

        # execute request to check new url
        $response = ExecuteRequest -url $redirect.NewUrl

        # add new url status column with response status code
        $redirect.NewUrlStatus = $response.StatusCode
    }
}


# check old urls
if ($checkOldUrls)
{
    foreach ($redirect in $redirects)
    {
        # skip, if urls aren't valid
        if (!$redirect.UrlsValid)
        {
            $redirect.RedirectTestUrlStatus = 'WARNING: Url''s not valid, skipped!'
            continue
        }

        # skip, if urls are identical
        if ($redirect.UrlsIdentical)
        {
            $redirect.RedirectTestUrlStatus = 'WARNING: Url''s are identical, skipped!'
            continue
        }

        # execute request to check redirect of old url
        $response = ExecuteRequest -url $redirect.OldUrl

        # add location and status code to redirect
        $redirect.Location = $response.Location
        $redirect.StatusCode = $response.StatusCode

        # strip trailing slash from response location
        $location = $response.Location -replace '/$', ''

        # check if location matches new url
        if ($redirect.StatusCode -eq 301 -and $redirect.NewUrl -like $location)
        {
            $redirect.RedirectTestUrlStatus = "OK"
        }
        else
        {
            $redirect.RedirectTestUrlStatus = 'ERROR: Response location doesn''t redirect to new url'
        }
    }
}


# write redirects report csv file
$redirects | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $redirectsReportCsvFile -NoTypeInformation -Encoding UTF8

# done
Write-Host "Done" -ForegroundColor "Green"