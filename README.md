# Campus Equipment Borrowing System

ITSD 81 - Desktop Application Development

> **Pair:** _Name 1_ and _Name 2_  
> This README keeps the documentation of Laboratory Activities 1 and 2 and adds Laboratory Activity 3 below.

---

## Laboratory Activity 1 - Domain, Application, Infrastructure

_Keep / paste your original Lab 1 documentation here (domain model, services, repository interfaces, in-memory storage)._

## Laboratory Activity 2 - Avalonia Desktop Interface

_Keep / paste your original Lab 2 documentation here (MVVM, data binding, commands, dependency injection)._

---

# Laboratory Activity 3 - From In-Memory Data to Persistent Storage

## How to build and run

Requirements: a .NET SDK (see `Directory.Build.props` for the target version).

```bash
# macOS / Linux                      # Windows PowerShell
./setup.sh                           ./setup.ps1
```

The script installs `dotnet-ef`, creates the `InitialCreate` migration (only the first time), applies it,
builds and runs the tests. Then start the app:

```bash
dotnet run --project src/EquipmentBorrowing.Desktop
```

Database file: `%LOCALAPPDATA%\EquipmentBorrowing\equipment-borrowing.db` (Windows) or
`~/.local/share/EquipmentBorrowing/equipment-borrowing.db` (Linux). macOS uses `~/.local/share` or `~/Library/Application Support`
depending on the .NET version - the app and `dotnet ef` always use the same path (`DatabasePaths.cs`).

## 1. Relational Database Design

![Database diagram](docs/database-diagram.png)

(The Mermaid source is in `docs/database-diagram.md`.)

| Table | Columns |
|---|---|
| **Students** | `Id` PK, `StudentNumber` TEXT(20) NOT NULL **UNIQUE**, `FullName` TEXT(100) NOT NULL, `IsAllowedToBorrow` NOT NULL |
| **Equipment** | `Id` PK, `Name` TEXT(100) NOT NULL **UNIQUE**, `Type` TEXT(50) NOT NULL (indexed), `IsAvailable` NOT NULL |
| **Borrowings** | `Id` PK, `StudentId` FK -> Students NOT NULL, `EquipmentId` FK -> Equipment NOT NULL, `BorrowedAt` NOT NULL, `ExpectedReturnAt` NOT NULL, `ReturnedAt` NULL, `Status` TEXT(20) NOT NULL |

Relationships: one student has many borrowings; one piece of equipment appears in many borrowings over time;
each borrowing belongs to exactly one student and one piece of equipment (both foreign keys are required,
`ON DELETE RESTRICT`).

Important constraints:

- Unique `StudentNumber` and unique equipment `Name`.
- `UX_Borrowings_ActiveByEquipment` - unique index on `EquipmentId` filtered to `ReturnedAt IS NULL`:
  the database itself refuses a second active borrowing of the same item.
- `CK_Borrowings_DueAfterBorrowed` - `ExpectedReturnAt > BorrowedAt`.
- `Status` is an enum stored as text (`Active` / `Returned`).
- No duplicated data: a borrowing stores `StudentId` and `EquipmentId`, not the student's or equipment's details.

SQL demonstration queries: `docs/database-queries.sql`.

## 2. SQLite and EF Core

Added to the **Infrastructure** project only (Domain and Application have no EF references):

```bash
dotnet add src/EquipmentBorrowing.Infrastructure package Microsoft.EntityFrameworkCore.Sqlite
dotnet add src/EquipmentBorrowing.Infrastructure package Microsoft.EntityFrameworkCore.Design
dotnet tool install --global dotnet-ef
```

## 3. DbContext

`EquipmentBorrowingDbContext` represents our session with the database. It exposes `Students`, `Equipment` and
`Borrowings` as `DbSet`s, applies the entity configurations (`ApplyConfigurationsFromAssembly`), tracks changes
to loaded entities, translates LINQ into SQL and writes changes with `SaveChangesAsync`. It is used only inside
Infrastructure (repositories / unit of work) - never from Views or ViewModels.

Entity mapping lives in `Persistence/Configurations/*Configuration.cs` (Fluent API,
`IEntityTypeConfiguration<T>`), so the domain classes contain no persistence attributes.

## 4. Repository Transition

Before (Lab 2):

```
Repository Interface -> In-Memory Repository
```

Now (Lab 3):

```
Repository Interface -> EF Core Repository -> DbContext -> SQLite
```

The interfaces (`IStudentRepository`, `IEquipmentRepository`, `IBorrowingRepository`) and the application
services did not change. Only the registrations changed (`AddPersistence()` in Infrastructure, called from the
composition root `App.axaml.cs`). `IUnitOfWork` (`EfUnitOfWork`) commits the new borrowing and the equipment
state change in one transaction.

Lifetime decision: the desktop app has no per-request scope and runs one command at a time, so the DbContext,
repositories and services are registered as singletons. ViewModel operations are serialized with a
`SemaphoreSlim` because a DbContext is not thread-safe.

## 5. Migration Process

```bash
# create the migration
dotnet ef migrations add InitialCreate --project src/EquipmentBorrowing.Infrastructure --output-dir Migrations

# apply it to the SQLite database
dotnet ef database update --project src/EquipmentBorrowing.Infrastructure
```

`DesignTimeDbContextFactory` lets these commands build the DbContext without starting Avalonia. At startup the
app calls `DatabaseInitializer.Initialize`, which runs `Database.Migrate()`: it creates the database the first
time and applies only new migrations afterwards - it never deletes or recreates existing data. Seed data
(`HasData`) is part of the migration.

Evidence: _(add screenshots: migration created, database updated, DB viewer showing Students, Equipment,
Borrowings and \_\_EFMigrationsHistory)_

## 6. Generated SQL

Capture the real output yourself:

```bash
dotnet test --filter GeneratedSql --logger "console;verbosity=detailed"
# or run the app with SQL logging:  EQUIPMENT_SQL_LOG=1  (PowerShell: $env:EQUIPMENT_SQL_LOG = "1")
```

> The SQL below shows the expected shape. **Replace it with the exact text from your own run.**

### Query A - available equipment

```csharp
_db.Equipment.AsNoTracking().Where(e => e.IsAvailable).OrderBy(e => e.Name).ToListAsync(ct);
```

```sql
SELECT "e"."Id", "e"."IsAvailable", "e"."Name", "e"."Type"
FROM "Equipment" AS "e"
WHERE "e"."IsAvailable"
ORDER BY "e"."Name"
```

Explanation: the `Where` becomes a SQL `WHERE`, `OrderBy` becomes `ORDER BY`, and only the mapped columns are
selected. SQLite stores booleans as 0/1, so `"IsAvailable"` is true when it is 1.

### Query B - active borrowings with student and equipment

```csharp
_db.Borrowings.AsNoTracking()
   .Include(b => b.Student).Include(b => b.Equipment)
   .Where(b => b.ReturnedAt == null)
   .OrderBy(b => b.ExpectedReturnAt)
   .ToListAsync(ct);
```

```sql
SELECT "b"."Id", "b"."BorrowedAt", "b"."EquipmentId", "b"."ExpectedReturnAt", "b"."ReturnedAt", "b"."Status", "b"."StudentId",
       "s"."Id", "s"."FullName", "s"."IsAllowedToBorrow", "s"."StudentNumber",
       "e"."Id", "e"."IsAvailable", "e"."Name", "e"."Type"
FROM "Borrowings" AS "b"
INNER JOIN "Students" AS "s" ON "b"."StudentId" = "s"."Id"
INNER JOIN "Equipment" AS "e" ON "b"."EquipmentId" = "e"."Id"
WHERE "b"."ReturnedAt" IS NULL
ORDER BY "b"."ExpectedReturnAt"
```

Explanation: each `Include` becomes a JOIN along the foreign key (INNER, because the keys are required).
`ReturnedAt == null` becomes `IS NULL`. LINQ did not remove SQL: EF Core translated the query into joins,
filters and ordering.

### Query C - number of active borrowings for a student

```csharp
_db.Borrowings.CountAsync(b => b.StudentId == studentId && b.ReturnedAt == null, ct);
```

```sql
SELECT COUNT(*)
FROM "Borrowings" AS "b"
WHERE "b"."StudentId" = @studentId AND "b"."ReturnedAt" IS NULL
```

This answers a real requirement: a student may have at most 3 active borrowings.

### Tracking vs. no-tracking

| Operation | Tracking | Why |
|---|---|---|
| Equipment list, available equipment, students, active borrowings (display) | `AsNoTracking()` | Data is only shown. No change tracking snapshot is needed, which saves memory and time. |
| `IEquipmentRepository.GetByIdAsync` when borrowing / returning | tracked | `IsAvailable` is changed and `SaveChangesAsync` must detect it and issue the UPDATE. |
| `IBorrowingRepository.GetActiveByIdAsync` when returning | tracked | `ReturnedAt` and `Status` are changed. |

## 7. Persistence Demonstration

1. Start the app, select Ana Reyes and Laptop 01, press **Borrow** - the borrowing appears under Active borrowings.
2. Close the application completely.
3. Start it again - the borrowing is still listed and Laptop 01 is unavailable.
4. Select the borrowing and press **Return selected equipment**.
5. Close and restart - the borrowing is gone from the active list and Laptop 01 is available again.

Failing scenarios to show: borrowing Camera 01 (not available), borrowing for Carla Santos (not allowed), a
fourth active borrowing for one student (limit of 3).

The same flow is automated in `tests/EquipmentBorrowing.Tests` (`Data_survives_a_restart_borrow_then_return`),
which opens a fresh DbContext for each "run" against the same SQLite file.

Screenshots: _(tables in DB viewer, stored data, successful borrow, borrowing after restart, successful return,
generated SQL, successful `dotnet build`)_

## 8. Architectural Reflection

_Rewrite these in your own words - both partners should be able to explain them._

1. **Why was no complete rewrite needed?** Views, ViewModels and application services depend only on repository
   interfaces. Only the Infrastructure implementations and the DI registration changed.
2. **Why shouldn't the ViewModel use DbContext directly?** It would tie UI code to EF Core and SQLite, mix
   persistence with presentation logic, make testing hard, and break the layering.
3. **What does the repository implementation do now?** It translates application requests into EF Core
   queries and changes, hiding LINQ, tracking and SQLite details behind the interface.
4. **Purpose of a migration?** A versioned, repeatable history of schema changes that can recreate or upgrade
   the database on any machine.
5. **Why are foreign keys important?** They guarantee that every borrowing points to a real student and real
   equipment, prevent orphan rows, and define the relationships used for joins.
6. **Why can read-only queries benefit from `AsNoTracking()`?** EF Core skips creating change-tracking
   snapshots, which is faster and uses less memory when nothing will be modified.
7. **If SQLite were replaced by another provider?** Only the Infrastructure project would change (provider
   package, `UseXxx` call, regenerated migrations). Domain, Application, ViewModels and Views stay the same.

## Project structure

```
EquipmentBorrowing/
├── EquipmentBorrowing.slnx
├── Directory.Build.props          (target framework / package versions)
├── setup.sh / setup.ps1
├── README.md
├── docs/
│   ├── database-diagram.md  (+ export database-diagram.png)
│   └── database-queries.sql
├── src/
│   ├── EquipmentBorrowing.Domain/          Student, Equipment, Borrowing, BorrowingStatus
│   ├── EquipmentBorrowing.Application/     repository interfaces, IUnitOfWork, services
│   ├── EquipmentBorrowing.Infrastructure/  DbContext, Configurations, Repositories, Migrations
│   └── EquipmentBorrowing.Desktop/         Avalonia Views, ViewModels, composition root
└── tests/EquipmentBorrowing.Tests/
```

## Git history

Commit in small steps (examples): _Design relational database schema_, _Add SQLite and EF Core packages_,
_Create application DbContext_, _Configure entity relationships_, _Create initial database migration_,
_Add initial database seed data_, _Implement EF equipment/student/borrowing repository_,
_Replace in-memory dependency registrations_, _Add LINQ database queries_, _Inspect generated SQL_,
_Verify persistent borrowing workflow_, _Update database documentation_.
