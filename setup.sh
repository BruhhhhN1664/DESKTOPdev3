#!/usr/bin/env bash
# One-shot setup for macOS / Linux: creates the migration (once), applies it, builds and tests.
set -euo pipefail
cd "$(dirname "$0")"

dotnet tool update --global dotnet-ef || dotnet tool install --global dotnet-ef
dotnet restore

INFRA=src/EquipmentBorrowing.Infrastructure
if [ ! -d "$INFRA/Migrations" ]; then
  dotnet ef migrations add InitialCreate --project "$INFRA" --output-dir Migrations
else
  echo "Migrations folder already exists - skipping 'migrations add'."
fi

dotnet ef database update --project "$INFRA"
dotnet build
dotnet test
echo
echo "Done. Run the app with:  dotnet run --project src/EquipmentBorrowing.Desktop"
