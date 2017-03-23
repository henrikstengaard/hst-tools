Param(
    [Parameter(Mandatory=$true)]
    [string]$buildNumber,
    [Parameter(Mandatory=$true)]
    [string]$branch,
    [Parameter(Mandatory=$true)]
    [String]$configuration,
    [Parameter(Mandatory=$true)]
    [String]$nugetOutputDir,
    [Parameter(Mandatory=$false)]
    [String]$buildModules
)

# Use try catch block to ensure script exits with error code, if it fails
try
{
    # get git commit count
    $commitId = git rev-parse --short HEAD
    $commitCount = git rev-list HEAD --count

    # set nuget package tags
    $nugetPackageTags = "{0} {1} build{2}" -f ($branch -replace '[^a-z0-9\-\.]', ''), $commitId, $buildNumber

    # temp nuget output directory
    $tempNugetOutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("TempNugetOutput")

    # delete temp nuget output directory, if it exists
    if (Test-Path $tempNugetOutputDir)
    {
        Remove-Item $tempNugetOutputDir -Force -Recurse 
    }

    # create temp nuget output directory
    mkdir $tempNugetOutputDir | Out-Null

    # create nuget output directory directory, if it doesn't exist
    if (!(Test-Path $nugetOutputDir))
    {
        mkdir $nugetOutputDir | Out-Null
    }

    # get module directories
    $moduleDirectories = @()
    $moduleDirectories += Get-ChildItem | Where-Object { $_.PSIsContainer }

    # filter module directories, if build modules is defined
    if ($buildModules)
    {
        $filteredModuleDirectories = @()

        foreach($buildModule in ($buildModules -Split ','))
        {
            $filteredModuleDirectories += $moduleDirectories | Where-Object { $_.Name -like ('*' + $buildModule + '*') }
        }

        $moduleDirectories = $filteredModuleDirectories
    }

    # build nuget packages for modules
    foreach($moduleDirectory in $moduleDirectories)
    {
        # get csproj files
        $csprojFiles = @()
        $csprojFiles += Get-ChildItem -Path $moduleDirectory.FullName -Filter *.csproj -Recurse -ErrorAction SilentlyContinue

        # skip, if no csproj files exist
        if ($csprojFiles.Count -eq 0)
        {
            continue
        }

        # get nuspec files from csproj files
        $nuspecFiles = @()
        $nuspecFiles += $csprojFiles | Foreach-Object { $_.FullName -replace '\.csproj$', '.nuspec' } | Where-Object { Test-Path $_ }

        # skip, if no nuspec files exist
        if ($nuspecFiles.Count -eq 0)
        {
            continue
        }

        # detect, if any bin files


        # get shared assembly file
        $sharedAssemblyFile = Get-ChildItem -Path $moduleDirectory.FullName -Filter SharedAssemblyInfo.cs -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($sharedAssemblyFile)
        {
            # get version from shared assembly file
            $version = Get-Content $sharedAssemblyFile.FullName | Select-String -pattern 'AssemblyVersion\("([0-9]+\.[0-9]+.[0-9])' -AllMatches | ForEach-Object { $_.Matches } | Foreach-Object { $_.Groups[1].Value }
        }
        else
        {
            $version = "1.0.0"
        }

        # append prerelease to version, if branch is not release or master
        if ($branch -notmatch '^(master|release)')
        {
            $version += ("-{0}{1}" -f ($branch -replace '[^a-z0-9]', ''), $commitCount)
        }

        Write-Output "---------------------------------------------------------------------------------------"
        Write-Output ("Building nuget packages for module '{0}'" -f $moduleDirectory.Name)
        Write-Output "---------------------------------------------------------------------------------------"
        
        # build nuget packages for module nuspec files using nuget pack
        foreach($nuspecFile in $nuspecFiles)
        {
            [xml]$nuspecXml = Get-Content $nuspecFile;

            $tagsElement = $nuspecXml.SelectSingleNode('//package/metadata/tags')

            if (-not $tagsElement)
            {
                $tagsElement = $nuspecXml.CreateElement('tags')
                $nuspecXml.package.metadata.AppendChild($tagsElement) | Out-Null
            }

            $tags = $tagsElement.InnerXML

            if ($tags.length -gt 0)
            {
                $tags += ' ' 
            }

            if (!($tags -like ('*' + $nugetPackageTags + '*')))
            {
                $tags += $nugetPackageTags
            }

            $tagsElement.set_InnerXml($nugetPackageTags)

            $nuspecXml.Save($nuspecFile)

            $csprojFile = $nuspecFile -replace '\.nuspec$', '.csproj'

            Write-Output ""
            Write-Output ("Csproj file: {0}" -f $csprojFile)
            
            $nugetArgs = "pack ""{0}"" -Version {1} -IncludeReferencedProjects -Prop Configuration={2} -OutputDirectory ""{3}""" -f $csprojFile, $version, $configuration, $tempNugetOutputDir

            Write-Output ""

            $process = Start-Process -FilePath "nuget.exe" -ArgumentList $nugetArgs -Wait -NoNewWindow -PassThru
            if ($process.ExitCode -ne 0)
            {
                Write-Error "Failed to build nuget package for csproj file '$csprojFile'"
                #Write-Output "##teamcity[buildStatus status='FAILURE']"
                #exit 1
            }
        }

        Write-Output ""
    }

    # copy temp nuget output directory files to nuget output directory 
    Copy-Item -Path "$tempNugetOutputDir\*" -Destination $nugetOutputDir
}
catch
{
    Write-Error $_
    ##teamcity[buildStatus status='FAILURE']
    exit 1
}