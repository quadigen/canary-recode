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

function Add-WireServiceTag([string]$Path) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $lines.Add($line)
    }

    $insertAfter = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^#\+build[ \t]+!js[ \t]*$') { $insertAfter = $index; break }
    }

    if ($insertAfter -lt 0) {
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^package[ \t]+') { $insertAfter = $index; break }
        }
    }
    if ($insertAfter -lt 0) { throw "Cannot find a place to add wire:service in $(Get-RelativePath $Path)" }

    if ($Check) {
        $script:OutdatedFiles.Add((Get-RelativePath $Path))
        return
    }

    $lines.Insert($insertAfter + 1, '// wire:service')
    $newText = [string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine
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

$constraintEntries = [System.Collections.Generic.List[object]]::new()
$constraintClassPattern = '(?s)\b(?<symbol>[A-Za-z][A-Za-z0-9_]*)_Class[ \t]*:=[ \t]*Class_Info[ \t]*\{(?<body>.*?)\}'
$constraintStepPattern = '(?m)^[ \t]*(?<name>[A-Za-z][A-Za-z0-9_]*_step)[ \t]*::[ \t]*proc[ \t]*\('
foreach ($file in $classFiles) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($classMatch in [regex]::Matches($source, $constraintClassPattern)) {
        $body = $classMatch.Groups['body'].Value
        if ($body -notmatch '\bparent[ \t]*=[ \t]*&Constraint_Class\b') { continue }
        $symbol = $classMatch.Groups['symbol'].Value
        $stepName = "${symbol}_step"
        $hasStep = $false
        foreach ($step in [regex]::Matches($source, $constraintStepPattern)) {
            if ($step.Groups['name'].Value -ceq $stepName) { $hasStep = $true; break }
        }
        if (!$hasStep) {
            throw "${symbol}_Class is a constraint but $(Get-RelativePath $file.FullName) has no $stepName proc"
        }
        $constraintEntries.Add([pscustomobject]@{
            Symbol = $symbol
            Step = $stepName
        })
    }
}
$constraintEntries = @($constraintEntries | Sort-Object Symbol)
$seenConstraints = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($constraint in $constraintEntries) {
    if (!$seenConstraints.Add($constraint.Symbol)) {
        throw "Duplicate constraint class '$($constraint.Symbol)'"
    }
}
$constraintLines = [System.Collections.Generic.List[string]]::new()
$constraintLines.Add('package classes')
$constraintLines.Add('')
$constraintLines.Add('// Generated by just wire. Do not edit by hand.')
$constraintLines.Add('')
$constraintLines.Add('Constraint_Steps := [?]Constraint_Step_Entry{')
foreach ($constraint in $constraintEntries) {
    $constraintLines.Add("`t{&$($constraint.Symbol)_Class, $($constraint.Step)},")
}
$constraintLines.Add('}')
Set-GeneratedFile (Join-Path $classesPath 'ConstraintRegistry.generated.odin') $constraintLines

$servicesPath = Join-Path $RootPath 'src/engine/services'
$serviceFiles = Get-OdinFiles $servicesPath @('Registry.odin')
$serviceClassPattern = '(?m)^[ \t]*(?<name>Register_[A-Za-z][A-Za-z0-9_]*_Class)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^classes\.Registry\b'
$serviceClassProcedures = foreach ($file in $serviceFiles) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    $nativeOnly = $source -match '(?m)^#\+build[ \t]+!js[ \t\r]*$'
    foreach ($registration in [regex]::Matches($source, $serviceClassPattern)) {
        [pscustomobject]@{
            Name = $registration.Groups['name'].Value
            NativeOnly = $nativeOnly
        }
    }
}
$serviceClassProcedures = @($serviceClassProcedures | Sort-Object @{ Expression = {
    if ($_.Name -eq 'Register_DataModel_Class') { 0 }
    elseif ($_.Name -eq 'Register_Service_Class') { 1 }
    else { 2 }
} }, @{ Expression = { $_.Name } })
$seenServiceClassProcedures = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$serviceClassLines = foreach ($procedure in $serviceClassProcedures) {
    if (!$seenServiceClassProcedures.Add($procedure.Name)) {
        throw "Duplicate service class registration procedure '$($procedure.Name)'"
    }
    if ($procedure.NativeOnly) {
        "`twhen ODIN_OS != .JS { $($procedure.Name)(registry.classes) }"
    } else {
        "`t$($procedure.Name)(registry.classes)"
    }
}
Set-GeneratedRegion (Join-Path $servicesPath 'Registry.odin') 'service-classes' $serviceClassLines

$serviceEntries = [System.Collections.Generic.List[object]]::new()
foreach ($file in $serviceFiles) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    $globalMatch = [regex]::Match($source, '(?m)^[ \t]*//[ \t]*wire:service(?:[ \t]+global="(?<global>[A-Za-z_][A-Za-z0-9_]*)")?[ \t\r]*$')
    $globalName = if ($globalMatch.Success) { $globalMatch.Groups['global'].Value } else { '' }
    $isService = $false                                              # NEW

    foreach ($registration in [regex]::Matches($source, $serviceClassPattern)) {
        $procedure = $registration.Groups['name'].Value
        $symbol = $procedure.Substring('Register_'.Length, $procedure.Length - 'Register_'.Length - '_Class'.Length)
        $classPattern = '(?s)\b' + [regex]::Escape($symbol) + '_Class[ \t]*:=[ \t]*classes\.Class_Info[ \t]*\{(?<body>.*?)\}'
        $classMatch = [regex]::Match($source, $classPattern)
        if (!$classMatch.Success) { throw "Cannot find ${symbol}_Class metadata in $(Get-RelativePath $file.FullName)" }

        $body = $classMatch.Groups['body'].Value
        if ($body -notmatch '\bparent[ \t]*=[ \t]*&Service_Class\b') { continue }
        $isService = $true                                           # NEW
        $nameMatch = [regex]::Match($body, '\bname[ \t]*=[ \t]*"(?<name>[^"]+)"')
        if (!$nameMatch.Success) { throw "${symbol}_Class has no string name in $(Get-RelativePath $file.FullName)" }
        $serviceEntries.Add([pscustomobject]@{
            Name = $nameMatch.Groups['name'].Value
            ClassName = $nameMatch.Groups['name'].Value
            GlobalName = $globalName
            NativeOnly = $source -match '(?m)^#\+build[ \t]+!js[ \t\r]*$'
        })
    }

    if ($isService -and -not $globalMatch.Success) {
        Add-WireServiceTag $file.FullName
    }
}

$seenServices = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$serviceLines = [System.Collections.Generic.List[string]]::new()
function Get-ServiceRegistration([object]$Service) {
    if ($Service.GlobalName) {
        return "Register_Service(registry, `"$($Service.Name)`", `"$($Service.ClassName)`", `"$($Service.GlobalName)`")"
    } else {
        return "Register_Service(registry, `"$($Service.Name)`", `"$($Service.ClassName)`")"
    }
}
$sortedServices = @($serviceEntries | Sort-Object Name)
foreach ($service in $sortedServices) {
    if (!$seenServices.Add($service.Name)) { throw "Duplicate wired service '$($service.Name)'" }
    $registration = Get-ServiceRegistration $service
    if ($service.NativeOnly) {
        $serviceLines.Add("`twhen ODIN_OS != .JS { $registration }")
    } else {
        $serviceLines.Add("`t$registration")
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

# KNE datatype dispatch. Every engine datatype exposes a Push_<Name> proc
# taking its concrete type, so the wire tool can generate the copy-in/copy-out
# adapters the KNE host needs. Adding a datatype and running `just wire` wires
# the extension ABI too; no per-type host code.
$datatypeTypeByName = @{}
$datatypeHasRegistry = @{}
foreach ($file in $datatypeFiles) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    foreach ($name in $bindings) {
        $pattern = '(?s)Push_' + [regex]::Escape($name) + '[ \t]*::[ \t]*proc[ \t]*\((?<params>[^)]*)\)'
        $match = [regex]::Match($source, $pattern)
        if (!$match.Success) { continue }
        $params = $match.Groups['params'].Value
        $typeMatches = [regex]::Matches($params, ':[ \t]*(?<type>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:,|$)')
        if ($typeMatches.Count -eq 0) { continue }
        $datatypeTypeByName[$name] = $typeMatches[$typeMatches.Count - 1].Groups['type'].Value
        $datatypeHasRegistry[$name] = $params -match '(?<![A-Za-z0-9_])registry(?![A-Za-z0-9_])'
    }
}
$missingTypes = @($datatypeEntries | Where-Object { -not $datatypeTypeByName.ContainsKey($_.Name) } | ForEach-Object { $_.Name })
if ($missingTypes.Count -gt 0) {
    throw "Datatype Push_<Name> procs missing or have an unexpected signature: $($missingTypes -join ', ')"
}

# Fixed-layout datatypes cross the ABI as their own value kind; types that own
# heap state or have no fixed C layout cross as opaque `Datatype` handles.
$kneKindByName = @{
    Vector2 = 20; Vector3 = 21; Vector2int16 = 22; Vector3int16 = 23
    CFrame = 24; Color3 = 25; UDim = 26; UDim2 = 27; Ray = 28; Rect = 29
    Region3 = 30; Region3int16 = 31; NumberRange = 32
    NumberSequenceKeypoint = 33; ColorSequenceKeypoint = 34
    Axes = 35; Faces = 36; PhysicalProperties = 37; Quaternion = 38
    TweenInfo = 39; DateTime = 40; UniqueId = 41; PathWaypoint = 42
    SecurityCapabilities = 43; DockWidgetPluginGuiInfo = 44
}

if ($datatypeEntries.Count -gt 36) { throw "Engine datatype tags overlap the extension tag range" }

$kneDatatypeLines = [System.Collections.Generic.List[string]]::new()
$kneDatatypeLines.Add('package extensions')
$kneDatatypeLines.Add('')
$kneDatatypeLines.Add('// Generated by just wire. Do not edit by hand.')
$kneDatatypeLines.Add('')
$kneDatatypeLines.Add('import datatypes "../datatypes"')
$kneDatatypeLines.Add('import vm "../vm"')
$kneDatatypeLines.Add('')
$kneDatatypeLines.Add('KNE_Engine_Datatype :: struct {')
$kneDatatypeLines.Add("`tname:  string,")
$kneDatatypeLines.Add("`tfield: string,")
$kneDatatypeLines.Add("`ttag:   u32,")
$kneDatatypeLines.Add("`tkind:  KNE_Value_Kind,")
$kneDatatypeLines.Add("`tsize:  int,")
$kneDatatypeLines.Add("`tpush:  proc(L: ^vm.State, registry: ^datatypes.Registry, handle: rawptr),")
$kneDatatypeLines.Add("`tget:   proc(L: ^vm.State, index: int, registry: ^datatypes.Registry) -> rawptr,")
$kneDatatypeLines.Add('}')
$kneDatatypeLines.Add('')
foreach ($entry in $datatypeEntries) {
    $type = $datatypeTypeByName[$entry.Name]
    $kneDatatypeLines.Add("kne_push_$($entry.Field) :: proc(L: ^vm.State, registry: ^datatypes.Registry, handle: rawptr) {")
    if ($datatypeHasRegistry[$entry.Name]) {
        $kneDatatypeLines.Add("`tdatatypes.Push_$($entry.Name)(L, registry, (cast(^datatypes.$type)handle)^)")
    } else {
        $kneDatatypeLines.Add("`tdatatypes.Push_$($entry.Name)(L, (cast(^datatypes.$type)handle)^)")
    }
    $kneDatatypeLines.Add('}')
    $kneDatatypeLines.Add('')
    $kneDatatypeLines.Add("kne_get_$($entry.Field) :: proc(L: ^vm.State, index: int, registry: ^datatypes.Registry) -> rawptr {")
    $kneDatatypeLines.Add("`treturn datatypes.KNE_Require_Value(L, index, &registry.$($entry.Field))")
    $kneDatatypeLines.Add('}')
    $kneDatatypeLines.Add('')
}
$kneDatatypeLines.Add('KNE_Engine_Datatypes := [?]KNE_Engine_Datatype{')
for ($index = 0; $index -lt $datatypeEntries.Count; $index += 1) {
    $entry = $datatypeEntries[$index]
    $type = $datatypeTypeByName[$entry.Name]
    $kind = if ($kneKindByName.ContainsKey($entry.Name)) { $kneKindByName[$entry.Name] } else { 60 }
    $kneDatatypeLines.Add("`t{")
    $kneDatatypeLines.Add("`t`tname = `"$($entry.Name)`",")
    $kneDatatypeLines.Add("`t`tfield = `"$($entry.Field)`",")
    $kneDatatypeLines.Add("`t`ttag = datatypes.DATATYPE_TAG_BASE + $index,")
    $kneDatatypeLines.Add("`t`tkind = KNE_Value_Kind($kind),")
    $kneDatatypeLines.Add("`t`tsize = size_of(datatypes.$type),")
    $kneDatatypeLines.Add("`t`tpush = kne_push_$($entry.Field),")
    $kneDatatypeLines.Add("`t`tget = kne_get_$($entry.Field),")
    $kneDatatypeLines.Add("`t},")
}
$kneDatatypeLines.Add('}')
Set-GeneratedFile (Join-Path $RootPath 'src/engine/extensions/KneDatatypes.generated.odin') $kneDatatypeLines

$globalsPath = Join-Path $RootPath 'src/engine/global'
$globalFiles = Get-OdinFiles $globalsPath @('Registry.odin')
$globalProcedures = Get-UniqueMatches $globalFiles '(?m)^[ \t]*(?<name>Register_[A-Za-z][A-Za-z0-9_]*_Globals?)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^Registry\b'
Set-GeneratedRegion (Join-Path $globalsPath 'Registry.odin') 'globals' @(
    $globalProcedures | ForEach-Object { "`t$_(registry)" }
)

$packagesPath = Join-Path $RootPath 'src/engine/packages'
$packageEntries = [System.Collections.Generic.List[object]]::new()
foreach ($directory in (Get-ChildItem -LiteralPath $packagesPath -Directory | Sort-Object Name)) {
    $markers = [System.Collections.Generic.List[object]]::new()
    foreach ($file in (Get-OdinFiles $directory.FullName)) {
        $source = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($match in [regex]::Matches($source, '(?m)^[ \t]*//[ \t]*wire:package[ \t]+name="(?<name>[A-Za-z_][A-Za-z0-9_]*)"[ \t\r]*$')) {
            $markers.Add([pscustomobject]@{ Name = $match.Groups['name'].Value; File = $file.FullName })
        }
    }
    if ($markers.Count -eq 0) { continue }
    if ($markers.Count -ne 1) { throw "Package directory '$($directory.Name)' must contain exactly one wire:package marker" }
    if ($markers[0].Name -cne $directory.Name) {
        throw "Package marker '$($markers[0].Name)' must match directory '$($directory.Name)' in $(Get-RelativePath $markers[0].File)"
    }
    $packageEntries.Add([pscustomobject]@{
        Name = $markers[0].Name
        Alias = ConvertTo-SnakeCase $markers[0].Name
        Field = ConvertTo-SnakeCase $markers[0].Name
    })
}

$duplicatePackageFields = @($packageEntries | Group-Object Field | Where-Object Count -gt 1)
if ($duplicatePackageFields.Count -gt 0) { throw "Package names collide when lowercased: $($duplicatePackageFields.Name -join ', ')" }

$packageRegistryLines = [System.Collections.Generic.List[string]]::new()
$packageRegistryLines.Add('package packages')
$packageRegistryLines.Add('')
$packageRegistryLines.Add('// Generated by just wire. Do not edit by hand.')
foreach ($entry in $packageEntries) {
    $packageRegistryLines.Add("import $($entry.Alias) `"$($entry.Name)`"")
}
$packageRegistryLines.Add('')
$packageRegistryLines.Add('Package_Contexts :: struct {')
foreach ($entry in $packageEntries) {
    $packageRegistryLines.Add("`t$($entry.Field): $($entry.Alias).Context,")
}
$packageRegistryLines.Add('}')
$packageRegistryLines.Add('')
$packageRegistryLines.Add('Register_Default_Packages :: proc(registry: ^Registry) {')
foreach ($entry in $packageEntries) {
    $packageRegistryLines.Add("`tRegister_Package(registry, `"$($entry.Name)`", $($entry.Alias).Install, $($entry.Alias).Begin_Frame, &registry.contexts.$($entry.Field))")
}
$packageRegistryLines.Add('}')
Set-GeneratedFile (Join-Path $packagesPath 'PackageRegistry.generated.odin') $packageRegistryLines

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
Write-Host "Discovered $($classProcedures.Count) classes, $($constraintEntries.Count) constraints, $($serviceEntries.Count) services, $($datatypeEntries.Count) datatypes, $($globalProcedures.Count) global hooks, $($packageEntries.Count) packages, and $($enumNames.Count) enums."
