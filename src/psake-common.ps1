Properties {
    ### Directories
    $base_dir = resolve-path .
    $build_dir = "$base_dir/build"
    $src_dir = "$base_dir/src"
    $tests_dir = "$base_dir/tests"
    $package_dir = "$base_dir/packages"
    $nuspec_dir = "$base_dir/nuspecs"
    $temp_dir = "$build_dir/temp"

    ### Tools
    $nuget = "$base_dir/.nuget/nuget.exe"
    $ilrepack = "$package_dir/ilrepack.*/tools/ilrepack.exe"
    $xunit = "$package_dir/xunit.runners*/tools/xunit.console.clr4.exe"
    $opencover = "$package_dir/OpenCover.*/opencover.console.exe"

    ### AppVeyor-related
    $appVeyorConfig = "$base_dir/appveyor.yml"
    $appVeyor = $env:APPVEYOR

    ### Project information
    $config = "Release"    
    $sharedAssemblyInfo = "$src_dir/SharedAssemblyInfo.cs"
    $directoryBuildProps = "$base_dir/Directory.build.props"
}

## Tasks

Task Prepare -Description "Prepare and clean up the build directory." {
    Write-Host "Preparing the build directory..." -ForegroundColor "Green"
    Clean-Directory $build_dir
}

Task Clean -Depends Prepare -Description "Clean up the project directories." {
    Write-Host "Cleaning up the solution..." -ForegroundColor "Green"
    Exec { dotnet clean -c $config -nologo -verbosity:minimal }
}

Task Restore -Depends Clean -Description "Restores all dependencies in a solution." {
    Write-Host "Restoring dependencies for the solution..." -ForegroundColor "Green"
    Exec { dotnet restore --locked-mode }
}

Task Compile -Depends Restore -Description "Compile all the projects in a solution." {
    Write-Host "Compiling the solution..." -ForegroundColor "Green"

    $extra = $null
    #if ($appVeyor) {
    #    $extra = "-logger:C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll"
    #}

    Exec { dotnet build --no-restore -c $config -nologo -verbosity:minimal $extra }
}

Task Version -Description "Patch AssemblyInfo and AppVeyor version files." {
    $newVersion = Read-Host "Please enter a new version number (major.minor.patch)"
    Update-SharedVersion $newVersion
    Update-AppVeyorVersion $newVersion
}

## Functions

### Test functions

function Run-XunitTests($project, $target) {
    Write-Host "Running xUnit test runner for '$project'..." -ForegroundColor "Green"
    $assembly = (Get-TestsOutputDir $project $target) + "/$project.dll"

    if ($appVeyor) {
        Exec { xunit.console.clr4 $assembly /appveyor }
    } else {
        Exec { .$xunit $assembly }
    }
}

function Run-OpenCover($projectWithOptionalTarget, $coverageFile, $coverageFilter) {
    $project = $projectWithOptionalTarget
    $target = $null

    if ($projectWithOptionalTarget -Is [System.Array]) {
        $project = $projectWithOptionalTarget[0]
        $target = $projectWithOptionalTarget[1]
    }

    if ($env:APPVEYOR) {
        $xunit_path = Get-Command "xunit.console.clr4.exe" | Select-Object -ExpandProperty Definition
        $extra = "/appveyor"
    }
    else {
        # We need to use paths without asterisks here
        $xunit_path = Resolve-Path $xunit
    }

    Write-Host "Running OpenCover/xUnit for '$project'..." -ForegroundColor "Green"
    $assembly = (Get-TestsOutputDir $project $target) + "/$project.dll"

    Exec {        
        .$opencover `"-target:$xunit_path`" `"-targetargs:$assembly /noshadow $extra`" `"-filter:$coverageFilter`" -mergeoutput `"-output:$coverageFile`" -register:user -returntargetcode
    }
}

### Merge functions

function Repack-Assembly($projectWithOptionalTarget, $internalizeAssemblies, $target) {
    $project = $projectWithOptionalTarget
    $target = $null

    if ($projectWithOptionalTarget -Is [System.Array]) {
        $project = $projectWithOptionalTarget[0]
        $target = $projectWithOptionalTarget[1]
    }

    Write-Host "Repacking '$project'/$target with $internalizeAssemblies..." -ForegroundColor "Green"

    $internalizePaths = @()

    $projectOutput = Get-SrcOutputDir $project $target

    foreach ($assembly in $internalizeAssemblies) {
        $internalizePaths += "$assembly.dll"
    }

    $primaryAssemblyPath = "$project.dll"

    Create-Directory $temp_dir

    Push-Location
    Set-Location -Path $projectOutput

    Exec { .$ilrepack `
        /out:"$temp_dir/$project.dll" `
        /target:library `
        /internalize `
        $primaryAssemblyPath `
        $internalizePaths `
    }

    Pop-Location

    Move-Files "$temp_dir/$project.*" $projectOutput
}

### Collect functions

function Collect-Tool($source) {
    Write-Host "Collecting tool '$source'..." -ForegroundColor "Green"

    $destination = "$build_dir/tools"

    Create-Directory $destination
    Copy-Files "$source" $destination
}

function Collect-Content($source) {
    Write-Host "Collecting content '$source'..." -ForegroundColor "Green"

    $destination = "$build_dir/content"

    Create-Directory $destination
    Copy-Files "$source" $destination
}

function Collect-Assembly($project, $target) {
    Write-Host "Collecting assembly '$target/$project'..." -ForegroundColor "Green"
    
    $source = (Get-SrcOutputDir $project $target) + "/$project.*"
    $destination = "$build_dir/$target"

    Create-Directory $destination
    Copy-Files $source $destination
}

function Collect-Localizations($project, $target) {
    Write-Host "Collecting localizations for '$target/$project'..." -ForegroundColor "Green"
    
    $output = (Get-SrcOutputDir $project $target)
    $dirs = Get-ChildItem -Path $output -Directory -Name

    foreach ($dir in $dirs) {
        $source = "$output/$dir/$project.resources.dll"

        if (Test-Path $source) {
            Write-Host "  Collecting '$dir' localization..."

            $destination = "$build_dir/$target/$dir"

            Create-Directory $destination
            Copy-Files $source $destination
        }
    }
}

function Collect-File($source) {
    Write-Host "Collecting file '$source'..." -ForegroundColor "Green"

    $destination = $build_dir;

    Create-Directory $destination
    Copy-Files $source $destination
}

### Pack functions

function Create-Package($project, $version) {
    Write-Host "Creating NuGet package for '$project'..." -ForegroundColor "Green"

    Create-Directory $temp_dir
    Copy-Files "$nuspec_dir/$project.nuspec" $temp_dir

    $commit = (git rev-parse HEAD)

    Try {
        Write-Host "Patching version with '$version'..." -ForegroundColor "DarkGray"
        Replace-Content "$nuspec_dir/$project.nuspec" '%version%' $version
        Write-Host "Patching commit hash with '$commit'..." -ForegroundColor "DarkGray"
        Replace-Content "$nuspec_dir/$project.nuspec" '%commit%' $commit
        Exec { .$nuget pack "$nuspec_dir/$project.nuspec" -OutputDirectory "$build_dir" -BasePath "$build_dir" -Version "$version" }
    }
    Finally {
        Move-Files "$temp_dir/$project.nuspec" $nuspec_dir
    }
}

### Version functions

function Get-SemanticVersion {
    $xml = [xml](Get-Content $directoryBuildProps)
    $versionPrefixNode = $xml.SelectSingleNode('Project/PropertyGroup/VersionPrefix')
    $versionSuffixNode = $xml.SelectSingleNode('Project/PropertyGroup/VersionSuffix')

    $versionPrefix = if ($versionPrefixNode) { $versionPrefixNode.InnerText } else { '1.0.0' }
    $versionSuffix = if ($versionSuffixNode) { $versionSuffixNode.InnerText } else { $null }

    $tag = $env:APPVEYOR_REPO_TAG_NAME
    if ($tag -And $tag.StartsWith("v$versionPrefix")) {
        $version = $tag.Substring(1)
        Write-Host "Using tag-based version '$version' for packages..." -ForegroundColor "Green"
        return $version
    }

    if ($env:APPVEYOR_BUILD_NUMBER) {
        $versionSuffix = "build." + $env:APPVEYOR_BUILD_NUMBER
        Write-Host "Using CI build suffix '$versionSuffix'..." -ForegroundColor "Green"
    }

    if ($versionPrefix) {
        if ($versionSuffix) {
            return $versionPrefix + '-' + $versionSuffix
        }
        return $versionPrefix
    }

    return $null;
}

function Get-PackageVersion {
    $version = Get-BuildVersion

	$tag = $env:APPVEYOR_REPO_TAG_NAME
    if ($tag -And $tag.StartsWith("v$version-")) {
        $version = $tag.Substring(1)
        Write-Host "Using tag-based version '$version' for packages..." -ForegroundColor "Green"
    }

    return $version
}

function Get-BuildVersion {
    $version = Get-SharedVersion
    $buildNumber = $env:APPVEYOR_BUILD_NUMBER

    if ($env:APPVEYOR_REPO_TAG -ne "True" -And $buildNumber -ne $null) {
        $version += "-build-" + $buildNumber.ToString().PadLeft(5, '0')
        Write-Host "Using CI build version '$version'..." -ForegroundColor "Green"
    }

    return $version
}

function Get-SharedVersion {
    $line = Get-Content "$sharedAssemblyInfo" | where {$_.Contains("AssemblyVersion")}
    $line.Split('"')[1]
}

function Update-SharedVersion($version) {
    Check-Version($version)
        
    $versionPattern = 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
    $versionAssembly = 'AssemblyVersion("' + $version + '")';

    if (Test-Path $sharedAssemblyInfo) {
        Write-Host "Patching '$sharedAssemblyInfo'..." -ForegroundColor "Green"
        Replace-Content "$sharedAssemblyInfo" $versionPattern $versionAssembly
    }
}

function Update-AppveyorVersion($version) {
    Check-Version($version)

    $versionPattern = "version: [0-9]+(\.([0-9]+|\*)){1,3}"
    $versionReplace = "version: $version"

    if (Test-Path $appVeyorConfig) {
        Write-Host "Patching '$appVeyorConfig'..." -ForegroundColor "Green"
        Replace-Content "$appVeyorConfig" $versionPattern $versionReplace
    }
}

function Check-Version($version) {
    if ($version -notmatch "[0-9]+(\.([0-9]+|\*)){1,3}") {
        Write-Error "Version number incorrect format: $version"
    }
}

### Archive functions

function Create-Archive($name) {
    Write-Host "Creating archive '$name.zip'..." -ForegroundColor "Green"
    Remove-Directory $temp_dir
    Compress-Archive -Path "$build_dir/*" -DestinationPath "$build_dir/$name.zip"
}

### Signing functions
# Requires Install-Module -Name SignPath, please see https://about.signpath.io/documentation/powershell/

function Sign-ArchiveContents($name, $project, $configuration) {
    if ($env:APPVEYOR_PULL_REQUEST_NUMBER) {
        Write-Host "Signing is skipped, because the required secrets are unavailable in pull requests for security reasons" -ForegroundColor "Yellow"
        return
    }

    $policy = "test-signing-policy"

    if ($env:APPVEYOR_REPO_TAG -eq "True") {
        $policy = "release-signing-policy"
    }

    if ($configuration -eq $null) {
        $configuration = "initial"
    }

    Write-Host "Using signing project '$project'..." -ForegroundColor "DarkGray"
    Write-Host "Using signing policy '$policy'..." -ForegroundColor "DarkGray"
    Write-Host "Using artifacts configuration '$configuration'..." -ForegroundColor "DarkGray"

    $archive = "$build_dir/$name.zip"

    Write-Host "Submitting archive '$archive' for signing..." -ForegroundColor "Green"
    Submit-SigningRequest -InputArtifactPath "$archive" -OrganizationId $env:SIGNPATH_ORGANIZATION_ID -ApiToken $env:SIGNPATH_API_TOKEN -ProjectSlug "$project" -SigningPolicySlug "$policy" -ArtifactConfigurationSlug "$configuration" -WaitForCompletion -OutputArtifactPath "$archive" -Force

    Write-Host "Unpacking signed files..." -ForegroundColor "Green"
    Expand-Archive -Path "$archive" -DestinationPath "$build_dir" -Force
}

### Common functions

function Create-Directory($dir) {
    New-Item -Path $dir -Type Directory -Force > $null
}

function Clean-Directory($dir) {
    If (Test-Path $dir) {
        Write-Host "Cleaning up '$dir'..." -ForegroundColor "DarkGray"
        Remove-Item "$dir/*" -Recurse -Force
    }
}

function Remove-File($file) {
    if (Test-Path $file) {
        Write-Host "Removing '$file'..." -ForegroundColor "DarkGray"
        Remove-Item $file -Force
    }
}

function Remove-Directory($dir) {
    if (Test-Path $dir) {
        Write-Host "Removing '$dir'..." -ForegroundColor "DarkGray"
        Remove-Item $dir -Recurse -Force
    }
}

function Copy-Files($source, $destination) {
    Copy-Item "$source" $destination -Force > $null
}

function Move-Files($source, $destination) {
    Move-Item "$source" $destination -Force > $null
}

function Replace-Content($file, $pattern, $substring) {
    (Get-Content $file) -Replace $pattern, $substring | Set-Content $file
}

function Get-SrcOutputDir($project, $target) {
    $result = _Get-OutputDir $src_dir $project $target

    Write-Host "  Using directory $result" -ForegroundColor "DarkGray"
    return $result
}

function Get-TestsOutputDir($project, $target) {
    $result = _Get-OutputDir $tests_dir $project $target

    Write-Host "  Using directory $result" -ForegroundColor "DarkGray"
    return $result
}

function _Get-OutputDir($dir, $project, $target) {
    $baseDir = "$dir/$project/bin"
    
    if ($target -And (Test-Path "$baseDir/$target/$config")) {
        return "$baseDir/$target/$config"
    }

    if ($target -And (Test-Path "$baseDir/$config/$target")) {
        return "$baseDir/$config/$target"
    }

    return "$baseDir/$config"
}
