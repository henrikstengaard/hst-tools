Param(
    [Parameter(Mandatory=$true)]
    [string]$branch,
    [Parameter(Mandatory=$true)]
    [string]$releaseBranches
)

# Use try catch block to ensure script exits with error code, if it fails
try
{
    # get git commit count
    $commitCount = git rev-list HEAD --count

    # set prerelease empty, if branch is a release branch. otherwise set prerelease to branch name
    if ($branch -match '^master$' -or $branch -match $releaseBranches)
    {
        $prerelease = ""
    }
    else
    {
        $prerelease = ("-{0}{1}" -f ($branch -replace '[^a-z0-9]', ''), $commitCount)
    }

    # patch prerelease to last 20 characters, if prerelease exceeds 20 characters
    if ($prerelease.length -gt 20)
    {
        $prerelease = "-" + $prerelease.Substring($prerelease.length - 20, 20)
    }

    Write-Host ("prelease = '$prerelease'")

    # get module directories
    $moduleDirectories = @()
    $moduleDirectories += Get-ChildItem | Where-Object { $_.PSIsContainer }

    foreach($moduleDirectory in $moduleDirectories)
    {
        # get csproj files
        $csprojFiles = @()
        $csprojFiles += Get-ChildItem -Path $moduleDirectory.FullName -Filter *.csproj -Recurse -ErrorAction SilentlyContinue

        # skip, if no csproj files exist in module directory
        if ($csprojFiles.Count -eq 0)
        {
            continue
        }

        Write-Output "---------------------------------------------------------------------------------------"
        Write-Output ("Patching assembly version for module '{0}'" -f $moduleDirectory.Name)
        Write-Output "---------------------------------------------------------------------------------------"
        Write-Output ""

        # get shared assembly files
        $sharedAssemblyFiles = @()
        $sharedAssemblyFiles += Get-ChildItem -Path $moduleDirectory.FullName -Filter SharedAssemblyInfo.cs -Recurse -ErrorAction SilentlyContinue

        # skip, if module directory doesn't have any shared assembly files
        if ($sharedAssemblyFiles.Count -eq 0)
        {
            Write-Warning ("Module '{0}' doesn't have any shared assembly files!" -f $moduleDirectory.Name)
            Write-Output ""
            continue                        
        }

        # warning, if module directory contains more than 1 shared assembly file
        if ($sharedAssemblyFiles.Count -gt 1)
        {
            Write-Error ("Module '{0}' has {1} shared assembly file(s)!" -f $moduleDirectory.Name, $sharedAssemblyFiles.Count)
            Write-Output ""
        }

        # patch shared assembly files
        foreach($sharedAssemblyFile in $sharedAssemblyFiles)
        {
            Write-Output ("Shared assembly file: {0}" -f $sharedAssemblyFile.FullName)
            Write-Output ""

            # read shared assmebly file and patch assembly informational version
            $sharedAssemblyLines = Get-Content $sharedAssemblyFile.FullName

            # get version from assembly version            
            $version = $sharedAssemblyLines | Select-String -pattern 'AssemblyVersion\("([0-9]+\.[0-9]+.[0-9])' -AllMatches | ForEach-Object { $_.Matches } | Foreach-Object { $_.Groups[1].Value } | Select-Object -First 1

            # fallback to version 1.0.0, if assembly version doesn't exist
            if (!$version)
            {
                $version = "1.0.0"
            }

            # patch shared assembly versions
            $patchedSharedAssemblyLines = $sharedAssemblyLines | ForEach-Object { 
                $_ -replace 'AssemblyVersion\("([^"]+)"\)', "AssemblyVersion(""$version"")" `
                -replace 'AssemblyFileVersion\("([^"]+)"\)', "AssemblyFileVersion(""$version"")" `
                -replace 'AssemblyInformationalVersion\("([^"]+)"\)', "AssemblyInformationalVersion(""$version$prerelease"")"
            }

            # output assembly lines from patched shared assembly lines
            $patchedSharedAssemblyLines | Where-Object { $_ -match 'assembly' } | Foreach-Object { Write-Output $_ }

            # write patched shared assembly lines
            Out-File -FilePath $sharedAssemblyFile.FullName -InputObject $patchedSharedAssemblyLines -Encoding utf8
        }
        
        Write-Output ""
    }
}
catch
{
    Write-Error $_
    ##teamcity[buildStatus status='FAILURE']
    exit 1
}