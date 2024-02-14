Include "src\psake-common.ps1"

Properties {
    $version = "0.4.1"
}

Task Default -Depends Pack

Task Collect -Depends Prepare -Description "Copy all artifacts to the build folder." {
    Collect-Tool "src\psake-common.ps1"
    Collect-Tool "src\psake-project.ps1"
    Collect-Tool "build.bat"
}

Task Pack -Depends Collect -Description "Create NuGet package." {
    Create-Package "Hangfire.Build" "$version"
    Create-Archive "Hangfire.Build-$version"
}

Task Sign -Depends Pack -Description "Sign artifacts." {
    Sign-ArchiveContents "Hangfire.Build-$version" "hangfire" "nuget-and-powershell-in-zip-file"
}