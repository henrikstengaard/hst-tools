# Build and check redirects
# -------------------------
#
# Author: Henrik Nørfjand Stengaard
# Company: First Realize
# Date: 2018-09-11
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
	[string]$redirectsCsvFiles,
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
    [switch]$checkOldUrls,
    [Parameter(Mandatory=$false)]
    [switch]$forceOldUrlDomainHost,
    [Parameter(Mandatory=$false)]
    [switch]$skipRootRedirects,
    [Parameter(Mandatory=$false)]
    [switch]$forceHttp,
	[Parameter(Mandatory=$false)]
	[string]$oldUrlExcludes,
	[Parameter(Mandatory=$false)]
	[string]$newUrlExcludes
)

Add-Type -AssemblyName System.Web


# calculate md5 hash from text
function CalculateMd5FromText
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$text
    )

    $encoding = [system.Text.Encoding]::UTF8
	$md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
	return [System.BitConverter]::ToString($md5.ComputeHash($encoding.GetBytes($text))).ToLower().Replace('-', '')
}


# execute request
function ExecuteRequest
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$url,
        [Parameter(Mandatory=$true)]
        [bool]$forceHttp
    )

    if ($forceHttp)
    {
        $url = $url -replace '^https?://', 'http://'
    }

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

    if ($location -notmatch '^https?://')
    {
        $uri = [System.Uri]$url
        $location = (New-Object -TypeName 'System.Uri' -ArgumentList $uri, $location).AbsoluteUri
    }
    
    if ($response)
    {
        $response.Close()
        $response.Dispose()    
    }

    return @{ "StatusCode" = $statusCode; "Location" = $location }
}

# xml encode
function XmlEncode
{
    Param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$text
    )

    return $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace('''', '&apos;')
}

# format query string
function FormatQueryString
{
    Param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$queryString
    )

    $parameters = [System.Web.HttpUtility]::ParseQueryString($queryString)
    return ($parameters.Keys | Where-Object { $_ } | Foreach-Object { ("{0}={1}" -f $_, [System.Uri]::EscapeDataString($parameters[$_])) }) -join '&'
}

# redirects web config template
$redirectsWebConfigTemplate = @'
<configuration>
    <system.web>
        <customErrors mode="Off" />
    </system.web>
    <system.webServer>
        <rewrite>
            <rules>
{0}
            </rules>
            <rewriteMaps>
{1}
            </rewriteMaps>
        </rewrite>
    </system.webServer>
</configuration>
'@

# rewrite rule template
$rewriteRuleTemplate = @'
<rule name="{0}" stopProcessing="true">
    <match url="{1}" />
    <conditions>
{2}
    </conditions>
    <action type="Redirect" url="{3}" redirectType="Permanent" appendQueryString="False" />
</rule>
'@

# rewrite map template
$rewriteMapTemplate = @'
<rewriteMap name="{0}" defaultValue="">
{1}
</rewriteMap>
'@

# read redirects csv files
$redirects = @()
$firstRedirectsCsvFile = $null
foreach($redirectsCsvFile in ($redirectsCsvFiles -split ','))
{
    Write-Host ('Reading redirects csv file ''{0}''...' -f $redirectsCsvFile) -ForegroundColor Green

    # fail, if redirects csv file doesn't exist
    if (!(test-path $redirectsCsvFile))
    {
        Write-Error "Redirects csv file '$redirectsCsvFile' doesn't exist"
        exit 1
    }

    if (!$firstRedirectsCsvFile)
    {
        $firstRedirectsCsvFile = $redirectsCsvFile
    }

    $redirects += Import-Csv -Delimiter ';' $redirectsCsvFile | Foreach-Object { @{ "OldUrl" = $_.OldUrl.Trim(); "NewUrl" = $_.NewUrl.Trim() } }
}

if (!$outputDir)
{
    $outputDir = Split-Path $firstRedirectsCsvFile -Parent
}


# process redirects
Write-Host ("Processing " + $redirects.Count + " redirects...") -ForegroundColor "Green"


$oldUrlDomainUri = if ($oldUrlDomain) { [System.Uri]$oldUrlDomain } else { $null }
$newUrlDomainUri = if ($newUrlDomain) { [System.Uri]$newUrlDomain } else { $null }

$oldUrlExcludesParsed = @()

if ($oldUrlExcludes)
{
    $oldUrlExcludesParsed += $oldUrlExcludes -split ','
}

$newUrlExcludesParsed = @()

if ($newUrlExcludes)
{
    $newUrlExcludesParsed += $newUrlExcludes -split ','
}

foreach ($redirect in $redirects)
{
    $redirect.OriginalOldUrl = $redirect.OldUrl
    $redirect.OriginalNewUrl = $redirect.NewUrl

    $redirect.UrlsValid = $false
    $redirect.OldUrlHasHost = ($redirect.OldUrl -and $redirect.OldUrl -match '^https?://')
    $redirect.NewUrlHasHost = ($redirect.NewUrl -and $redirect.NewUrl -match '^https?://')
    
    # add scheme and host to old url
    if ($redirect.OldUrl)
    {
        # remove whitespaces
        $redirect.OldUrl = $redirect.OldUrl -replace '\s+', ''

        if ($redirect.OldUrl -match '^/' -and $oldUrlDomainUri)
        {
            $redirect.OldUrl = [System.Web.HttpUtility]::UrlDecode((New-Object -TypeName 'System.Uri' -ArgumentList $oldUrlDomainUri, $redirect.OldUrl).AbsoluteUri)
        }
        elseif ($redirect.OldUrl -notmatch '^https?://')
        {
            $scheme = if ($oldUrlDomainUri) { $oldUrlDomainUri.Scheme } else { 'http' }
            
            $oldUrl = $null
            if ($redirect.OldUrl -match '^[a-z0-9]+\.[a-z0-9]+')
            {
                $oldUrl = '{0}://{1}' -f $scheme, [System.Web.HttpUtility]::UrlDecode($redirect.OldUrl)
            }
            elseif ($oldUrlDomainUri)
            {
                $oldUrl = [System.Web.HttpUtility]::UrlDecode((New-Object -TypeName 'System.Uri' -ArgumentList $oldUrlDomainUri, $redirect.OldUrl).AbsoluteUri)
            }

            try
            {
                $oldUri = if ($oldUrl) { [System.Uri]$oldUrl } else { $null }
            }
            catch
            {
                $oldUri = $null
            }

            $redirect.OldUrlHasHost = $oldUri -and $oldUri.Host -and $oldUri.Host -ne ''
            if ($redirect.OldUrlHasHost)
            {
                $redirect.OldUrl = [System.Web.HttpUtility]::UrlDecode($oldUri.AbsoluteUri)
            }
        }
    }

    # add scheme and host to new url
    if ($redirect.NewUrl)
    {
        # remove whitespaces
        $redirect.NewUrl = $redirect.NewUrl -replace '\s+', ''

        if ($redirect.NewUrl -match '^/' -and $newUrlDomainUri)
        {
            # combine new url without domain with specified new url domain
            $redirect.NewUrl = [System.Web.HttpUtility]::UrlDecode((New-Object -TypeName 'System.Uri' -ArgumentList $newUrlDomainUri, $redirect.NewUrl).AbsoluteUri)
        }
        elseif ($redirect.NewUrl -notmatch '^https?://')
        {
            $scheme = if ($newUrlDomainUri) { $newUrlDomainUri.Scheme } else { 'http' }

            $newUrl = $null
            if ($redirect.NewUrl -match '^[a-z0-9]+\.[a-z0-9]+')
            {
                $newUrl = '{0}://{1}' -f $scheme, [System.Web.HttpUtility]::UrlDecode($redirect.NewUrl)
            }
            elseif ($newUrlDomainUri)
            {
                $newUrl = [System.Web.HttpUtility]::UrlDecode((New-Object -TypeName 'System.Uri' -ArgumentList $newUrlDomainUri, $redirect.NewUrl).AbsoluteUri)
            }
            
            try
            {
                $newUri = if ($newUrl) { [System.Uri]$newUrl } else { $null }
            }
            catch
            {
                $newUri = $null
            }
            
            $redirect.NewUrlHasHost = $newUri -and $newUri.Host -and $newUri.Host -ne ''
            if ($redirect.NewUrlHasHost)
            {
                $redirect.NewUrl = [System.Web.HttpUtility]::UrlDecode($newUri.AbsoluteUri)
            }
        }
    }
    
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

    # exclude urls, if old or any new url excludes match
    $redirect.UrlsExcluded = (($oldUrlExcludesParsed | Where-Object { $redirect.OldUrl -match $_ }).Count -gt 0) -or `
        (($newUrlExcludesParsed | Where-Object { $redirect.NewUrl -match $_ }).Count -gt 0)

    # skip redirect, if urls are excluded
    if ($redirect.UrlsExcluded)
    {
        continue
    }

    $redirect.UrlsValid = $true

    $oldUri = [System.Uri]$redirect.OldUrl
    $newUri = [System.Uri]$redirect.NewUrl

    # get old and new path and query string
    $redirect.OldPathAndQueryString = [System.Web.HttpUtility]::UrlDecode(($oldUri.AbsolutePath -replace '/+$', '') + $oldUri.Query)
    $redirect.NewPathAndQueryString = [System.Web.HttpUtility]::UrlDecode((($newUri.AbsolutePath -replace '/+$', '') + $newUri.Fragment + $newUri.Query))

    # get old and new path
    $redirect.OldPath = [System.Web.HttpUtility]::UrlDecode(($oldUri.AbsolutePath -replace '/+$', ''))
    $redirect.NewPath = [System.Web.HttpUtility]::UrlDecode((($newUri.AbsolutePath -replace '/+$', '') + $newUri.Fragment))

    # get old query string
    $redirect.OldQueryString = $oldUri.Query -replace '^\?', ''
    $redirect.NewQueryString = $newUri.Query -replace '^\?', ''

    # old scheme and host
    $redirect.OldScheme = $oldUri.Scheme
    $redirect.OldHost = $oldUri.Host

    # new scheme and host
    $redirect.NewScheme = $newUri.Scheme
    $redirect.NewHost = $newUri.Host
    
    # set urls identical, if old and new path are identical
    $redirect.UrlsIdentical = $redirect.OldPathAndQueryString -like $redirect.NewPathAndQueryString

    # set old path to '/', if empty
    if (!$redirect.OldPath -or $redirect.OldPath -eq '')
    {
        $redirect.OldPath = '/'
    }

    if (!$redirect.OldPathAndQueryString -or $redirect.OldPathAndQueryString -eq '')
    {
        $redirect.OldPathAndQueryString = '/'
    }
    
    if ($redirect.OldPath -eq '/' -and $redirect.OldQueryString -eq '')
    {
        Write-Host ("WARNING: Root redirect for old url '{0}' to new url '{1}'!" -f $redirect.OldUrl, $redirect.NewUrl) -ForegroundColor Yellow
    }

    # set new path to '/', if empty
    if (!$redirect.NewPath -or $redirect.NewPath -eq '')
    {
        $redirect.NewPath = '/'
    }

    if (!$redirect.NewPathAndQueryString -or $redirect.NewPathAndQueryString -eq '')
    {
        $redirect.NewPathAndQueryString = '/'
    }

    if ($redirect.NewUrl -match '^http://' -and $redirect.NewUrl -match ':80')
    {
        $redirect.NewUrl = $redirect.NewUrl -replace ':80', ''
    }

    if ($redirect.NewUrl -match '^https://' -and $redirect.NewUrl -match ':443')
    {
        $redirect.NewUrl = $redirect.NewUrl -replace ':443', ''
    }

    if ($redirect.NewUrl -match '/\?')
    {
        $redirect.NewUrl = $redirect.NewUrl -replace '/\?', '?'
    }
}

# sort redirects by redirect path, so most specific redirects comes first and make list unique
$redirectsSorted = $redirects | Sort-Object @{expression={$_.OldPathAndQueryString};Ascending=$false}

# find duplicate redirects
$redirectsIndex = @{}
foreach($redirect in $redirectsSorted)
{
    $oldUrl = $redirect.OldUrl -replace '^https?://', 'http://' -replace '/+$', ''


    if ($redirectsIndex.ContainsKey($oldUrl))
    {
        # remove duplicate status from prevoius duplicate
        $redirectsIndex[$oldUrl].DuplicateRedirect = $false 
        $redirectsIndex[$oldUrl].DuplicateStatus = '' 

        $redirect.DuplicateRedirect = $true
        $redirect.DuplicateStatus = "WARNING: Duplicate redirect to '{0}'! Existing redirect to '{1}' replaced by redirect to '{2}'" -f $redirect.OldUrl, $redirectsIndex[$oldUrl].NewUrl, $redirect.NewUrl
    }
    else
    {
        $redirect.DuplicateRedirect = $false
        $redirect.DuplicateStatus = ''
    }

    $redirectsIndex[$oldUrl] = $redirect
}

Write-Host ("Duplicate redirects: {0}" -f ($redirects | Where-Object { $_.DuplicateRedirect }).Count)
Write-Host ("Excluded redirects: {0}" -f ($redirects | Where-Object { $_.UrlsExcluded }).Count)


# build redirects web config 
if ($buildRedirectsWebConfig)
{
    $validRedirects = @()
    $validRedirects += $redirectsSorted | Where-Object { $_.UrlsValid -and !$_.UrlsIdentical -and !$_.DuplicateRedirect }

    Write-Host ("Writing {0} redirects to web.config" -f $validRedirects.Count)

    $oldUrlDomainsIndex = @{}
    $rewritesIndex = @{}

    foreach ($redirect in $validRedirects)
    {
        if (!$oldUrlDomainsIndex.ContainsKey($redirect.OldHost))
        {
            $oldUrlDomainsIndex[$redirect.OldHost] = $true
        }
    
        $conditions = @()

        if ($skipRootRedirects -and $redirect.OldPath -eq '/')
        {
            continue
        }

        $oldHost = if ($forceOldUrlDomainHost -and $oldUrlDomainUri) { $oldUrlDomainUri.Host } else { $redirect.OldHost }

        $redirectUrl = if ($redirect.NewUrlHasHost) { '{0}://{1}{{C:1}}' -f $redirect.NewScheme, $redirect.NewHost } else { '{C:1}' }
        

        # build rewrite key and rule name
        $rewriteRuleName = "Rewrite rule for "

        if ($redirect.OldPath -eq '/')
        {
            $rewriteRuleName += "root url "
        }
        else
        {
            $rewriteRuleName += "urls "
        }

        $rewriteKey = "OldUrlHost={0}" -f $redirect.OldUrlHasHost
        if ($redirect.OldUrlHasHost)
        {
            $rewriteRuleName += "with host '{0}'" -f $redirect.OldHost
            $rewriteKey += ",{0}" -f $redirect.OldHost.ToLower()
        }
        else
        {
            $rewriteRuleName += "on any host"
        }
        $rewriteKey += "|NewUrlHost={0}" -f $redirect.NewUrlHasHost

        if ($redirect.NewUrlHasHost)
        {
            $rewriteRuleName += " to host '{0}'" -f $redirect.NewHost
            $rewriteKey += ",{0}" -f $redirect.NewHost.ToLower()
        }
        else
        {
            $rewriteRuleName += " to same host"
        }

        # make root redirects unique
        if ($redirect.OldPath -eq '/')
        {
            $rewriteKey += "|{0}" -f $redirect.OldPath
        }

        $useRewriteMap = $false
        $useQueryString = $false

        if ($redirect.OldPath -eq '/')
        {
            $matchUrl = '^/?$'
        }
        elseif (!$redirect.OldQueryString -or $redirect.OldQueryString -eq '^\s*$')
        {
            $useRewriteMap = $true
            $matchUrl = '^(.+?)/?$'
        }
        else
        {
            $rewriteKey += "|{0}" -f $redirect.OldQueryString
            $rewriteRuleName += " using query string '{0}'" -f (XmlEncode $redirect.OldQueryString)

            $useRewriteMap = $true
            $useQueryString = $true
            $matchUrl = '^(.+?)/?$'
        }

        $rewriteId = CalculateMd5FromText -text $rewriteKey.ToLower()

        if ($redirect.OldUrlHasHost -or $redirect.OldPath -eq '/')
        {
            $conditions += '<add input="{{HTTP_HOST}}" pattern="^{0}$" />' -f $oldHost
        }

        if ($useQueryString)
        {
            $conditions += '<add input="{{QUERY_STRING}}" pattern="{0}" />' -f (XmlEncode ([Regex]::Escape($redirect.OldQueryString)))
        }

        if ($useRewriteMap)
        {
            $conditions += '<add input="{{{0}:{{R:1}}}}" pattern="(.+)" />' -f $rewriteId
        }

        if (!$rewritesIndex.ContainsKey($rewriteId))
        {
            $rewritesIndex[$rewriteId] = @{
                'Name' = $rewriteRuleName;
                'MatchUrl' = $matchUrl;
                'Conditions' = $conditions;
                'RedirectUrl' = $redirectUrl;
                'UseQueryString' = $useQueryString;
                'RewriteMap' = @{};
                'OldPath' = ($redirect.OldPath -replace '^/', '');
                'OldPathAndQueryString' = $redirect.OldPathAndQueryString;
                'OldUrlHasHost' = $redirect.OldUrlHasHost;
                'NewUrlHasHost' = $redirect.NewUrlHasHost;
                'OldUrl' = $redirect.OldUrl;
                'NewUrl' = $redirect.NewUrl
            }
        }

        # add rewrite to rewrite rules index
        $newPath = $redirect.NewPathAndQueryString 

        if ($newPath -match '\?')
        {
            $newPath = "{0}?{1}" -f ($newPath -replace '\?.*'), (FormatQueryString $redirect.NewQueryString)
        }

        if ($newPath -notmatch '^/')
        {
            $newPath = '/{0}' -f $newPath
        }
        $rewritesIndex[$rewriteId].RewriteMap[($redirect.OldPath -replace '^/', '')] = $newPath
    }

    # update rewrite rules with one entry in rewrite map
    foreach ($rewriteId in ($rewritesIndex.Keys | Where-Object { $rewritesIndex[$_].RewriteMap.Keys.Count -eq 1 }))
    {

        # replace match url with first old path in rewrite map
        $rewritesIndex[$rewriteId].MatchUrl = '^{0}/?$' -f $rewritesIndex[$rewriteId].OldPath

        # remove rewrite map condition
        $rewritesIndex[$rewriteId].Conditions = $rewritesIndex[$rewriteId].Conditions | Where-Object { $_ -notmatch $rewriteId }
        
        # replace redirect url with new url
        $rewritesIndex[$rewriteId].RedirectUrl = XmlEncode $rewritesIndex[$rewriteId].NewUrl
    }

    # build rewrite maps
    $rewriteMaps = New-Object System.Collections.Generic.List[System.Object]
    foreach($rewriteId in ($rewritesIndex.Keys | Where-Object { $rewritesIndex[$_].RewriteMap.Keys.Count -gt 1 } | Sort-Object @{expression={$_};Ascending=$false}))
    {
        $rewriteMap = $rewriteMapTemplate -f $rewriteId, (($rewritesIndex[$rewriteId].RewriteMap.Keys | `
            Sort-Object @{expression={$_};Ascending=$false} | `
            Foreach-Object { '<add key="{0}" value="{1}" />' -f (XmlEncode $_), (XmlEncode ($rewritesIndex[$rewriteId].RewriteMap[$_])) }) -join [System.Environment]::NewLine)
        $rewriteMaps.Add($rewriteMap)
    }

    # sort rewrite index for building rewrite rules
    $rewriteIndexKeysSorted = @()
    $rewriteIndexKeysSorted += $rewritesIndex.Keys | Where-Object { $rewritesIndex[$_].UseQueryString } | Sort-Object @{expression={$rewritesIndex[$_].OldPathAndQueryString};Ascending=$false},@{expression={$rewritesIndex[$_].OldUrlHasHost};Ascending=$false},@{expression={$rewritesIndex[$_].NewUrlHasHost};Ascending=$false}
    $rewriteIndexKeysSorted += $rewritesIndex.Keys | Where-Object { !$rewritesIndex[$_].UseQueryString } | Sort-Object @{expression={$rewritesIndex[$_].OldPathAndQueryString};Ascending=$false},@{expression={$rewritesIndex[$_].OldUrlHasHost};Ascending=$false},@{expression={$rewritesIndex[$_].NewUrlHasHost};Ascending=$false}

    # build rewrite rules
    $rewriteRules = New-Object System.Collections.Generic.List[System.Object]
    foreach($rewriteId in $rewriteIndexKeysSorted)
    {
        $rewrite = $rewritesIndex[$rewriteId]

        $rewriteRule = $rewriteRuleTemplate -f `
            $rewrite.Name, `
            $rewrite.MatchUrl, `
            ($rewrite.Conditions -join [System.Environment]::NewLine), `
            $rewrite.RedirectUrl
        $rewriteRules.Add($rewriteRule)
    }

    # write redirects web.config file
    $redirectsWebConfigFile = Join-Path $outputDir -ChildPath 'web.config'
    Write-Host "Writing redirects web.config file '$redirectsWebConfigFile'..." -ForegroundColor Yellow
    $redirectsWebConfig = $redirectsWebConfigTemplate -f `
        ($rewriteRules -join [System.Environment]::NewLine), `
        ($rewriteMaps -join [System.Environment]::NewLine),
    $redirectsWebConfig | Out-File -filepath $redirectsWebConfigFile

    # write old url domains text file
    $oldUrlDomainsFile = Join-Path $outputDir -ChildPath 'old_url_domains.txt'
    Write-Host "Writing old url domains text file '$oldUrlDomainsFile'..." -ForegroundColor Yellow
    Set-Content $oldUrlDomainsFile -Value ($oldUrlDomainsIndex.Keys | Sort-Object)
    
    # write build redirects report csv file
    $buildRedirectsCsvFile = Join-Path $outputDir -ChildPath 'build_redirects_report.csv'
    Write-Host "Writing build redirects repost csv file '$buildRedirectsCsvFile'..." -ForegroundColor Yellow
    $redirectsSorted | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $buildRedirectsCsvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Done" -ForegroundColor "Green"
}


# check new urls
if ($checkNewUrls)
{
    $newUrlsStatusIndex = @{}

    foreach ($redirect in $redirects)
    {
        # skip, if urls aren't valid
        if (!$redirect.UrlsValid)
        {
            $redirect.NewUrlStatus = 'WARNING: Url''s not valid, skipped!'
            continue
        }

        $newUrlId = CalculateMd5FromText -text $redirect.NewUrl.ToLower()

        if ($newUrlsStatusIndex.ContainsKey($newUrlId))
        {
            $redirect.NewUrlStatus = $newUrlsStatusIndex[$newUrlId]
            continue
        }

        Write-Host ("Checking new url '{0}'..." -f $redirect.NewUrl)

        # execute request to check new url
        $response = ExecuteRequest -url $redirect.NewUrl -forceHttp $forceHttp

        # add new url status column with response status code
        $redirect.NewUrlStatus = $response.StatusCode
        $newUrlsStatusIndex[$newUrlId] = $redirect.NewUrlStatus
    }

    # write check new urls report csv file
    $checkNewUrlsReportCsvFile = Join-Path $outputDir -ChildPath 'check_new_urls_report.csv'
    Write-Host "Writing check new urls report csv file '$checkNewUrlsReportCsvFile'..." -ForegroundColor Yellow
    $redirectsSorted | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $checkNewUrlsReportCsvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Done" -ForegroundColor "Green"
}


# check old urls
if ($checkOldUrls)
{
    $responseIndex = @{}

    Write-Host "Checking old urls..." -ForegroundColor Yellow
    foreach ($redirect in $redirectsSorted)
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

        # force old url domain for old url
        if ($forceOldUrlDomainHost -and $oldUrlDomainUri)
        {
            $oldPath = $redirect.OldPathAndQueryString
            $redirect.OldUrl = [System.Web.HttpUtility]::UrlDecode((New-Object -TypeName 'System.Uri' -ArgumentList $oldUrlDomainUri, $oldPath).AbsoluteUri)
        }

        # force http
        if ($forceHttp)
        {
            $redirect.OldUrl = $redirect.OldUrl -replace '^https?://', 'http://'
        }

        # execute request to check redirect of old url
        $response = ExecuteRequest -url $redirect.OldUrl -forceHttp $forceHttp

        # add location and status code to redirect
        $redirect.Location = $response.Location
        $redirect.StatusCode = $response.StatusCode
        
        # cyclic redirect check of response location
        $redirectSession = @{ $redirect.OldUrl = $true }
        $redirectCount = 0
        $cyclicRedirect = $false
        $url = $response.Location
        $urlsVisited = New-Object System.Collections.Generic.List[System.Object]
        $urlsVisited.Add($redirect.OldUrl)
        do {
            if (!$url)
            {
                break;
            }

            $redirectCount++
            $url = $url.ToLower() -replace '/+$', ''
            $cyclicRedirect = $redirectSession.ContainsKey($url)

            if (!$cyclicRedirect)
            {
                $urlsVisited.Add($url)
            }

            $redirectSession[$url] = $true

            if ($responseIndex.ContainsKey($url))
            {
                $response = $responseIndex[$url]
            }
            else
            {
                $response = ExecuteRequest -url $url -forceHttp $forceHttp

                $responseIndex[$url] = $response
            }
            
            $urlHasRedirect = $response -and $response.StatusCode -eq 301 -and $response.Location
            if ($urlHasRedirect)
            {
                $url = $response.Location
            }
        } while ($urlHasRedirect -and !$cyclicRedirect -and $redirectCount -lt 20)

        $redirect.CyclicRedirect = $cyclicRedirect

        if ($cyclicRedirect)
        {
            Write-Host -NoNewline "O"
            $redirect.RedirectTestUrlStatus = "ERROR: Cyclic redirect detect in urls '{0}'" -f ($urlsVisited -join ',')
            continue
        }

        $redirect.TooManyRedirects = $redirectCount -ge 20
        
        if ($redirectCount -ge 20)
        {
            Write-Host -NoNewline "%"
            $redirect.RedirectTestUrlStatus = "ERROR: Too many redirects"
            continue
        }

        # strip trailing slash from new url and response location
        $newUrl = [System.Web.HttpUtility]::UrlDecode(($redirect.NewUrl -replace '/+$', '' -replace '^https?://', 'https://'))
        $location = [System.Web.HttpUtility]::UrlDecode(($redirect.Location -replace '/+$', '' -replace '^https?://', 'https://'))

        # check if location matches new url
        $urlRedirect = $false
        $locationEqual = $false
        if ($redirect.StatusCode -eq 301)
        {
            $urlRedirect = $true

            if ($redirect.NewUrlHasHost)
            {
                $locationEqual = $newUrl -like $location

                if (!$locationEqual)
                {
                    $newUrl = $newUrl -replace '^https?://', ''
                    $location = $location -replace '^https?://', ''

                    $locationEqual = $newUrl -like $location
                }
            }
            else
            {
                $locationUri = [System.Uri]$location
                $locationEqual = $redirect.NewPathAndQueryString -like [System.Web.HttpUtility]::UrlDecode($locationUri.PathAndQuery)
            }
        }

        if ($urlRedirect)
        {
            if ($locationEqual)
            {
                Write-Host -NoNewline "."
                $redirect.RedirectTestUrlStatus = "OK"
            }
            else
            {
                Write-Host -NoNewline "!"
                $redirect.RedirectTestUrlStatus = 'ERROR: Response location doesn''t redirect to new url'
            }
        }
        else
        {
            Write-Host -NoNewline "X"
            $redirect.RedirectTestUrlStatus = 'ERROR: Response doesn''t redirect'
        }

    }
    Write-Host ""
    Write-Host ("Cyclic redirects: {0}" -f ($redirectsSorted | Where-Object { $_.CyclicRedirect }).Count)
    Write-Host ("Too many redirects: {0}" -f ($redirectsSorted | Where-Object { $_.TooManyRedirects }).Count)

    # write check old urls report csv file
    $checkOldUrlsReportCsvFile = Join-Path $outputDir -ChildPath 'check_old_urls_report.csv'
    Write-Host "Writing check old url report csv file '$checkOldUrlsReportCsvFile'..." -ForegroundColor Yellow
    $redirectsSorted | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $checkOldUrlsReportCsvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Done" -ForegroundColor "Green"
}