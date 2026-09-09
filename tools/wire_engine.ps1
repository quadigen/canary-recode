[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$RootPath = [System.IO.Path]::GetFullPath($RootPath)
$script:ChangedFiles = [System.Collections.Generic.List[string]]::new()
$script:OutdatedFiles = [System.Collections.Generic.List[string]]::new()

function Get-RelativePath([string]$Path) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $RootPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
}

function Get-OdinFiles([string]$Directory, [string[]]$Exclude = @()) {
    return Get-ChildItem -LiteralPath $Directory -File -Filter '*.odin' |
        Where-Object { $_.Name -notin $Exclude -and $_.Name -notlike '*.generated.odin' } |
        Sort-Object Name
}

function Get-UniqueMatches(
    [System.IO.FileInfo[]]$Files,
    [string]$Pattern
) {
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($file in $Files) {
        $source = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($match in [regex]::Matches($source, $Pattern)) {
            [void]$names.Add($match.Groups['name'].Value)
        }
    }
    return @($names | Sort-Object)
}

function ConvertTo-SnakeCase([string]$Name) {
    $withAcronymBoundaries = [regex]::Replace($Name, '([A-Z]+)([A-Z][a-z])', '$1_$2')
    $withWordBoundaries = [regex]::Replace($withAcronymBoundaries, '([a-z0-9])([A-Z])', '$1_$2')
    return $withWordBoundaries.ToLowerInvariant()
}

function Set-GeneratedRegion(
    [string]$Path,
    [string]$Region,
    [string[]]$GeneratedLines
) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $lines.Add($line)
    }

    $beginMarker = "// wire:begin $Region"
    $endMarker = "// wire:end $Region"
    $beginIndex = -1
    $endIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq $beginMarker) {
            if ($beginIndex -ne -1) { throw "Duplicate '$beginMarker' in $(Get-RelativePath $Path)" }
            $beginIndex = $index
        }
        if ($lines[$index].Trim() -eq $endMarker) {
            if ($endIndex -ne -1) { throw "Duplicate '$endMarker' in $(Get-RelativePath $Path)" }
            $endIndex = $index
        }
    }

    if ($beginIndex -lt 0 -or $endIndex -lt 0 -or $endIndex -le $beginIndex) {
        throw "Missing or invalid wire region '$Region' in $(Get-RelativePath $Path)"
    }

    $result = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -le $beginIndex; $index++) { $result.Add($lines[$index]) }
    foreach ($line in $GeneratedLines) { $result.Add($line) }
    for ($index = $endIndex; $index -lt $lines.Count; $index++) { $result.Add($lines[$index]) }

    $newText = [string]::Join([Environment]::NewLine, $result) + [Environment]::NewLine
    $oldText = [System.IO.File]::ReadAllText($Path)
    if ($oldText -ceq $newText) { return }

    if ($Check) {
        $script:OutdatedFiles.Add((Get-RelativePath $Path))
        return
    }

    [System.IO.File]::WriteAllText($Path, $newText, [System.Text.UTF8Encoding]::new($false))
    $script:ChangedFiles.Add((Get-RelativePath $Path))
}

function Set-GeneratedFile([string]$Path, [string[]]$Lines) {
    $newText = [string]::Join([Environment]::NewLine, $Lines) + [Environment]::NewLine
    $oldText = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { "" }
    if ($oldText -ceq $newText) { return }

    if ($Check) {
        $script:OutdatedFiles.Add((Get-RelativePath $Path))
        return
    }

    $directory = Split-Path -Parent $Path
    if ($directory) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
    [System.IO.File]::WriteAllText($Path, $newText, [System.Text.UTF8Encoding]::new($false))
    $script:ChangedFiles.Add((Get-RelativePath $Path))
}

$classesPath = Join-Path $RootPath 'src/engine/classes'
$classFiles = Get-OdinFiles $classesPath @('Registry.odin')
$classProcedures = Get-UniqueMatches $classFiles '(?m)^[ \t]*(?<name>Register_[A-Za-z][A-Za-z0-9_]*)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^Registry\b'
$classProcedures = @($classProcedures | Sort-Object @{ Expression = { if ($_ -eq 'Register_Instance') { 0 } else { 1 } } }, @{ Expression = { $_ } })
Set-GeneratedRegion (Join-Path $classesPath 'Registry.odin') 'classes' @(
    $classProcedures | ForEach-Object { "`t$_(registry)" }
)

$servicesPath = Join-Path $RootPath 'src/engine/services'
$serviceFiles = Get-OdinFiles $servicesPath @('Registry.odin')
$serviceClassPattern = '(?m)^[ \t]*(?<name>Register_[A-Za-z][A-Za-z0-9_]*_Class)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^classes\.Registry\b'
$serviceClassProcedures = Get-UniqueMatches $serviceFiles $serviceClassPattern
$serviceClassProcedures = @($serviceClassProcedures | Sort-Object @{ Expression = {
    if ($_ -eq 'Register_DataModel_Class') { 0 }
    elseif ($_ -eq 'Register_Service_Class') { 1 }
    else { 2 }
} }, @{ Expression = { $_ } })
Set-GeneratedRegion (Join-Path $servicesPath 'Registry.odin') 'service-classes' @(
    $serviceClassProcedures | ForEach-Object { "`t$_(registry.classes)" }
)

$serviceEntries = [System.Collections.Generic.List[object]]::new()
foreach ($file in $serviceFiles) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    $globalMatch = [regex]::Match($source, '(?m)^[ \t]*//[ \t]*wire:service(?:[ \t]+global="(?<global>[A-Za-z_][A-Za-z0-9_]*)")?[ \t]*$')
    $globalName = if ($globalMatch.Success) { $globalMatch.Groups['global'].Value } else { '' }

    foreach ($registration in [regex]::Matches($source, $serviceClassPattern)) {
        $procedure = $registration.Groups['name'].Value
        $symbol = $procedure.Substring('Register_'.Length, $procedure.Length - 'Register_'.Length - '_Class'.Length)
        $classPattern = '(?s)\b' + [regex]::Escape($symbol) + '_Class[ \t]*:=[ \t]*classes\.Class_Info[ \t]*\{(?<body>.*?)\}'
        $classMatch = [regex]::Match($source, $classPattern)
        if (!$classMatch.Success) { throw "Cannot find ${symbol}_Class metadata in $(Get-RelativePath $file.FullName)" }

        $body = $classMatch.Groups['body'].Value
        if ($body -notmatch '\bparent[ \t]*=[ \t]*&Service_Class\b') { continue }
        $nameMatch = [regex]::Match($body, '\bname[ \t]*=[ \t]*"(?<name>[^"]+)"')
        if (!$nameMatch.Success) { throw "${symbol}_Class has no string name in $(Get-RelativePath $file.FullName)" }
        $serviceEntries.Add([pscustomobject]@{
            Name = $nameMatch.Groups['name'].Value
            ClassName = $nameMatch.Groups['name'].Value
            GlobalName = $globalName
        })
    }
}

$seenServices = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$serviceLines = [System.Collections.Generic.List[string]]::new()
foreach ($service in ($serviceEntries | Sort-Object Name)) {
    if (!$seenServices.Add($service.Name)) { throw "Duplicate wired service '$($service.Name)'" }
    if ($service.GlobalName) {
        $serviceLines.Add("`tRegister_Service(registry, `"$($service.Name)`", `"$($service.ClassName)`", `"$($service.GlobalName)`")")
    } else {
        $serviceLines.Add("`tRegister_Service(registry, `"$($service.Name)`", `"$($service.ClassName)`")")
    }
}
Set-GeneratedRegion (Join-Path $servicesPath 'Registry.odin') 'services' $serviceLines

$datatypesPath = Join-Path $RootPath 'src/engine/datatypes'
$datatypeFiles = Get-OdinFiles $datatypesPath @('LuaRegistry.odin')
$bindingPattern = '(?m)^[ \t]*(?<name>[A-Za-z][A-Za-z0-9_]*)_Luau_Binding[ \t]*::[ \t]*proc\b'
$installPattern = '(?m)^[ \t]*(?<name>[A-Za-z][A-Za-z0-9_]*)_Install_Fields[ \t]*::[ \t]*proc\b'
$bindings = Get-UniqueMatches $datatypeFiles $bindingPattern
$installers = Get-UniqueMatches $datatypeFiles $installPattern
$missingInstallers = @($bindings | Where-Object { $_ -notin $installers })
$missingBindings = @($installers | Where-Object { $_ -notin $bindings })
if ($missingInstallers.Count -gt 0) { throw "Datatype bindings missing *_Install_Fields: $($missingInstallers -join ', ')" }
if ($missingBindings.Count -gt 0) { throw "Datatype installers missing *_Luau_Binding: $($missingBindings -join ', ')" }

$datatypeEntries = @($bindings | ForEach-Object {
    [pscustomobject]@{ Name = $_; Field = ConvertTo-SnakeCase $_ }
} | Sort-Object Name)
$duplicateFields = @($datatypeEntries | Group-Object Field | Where-Object Count -gt 1)
if ($duplicateFields.Count -gt 0) { throw "Datatype names collide when lowercased: $($duplicateFields.Name -join ', ')" }
$datatypeTagBase = 64
$nativeUserdataMaxTag = 127
if ($datatypeEntries.Count -gt ($nativeUserdataMaxTag - $datatypeTagBase + 1)) {
    throw "Too many wired datatypes for Luau userdata tags $datatypeTagBase..$nativeUserdataMaxTag"
}

$datatypeRegistryPath = Join-Path $datatypesPath 'LuaRegistry.odin'
Set-GeneratedRegion $datatypeRegistryPath 'datatype-fields' @(
    $datatypeEntries | ForEach-Object { "`t$($_.Field): vm.Userdata_Binding," }
)
Set-GeneratedRegion $datatypeRegistryPath 'datatype-bindings' @(
    $datatypeEntries | ForEach-Object { "`tregistry.$($_.Field) = $($_.Name)_Luau_Binding()" }
)
Set-GeneratedRegion $datatypeRegistryPath 'datatype-tags' @(
    for ($index = 0; $index -lt $datatypeEntries.Count; $index++) {
        "`tregistry.$($datatypeEntries[$index].Field).tag = DATATYPE_TAG_BASE + $index"
    }
)
Set-GeneratedRegion $datatypeRegistryPath 'datatype-contexts' @(
    $datatypeEntries | ForEach-Object {
        "`tregistry.$($_.Field).ctx = &registry.$($_.Field)"
        "`tregistry.$($_.Field).owner = registry"
    }
)
Set-GeneratedRegion $datatypeRegistryPath 'datatype-libraries' @(
    $datatypeEntries | ForEach-Object { "`tinstall_library(vm_state, `"$($_.Name)`", &registry.$($_.Field), $($_.Name)_Install_Fields)" }
)

$globalsPath = Join-Path $RootPath 'src/engine/global'
$globalFiles = Get-OdinFiles $globalsPath @('Registry.odin')
$globalProcedures = Get-UniqueMatches $globalFiles '(?m)^[ \t]*(?<name>Register_[A-Za-z][A-Za-z0-9_]*_Globals?)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^Registry\b'
Set-GeneratedRegion (Join-Path $globalsPath 'Registry.odin') 'globals' @(
    $globalProcedures | ForEach-Object { "`t$_(registry)" }
)

$enumInputPath = Join-Path $RootPath 'src/engine/enum/enum.odin'
$enumOutputPath = Join-Path $RootPath 'src/engine/enum/LuaEnumGenerated.odin'
$enumSource = [System.IO.File]::ReadAllText($enumInputPath)
$enumNames = @([regex]::Matches($enumSource, '(?m)^(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*::\s*enum(?:\s+[^\s{]+)?\s*\{') |
    ForEach-Object { $_.Groups['name'].Value })
if ($enumNames.Count -eq 0) { throw "No enum declarations found in $(Get-RelativePath $enumInputPath)" }
$enumLines = [System.Collections.Generic.List[string]]::new()
$enumLines.Add('package engine_enums')
$enumLines.Add('')
$enumLines.Add('// Generated by just wire. Do not edit by hand.')
$enumLines.Add('Register_Default_Enums :: proc(registry: ^Registry) {')
foreach ($name in $enumNames) { $enumLines.Add("`tRegister_Reflected_Enum(registry, `"$name`", $name)") }
$enumLines.Add('}')
Set-GeneratedFile $enumOutputPath $enumLines

$outdatedFiles = @($script:OutdatedFiles | Sort-Object -Unique)
$changedFiles = @($script:ChangedFiles | Sort-Object -Unique)

if ($Check -and $outdatedFiles.Count -gt 0) {
    Write-Error "Engine wiring is out of date: $($outdatedFiles -join ', '). Run 'just wire'."
}

if ($changedFiles.Count -eq 0) {
    Write-Host "Engine wiring is up to date."
} else {
    Write-Host "Updated engine wiring: $($changedFiles -join ', ')"
}
Write-Host "Discovered $($classProcedures.Count) classes, $($serviceEntries.Count) services, $($datatypeEntries.Count) datatypes, $($globalProcedures.Count) global hooks, and $($enumNames.Count) enums."
