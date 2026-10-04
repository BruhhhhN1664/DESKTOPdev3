# One-shot setup for Windows PowerShell: creates the migration (once), applies it, builds and tests.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

dotnet tool update --global dotnet-ef
if ($LASTEXITCODE -ne 0) { dotnet tool install --global dotnet-ef }

dotnet restore

$infra = "src/EquipmentBorrowing.Infrastructure"
if (-not (Test-Path "$infra/Migrations")) {
    dotnet ef migrations add InitialCreate --project $infra --output-dir Migrations
} else {
    Write-Host "Migrations folder already exists - skipping 'migrations add'."
}

dotnet ef database update --project $infra
dotnet build
dotnet test
Write-Host ""
Write-Host "Done. Run the app with:  dotnet run --project src/EquipmentBorrowing.Desktop"
