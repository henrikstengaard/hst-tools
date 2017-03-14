# Make solution file
# ------------------
#
# Author: Henrik Nørfjand Stengaard
# Date:   2017-03-14
#
# A PowerShell script to make a Visual Studio .sln solution file from existing .csproj files. 


Param(
	[Parameter(Mandatory=$true)]
	[string]$solutionFile
)


# template for building solution file
$solutionTemplateText = @'

Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio 14
VisualStudioVersion = 14.0.25420.1
MinimumVisualStudioVersion = 10.0.40219.1
[$Projects]
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		[$ProjectConfigurationId].Debug|Any CPU.ActiveCfg = Debug|Any CPU
		[$ProjectConfigurationId].Debug|Any CPU.Build.0 = Debug|Any CPU
		[$ProjectConfigurationId].Release|Any CPU.ActiveCfg = Release|Any CPU
		[$ProjectConfigurationId].Release|Any CPU.Build.0 = Release|Any CPU
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
'@

# get csproj files
$csprojFiles = @()
$csprojFiles += Get-ChildItem -Filter *.csproj -Recurse | Foreach-Object { $_.FullName }

# generate project configuration id
$projectConfigurationId = "{{{0}}}" -f [guid]::NewGuid().ToString().ToUpper() 

$projectsLines = @()

# build project lines
foreach ($csprojFile in $csprojFiles)
{
    $csprojLines = get-content $csprojFile

    $projectId = $csprojLines | Where-Object { $_ -match 'projectguid' } | Select-String -Pattern "<ProjectGuid>([^<>]+)</ProjectGuid>" -AllMatches | % { $_.Matches } | % { $_.Groups[1].Value.Trim() } | Select-Object -First 1
    $projectName = Split-Path -parent $csprojFile | Split-Path -leaf
    $projectFile = $csprojFile.Replace((Get-Location).ToString() + "\", "")

    $projectsLines += ("Project(""{0}"") = ""{1}"", ""{2}"", ""{{{3}}}""" -f $projectId, $projectName, $projectFile, $projectConfigurationId)
    $projectsLines += "EndProject"
}

# replace solution template placeholders
$solutionTemplateText = $solutionTemplateText.Replace('[$ProjectConfigurationId]', $projectConfigurationId)
$solutionTemplateText = $solutionTemplateText.Replace('[$Projects]', $projectsLines -join [System.Environment]::NewLine)

# write solution file
[System.IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($solutionFile), $solutionTemplateText)