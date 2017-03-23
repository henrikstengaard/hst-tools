Param(
    [Parameter(Mandatory=$false)]
	[string]$buildModules
)

# Use try catch block to ensure script exits with error code, if it fails
try
{
    if (!$buildModules)
    {
        exit
    }

    # get module directories
    $moduleDirectories = @()
    $moduleDirectories += Get-ChildItem | Where-Object { $_.PSIsContainer }

    # build modules index of csproj files in each module
	$modules = @{}
    foreach($moduleDirectory in $moduleDirectories)
    {
        # get csproj files
        $csprojFiles = @()
        $csprojFiles += Get-ChildItem -Path $moduleDirectory.FullName -Filter *.csproj -Recurse -ErrorAction SilentlyContinue | Select-Object Name

        # skip, if no csproj files exist in module directory
        if ($csprojFiles.Count -eq 0)
        {
            continue
        }

		$modules.Set_Item($moduleDirectory.Name, $csprojFiles)
	}

    # make list of csproj files to build
	$buildCsprojFiles = @()
	$buildModules -Split ',' | Foreach-Object { $modules.keys -like ('*' + $_ + '*') } | ForEach-Object { $buildCsprojFiles += $modules.Get_Item($_) }

    # make build targets
	$buildTargets = ($buildCsprojFiles | ForEach-Object { $_.Name -replace '\.csproj', '' -replace '\.', '_' }) -join ';'

    # set teamcity build targets parameter 
    Write-Host "##teamcity[setParameter name='BuildTargets' value='$buildTargets']"
}
catch
{
    Write-Error $_
    ##teamcity[buildStatus status='FAILURE']
    exit 1
}