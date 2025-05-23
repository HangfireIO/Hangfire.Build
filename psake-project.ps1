Include "src\psake-common.ps1"

Task Default -Depends Pack

Task Collect -Depends Prepare -Description "Copy all artifacts to the build folder." {
    Collect-Tool "src\psake-common.ps1"
    Collect-Tool "src\psake-project.ps1"
    Collect-Tool "build.bat"
    Collect-File "README.md"
    Collect-File "icon.png"
}

Task Pack -Depends Collect -Description "Create NuGet package." {
    $version = Get-SemanticVersion
    Create-Package "Hangfire.Build" "$version"
    Create-Archive "Hangfire.Build-$version"
}

Task Sign -Depends Pack -Description "Sign artifacts." {
    $version = Get-SemanticVersion
    Sign-ArchiveContents "Hangfire.Build-$version" "hangfire" "nuget-and-powershell-in-zip-file"
}