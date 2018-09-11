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

    if ($response)
    {
        $response.Close()
        $response.Dispose()    
    }

    return @{ "StatusCode" = $statusCode; "Location" = $location }
}


# redirects web config template
$redirectsWebConfigTemplate = @'
<configuration>
    <system.web>
        <customErrors mode="off" />
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

# default redirects report csv file
if (!$redirectsReportCsvFile)
{
    $redirectsReportCsvFile = $firstRedirectsCsvFile + '.report.csv'
}

# default redirects web config file
if ($buildRedirectsWebConfig -and !$redirectsWebConfigFile)
{
    $redirectsWebConfigFile = $firstRedirectsCsvFile + '.web.config'
}


# process redirects
Write-Host ("Processing " + $redirects.Count + " redirects...") -ForegroundColor "Green"


$oldUrlDomainUri = if ($oldUrlDomain) { [System.Uri]$oldUrlDomain } else { $null }
$newUrlDomainUri = if ($newUrlDomain) { [System.Uri]$newUrlDomain } else { $null }

$oldDomainsIndex = @{}


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
        $redirect.OldUrl = $redirect.OldUrl -replace '\s+', ''

        if ($redirect.OldUrl -match '^([^/\.]+\.[^/\.]+|[^/\.]+\.[^/\.]+\.[^/\.]+)+' -and $redirect.OldUrl -notmatch '^https?://')
        {
            $redirect.OldUrl = $oldUrlDomainUri.Scheme + '://' + $redirect.OldUrl
        }
        elseif ($redirect.OldUrl -match '^/' -and $oldUrlDomainUri -and $redirect.OldUrl -notmatch '^https?://')
        {
            $redirect.OldUrl = (New-Object -TypeName 'System.Uri' -ArgumentList $oldUrlDomainUri, $redirect.OldUrl).AbsoluteUri
        }
    }

    # add scheme and host to new url
    if ($redirect.NewUrl)
    {
        $redirect.NewUrl = $redirect.NewUrl -replace '\s+', ''

        if ($redirect.NewUrl -match '^([^/\.]+\.[^/\.]+|[^/\.]+\.[^/\.]+\.[^/\.]+)+' -and $redirect.NewUrl -notmatch '^https?://')
        {
            $redirect.NewUrl = $newUrlDomainUri.Scheme + '://' + $redirect.NewUrl
        }
        elseif ($redirect.NewUrl -match '^/' -and $newUrlDomainUri -and $redirect.NewUrl -notmatch '^https?://')
        {
            $redirect.NewUrl = (New-Object -TypeName 'System.Uri' -ArgumentList $newUrlDomainUri, $redirect.NewUrl).AbsoluteUri
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

    if (($newUrlExcludesParsed | Where-Object { $redirect.NewUrl -match $_ }).Count -gt 0)
    {
        $redirect.UrlsExcluded = $true
        continue
    }

    $redirect.UrlsValid = $true

    $oldUri = [System.Uri]$redirect.OldUrl
    $newUri = [System.Uri]$redirect.NewUrl

    if (!$oldDomainsIndex.ContainsKey($oldUri.Host))
    {
        $oldDomainsIndex[$oldUri.Host] = $true
    }

    # get old and new path and query string
    $redirect.OldPathAndQueryString = $oldUri.PathAndQuery -replace '/$', ''
    $redirect.NewPathAndQueryString = $newUri.PathAndQuery -replace '/$', ''

    # get old and new path
    $redirect.OldPath = $oldUri.AbsolutePath -replace '/$', ''
    $redirect.NewPath = $newUri.AbsolutePath -replace '/$', ''

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

    if ($redirect.OldPath -eq '/' -and $redirect.OldQueryString -eq '')
    {
        Write-Host ("WARNING: Root redirect for old url '{0}' to new url '{1}'!" -f $redirect.OldUrl, $redirect.NewUrl) -ForegroundColor Yellow
    }

    # set new path to '/', if empty
    if (!$redirect.NewPath -or $redirect.NewPath -eq '')
    {
        $redirect.NewPath = '/'
    }
}

Write-Host ("excluded redirects: {0}" -f ($redirects | Where-Object { $_.UrlsExcluded }).Count)

Set-Content ($firstRedirectsCsvFile + ".old_domains.txt") -Value ($oldDomainsIndex.Keys | Sort-Object)

# sort redirects by redirect path, so most specific redirects comes first and make list unique
$redirectsSorted = $redirects | Sort-Object @{expression={$_.OldPathAndQueryString};Ascending=$false}

# find duplicate redirects
$redirectsIndex = @{}
foreach($redirect in $redirectsSorted)
{
    $oldUrl = $redirect.OldUrl -replace '^https?://', 'http://' -replace '/$', ''
    $redirect.DuplicateRedirect = $redirectsIndex.ContainsKey($oldUrl)

    if ($redirect.DuplicateRedirect)
    {
        $message = "WARNING: Duplicate redirect '{0}'! First found redirects to '{1}' and duplicate redirects to '{2}'" -f $redirect.OldUrl, $redirectsIndex[$oldUrl].NewUrl, $redirect.NewUrl
        $redirect.DuplicateStatus = $message
        Write-Host $message -ForegroundColor Yellow
        continue
    }
    else
    {
        $redirect.DuplicateStatus = ''
    }

    $redirectsIndex[$oldUrl] = $redirect
}


# build redirects web config 
if ($buildRedirectsWebConfig)
{
    $validRedirects = @()
    $validRedirects += $redirectsSorted | Where-Object { $_.UrlsValid -and !$_.UrlsIdentical -and !$_.DuplicateRedirect }

    Write-Host ("Writing {0} redirects to web.config" -f $validRedirects.Count)

    $rewritesIndex = @{}

    foreach ($redirect in $validRedirects)
    {
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
            $rewriteRuleName += " using query string '{0}'" -f [System.Web.HttpUtility]::HtmlEncode($redirect.OldQueryString)

            $useRewriteMap = $true
            $useQueryString = $true
            $matchUrl = '^(.+?)/?$'
        }

        $rewriteId = CalculateMd5FromText -text $rewriteKey.ToLower()
        
        if ($redirect.OldUrlHasHost)
        {
            $conditions += '<add input="{{HTTP_HOST}}" pattern="^{0}$" />' -f $oldHost
        }

        if ($useQueryString)
        {
            $conditions += '<add input="{{QUERY_STRING}}" pattern="{0}" />' -f [System.Web.HttpUtility]::HtmlEncode([Regex]::Escape($redirect.OldQueryString))
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
                'OldPath' = $redirect.OldPathAndQueryString;
                'OldUrlHasHost' = $redirect.OldUrlHasHost;
                'NewUrlHasHost' = $redirect.NewUrlHasHost;
                'NewUrl' = $redirect.NewUrl
            }
        }

        # add rewrite to rewrite rules index
        $newPath = $redirect.NewPathAndQueryString
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
        $rewritesIndex[$rewriteId].MatchUrl = '^{0}/?$' -f ($rewritesIndex[$rewriteId].RewriteMap.Keys | Select-Object -First 1)

        # remove rewrite map condition
        $rewritesIndex[$rewriteId].Conditions = $rewritesIndex[$rewriteId].Conditions | Where-Object { $_ -notmatch $rewriteId }
        
        # replace redirect url with new url
        $rewritesIndex[$rewriteId].RedirectUrl = [System.Web.HttpUtility]::HtmlEncode($rewritesIndex[$rewriteId].NewUrl)
    }

    # build rewrite maps
    $rewriteMaps = New-Object System.Collections.Generic.List[System.Object]
    foreach($rewriteId in ($rewritesIndex.Keys | Where-Object { $rewritesIndex[$_].RewriteMap.Keys.Count -gt 1 } | Sort-Object @{expression={$_};Ascending=$false}))
    {
        $rewriteMap = $rewriteMapTemplate -f $rewriteId, (($rewritesIndex[$rewriteId].RewriteMap.Keys | `
            Sort-Object @{expression={$_};Ascending=$false} | `
            Foreach-Object { '<add key="{0}" value="{1}" />' -f [System.Web.HttpUtility]::HtmlEncode($_), [System.Web.HttpUtility]::HtmlEncode($rewritesIndex[$rewriteId].RewriteMap[$_]) }) -join [System.Environment]::NewLine)
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

    $redirectsWebConfig = $redirectsWebConfigTemplate -f `
        ($rewriteRules -join [System.Environment]::NewLine), `
        ($rewriteMaps -join [System.Environment]::NewLine),
    $redirectsWebConfig | Out-File -filepath $redirectsWebConfigFile
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
        $response = ExecuteRequest -url $redirect.NewUrl

        # add new url status column with response status code
        $redirect.NewUrlStatus = $response.StatusCode
        $newUrlsStatusIndex[$newUrlId] = $redirect.NewUrlStatus
    }
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
            $redirect.OldUrl = (New-Object -TypeName 'System.Uri' -ArgumentList $oldUrlDomainUri, $oldPath).AbsoluteUri
        }

        # force http
        if ($forceHttp)
        {
            $redirect.OldUrl = $redirect.OldUrl -replace '^https?://', 'http://'
        }

        # execute request to check redirect of old url
        $response = ExecuteRequest -url $redirect.OldUrl

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
            $url = $url.ToLower() -replace '/$', ''
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
                if (!$url)
                {
                    Write-Host ("redirect result in null: {0}" -f ($urlsVisited -join ','))
                }
                $response = ExecuteRequest -url $url

                $responseIndex[$url] = $response
            }
            
            $urlHasRedirect = $response -and $response.StatusCode -eq 301 -and $response.Location
            if ($urlHasRedirect)
            {
                $oldU = $url
                $url = $response.Location
                $urlsVisited.Add($oldU + '=>' + $url)
            }
            else
            {
                $urlsVisited.Add('no url to follow')
            }
        } while ($urlHasRedirect -and !$cyclicRedirect -and $redirectCount -lt 20)

        if ($cyclicRedirect)
        {
            Write-Host ("cyclic redirect: {0}" -f ($urlsVisited -join ','))
            $redirect.RedirectTestUrlStatus = "ERROR: Cyclic redirect detect in urls '{0}'" -f ($urlsVisited -join ',')
            continue
        }
        
        if ($redirectCount -ge 20)
        {
            $redirect.RedirectTestUrlStatus = "ERROR: Too many redirects"
            continue
        }

        # strip trailing slash from new url and response location
        $newUrl = $redirect.NewUrl -replace '/$', '' -replace '^https?://', 'https://'
        $location = $redirect.Location -replace '/$', '' -replace '^https?://', 'https://'

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
                $locationEqual = $redirect.NewPathAndQueryString -like $locationUri.PathAndQuery
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
            Write-Host -NoNewline "x"
            $redirect.RedirectTestUrlStatus = 'ERROR: Response doesn''t redirect'
        }

    }
    Write-Host ""
    Write-Host "Done" -ForegroundColor Green
}


# write redirects report csv file
Write-Host "Writing redirects repost csv '$redirectsReportCsvFile'..." -ForegroundColor Yellow
$redirectsSorted | ForEach-Object { New-Object PSObject -Property $_ } | export-csv -delimiter ';' -path $redirectsReportCsvFile -NoTypeInformation -Encoding UTF8
Write-Host "Done" -ForegroundColor "Green"