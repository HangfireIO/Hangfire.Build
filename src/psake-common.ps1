Properties {
    ### Directories
    $base_dir = resolve-path .
    $build_dir = "$base_dir\build"
    $src_dir = "$base_dir\src"
    $tests_dir = "$base_dir\tests"
    $package_dir = "$base_dir\packages"
    $nuspec_dir = "$base_dir\nuspecs"
    $temp_dir = "$build_dir\temp"
    $framework_dir =  $env:windir + "\Microsoft.Net\Framework\v4.0.30319"

    ### Tools
    $nuget = "$base_dir\.nuget\nuget.exe"
    $ilmerge = "$package_dir\ilmerge.*\tools\ilmerge.exe"
    $xunit = "$package_dir\xunit.runners*\tools\xunit.console.clr4.exe"
    $7zip = "$package_dir\7-Zip.CommandLine.*\tools\7za.exe"
    $opencover = "$package_dir\OpenCover.*\opencover.console.exe"

    ### AppVeyor-related
    $appVeyorConfig = "$base_dir\appveyor.yml"
    $appVeyor = $env:APPVEYOR

    ### Project information
    $solution_path = "$base_dir\$solution"
    $config = "Release"    
    $sharedAssemblyInfo = "$src_dir\SharedAssemblyInfo.cs"
}

## Tasks

Task Restore -Description "Restore NuGet packages for solution." {
    "Restoring NuGet packages for '$solution'..."
    Exec { .$nuget restore $solution }
}

Task Clean -Description "Clean up build and project folders." {
    Clean-Directory $build_dir

    if ($solution) {
        "Cleaning up '$solution'..."
        Exec { msbuild $solution_path /target:Clean /nologo /verbosity:minimal }
    }
}

Task Compile -Depends Clean, Restore -Description "Compile all the projects in a solution." {
    "Compiling '$solution'..."

    $extra = $null
    if ($appVeyor) {
        $extra = "/logger:C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll"
    }

    Exec { msbuild $solution_path /p:Configuration=$config /nologo /verbosity:minimal $extra }
}

Task Version -Description "Patch AssemblyInfo and AppVeyor version files." {
    $newVersion = Read-Host "Please enter a new version number (major.minor.patch)"
    Update-SharedVersion $newVersion
    Update-AppVeyorVersion $newVersion
}

## Functions

### Test functions

function Run-XunitTests($project, $target) {
    $assembly = (Get-TestsOutputDir $project $target) + "\$project.dll"

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

    $assembly = (Get-TestsOutputDir $project $target) + "\$project.dll"

    Exec {        
        .$opencover `"-target:$xunit_path`" `"-targetargs:$assembly /noshadow $extra`" `"-filter:$coverageFilter`" -mergeoutput `"-output:$coverageFile`" -register:user -returntargetcode
    }
}

### Merge functions

function Merge-Assembly($projectWithOptionalTarget, $internalizeAssemblies, $target) {
    $project = $projectWithOptionalTarget
    $target = $null

    if ($projectWithOptionalTarget -Is [System.Array]) {
        $project = $projectWithOptionalTarget[0]
        $target = $projectWithOptionalTarget[1]
    }

    "Merging '$project' with $internalizeAssemblies..."

    $internalizePaths = @()

    $projectOutput = Get-SrcOutputDir $project $target

    foreach ($assembly in $internalizeAssemblies) {
        $internalizePaths += "$projectOutput\$assembly.dll"
    }

    $primaryAssemblyPath = "$projectOutput\$project.dll"

    Create-Directory $temp_dir
    
    Exec { .$ilmerge /targetplatform:"v4,$framework_dir" `
        /out:"$temp_dir\$project.dll" `
        /target:library `
        /internalize `
        $primaryAssemblyPath `
        $internalizePaths `
    }

    Move-Files "$temp_dir\$project.*" (Get-SrcOutputDir $project $target)
}

### Collect functions

function Collect-Tool($source) {
    "Collecting tool '$source'..."

    $destination = "$build_dir\tools"

    Create-Directory $destination
    Copy-Files "$source" $destination
}

function Collect-Content($source) {
    "Collecting content '$source'..."

    $destination = "$build_dir\content"

    Create-Directory $destination
    Copy-Files "$source" $destination
}

function Collect-Assembly($project, $target) {
    "Collecting assembly '$target/$project'..."
    
    $source = (Get-SrcOutputDir $project $target) + "\$project.*"
    $destination = "$build_dir\$target"

    Create-Directory $destination
    Copy-Files $source $destination
}

### Pack functions

function Create-Package($project, $version) {
    Create-Directory $temp_dir
    Copy-Files "$nuspec_dir\$project.nuspec" $temp_dir

    Try {
        Replace-Content "$nuspec_dir\$project.nuspec" '0.0.0' $version
        Exec { .$nuget pack "$nuspec_dir\$project.nuspec" -OutputDirectory "$build_dir" -BasePath "$build_dir" -Version $version -Symbols }
    }
    Finally {
        Move-Files "$temp_dir\$project.nuspec" $nuspec_dir
    }
}

### Version functions

function Get-PackageVersion {
    $version = Get-BuildVersion

	$tag = $env:APPVEYOR_REPO_TAG_NAME
    if ($tag -And $tag.StartsWith("v$version-")) {
        "Using tag-based version for packages."
        $version = $tag.Substring(1)
    }

    return $version
}

function Get-BuildVersion {
    $version = Get-SharedVersion
    $buildNumber = $env:APPVEYOR_BUILD_NUMBER

    if ($env:APPVEYOR_REPO_TAG -ne "True" -And $buildNumber -ne $null) {
        "Using CI build version."
        $version += "-" + $buildNumber.ToString().PadLeft(5, '0')
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
        "Patching $sharedAssemblyInfo..."
        Replace-Content "$sharedAssemblyInfo" $versionPattern $versionAssembly
    }
}

function Update-AppveyorVersion($version) {
    Check-Version($version)

    $versionPattern = "version: [0-9]+(\.([0-9]+|\*)){1,3}"
    $versionReplace = "version: $version"

    if (Test-Path $appVeyorConfig) {
        "Patching $appVeyorConfig..."
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
    Remove-Directory $temp_dir
    Create-Zip "$build_dir\$name.zip" "$build_dir"
}

function Create-Zip($file, $dir){
    if (Test-Path -path $file) { Remove-Item $file }
    Create-Directory $dir
    Exec { & $7zip a -mx -tzip $file $dir\* } 
}

### Common functions

function Create-Directory($dir) {
    New-Item -Path $dir -Type Directory -Force > $null
}

function Clean-Directory($dir) {
    If (Test-Path $dir) {
        "Cleaning up '$dir'..."
        Remove-Item "$dir\*" -Recurse -Force
    }
}

function Remove-File($file) {
    if (Test-Path $file) {
        "Removing '$file'..."
        Remove-Item $file -Force
    }
}

function Remove-Directory($dir) {
    if (Test-Path $dir) {
        "Removing '$dir'..."
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
    (gc $file) -Replace $pattern, $substring | sc $file
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
    $baseDir = "$dir\$project\bin"
    
    if ($target -And (Test-Path "$baseDir\$target\$config")) {
        return "$baseDir\$target\$config"
    }

    if ($target -And (Test-Path "$baseDir\$config\$target")) {
        return "$baseDir\$config\$target"
    }

    return "$baseDir\$config"
}
