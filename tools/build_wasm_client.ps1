
param(
    [string]$Address = "",
    [string]$Port = ""
)

$ErrorActionPreference = "Stop"
$builder = Join-Path $PSScriptRoot "build_wasm.ps1"
$arguments = @{
    OutputDirectory = "build/web-client"
    BuildTarget     = "client"
    Shell           = "client.html"
}
if ($Address) { $arguments.ClientAddress = $Address }
if ($Port) { $arguments.ClientPort = $Port }

& $builder @arguments
exit $LASTEXITCODE
