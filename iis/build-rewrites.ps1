# Build Rewrites
# --------------
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2017-03-23

# Powershell script to build rewrites web.config for IIS. Following parameters can be used:
# -redirectsCsvFile "redirects.csv"


Param(
	[Parameter(Mandatory=$true)]
	[string]$redirectsCsvFile,
	[Parameter(Mandatory=$false)]
	[string]$redirectsReportCsvFile,
	[Parameter(Mandatory=$false)]
	[string]$rewritesWebConfigFile,
	[Parameter(Mandatory=$false)]
	[switch]$buildRewritesWebConfig,
	[Parameter(Mandatory=$false)]
	[switch]$checkNewUrls,
	[Parameter(Mandatory=$false)]
	[string]$redirectTestDomain,
	[Parameter(Mandatory=$false)]
	[switch]$checkRedirectUrls
)


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


# rewrites web config template
$rewriteWebConfigTemplate = @'
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
$redirectsReportCsvFile

# read redirects csv file
$redirects = @()
$redirects += Import-Csv -Delimiter ';' $redirectsCsvFile | Foreach-Object { @{ "OldUrl" = $_.OldUrl.Trim(); "NewUrl" = $_.NewUrl.Trim() } }


# process redirects
Write-Host ("Processing " + $redirects.Count + " redirects...")
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


# sort redirects by redirect path, so most specific redirects comes first
$redirectsSortedByRedirectPath = $redirects | Sort-Object @{expression={$_.RedirectPath};Ascending=$false} -Unique


# build rewrites web config 
if ($buildRewritesWebConfig)
{
    $rewriteWebConfig = $rewriteWebConfigTemplate -f (($redirectsSortedByRedirectPath | Where-Object { $_.UrlsValid } | Foreach-Object { $rewriteRuleTemplate -f [guid]::NewGuid(), ('^' + $_.RedirectPath), $_.NewUrl }) -join [System.Environment]::NewLine)
    $rewriteWebConfig | Out-File -filepath $rewritesWebConfigFile
}


# check new urls
if ($checkNewUrls)
{
    foreach ($redirect in $redirects)
    {
        $response = ExecuteRequest -url $redirect.NewUrl

        $redirect.NewUrlStatus = $response.StatusCode
    }
}


# check redirect urls
if ($checkRedirectUrls)
{
    foreach ($redirect in $redirectsSortedByRedirectPath)
    {
        $redirectTestUrl = ($redirectTestDomain + $redirect.RedirectPath)

        $redirect.RedirectTestUrl = $redirectTestUrl

        if ($redirect.UrlsValid)
        {
            $response = ExecuteRequest -url $redirectTestUrl

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
        else
        {
            $redirect.RedirectTestUrlStatus = 'Warning: Url''s not valid, skipped!'
        }
    }
}


# write redirects report csv file
$redirects | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $redirectsReportCsvFile -NoTypeInformation -Encoding UTF8
