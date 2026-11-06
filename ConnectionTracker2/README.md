# ConnectionTrackerEverywhere

ConnectionTrackerEverywhere measures SQL Server connection times through repeated batches of connections.
It can also execute a SQL query and measure its execution time.
The tool supports SQL Server and Azure SQL endpoints through `Microsoft.Data.SqlClient`.

## Releases

Download [Pre-compiled version](https://github.com/EvanBasalik/Tools/releases/tag/ConnectionTrackerEverywhere-20260715-001548).

## Project layout

| Path | Purpose |
| --- | --- |
| `ConnectionTrackerEverywhere\` | Current C# console application |
| `ConnectionTracker.sln` | Solution for the current application |
| `Sample.txt` | Example command lines |
| `ConnectionTracker_deprecated\` | Legacy Visual Basic project, outside the current solution |
| `binaries\` | Placeholder folder, not a packaged release |

## Requirements

- .NET 10 SDK to build the application.
- .NET 10 runtime to run a framework-dependent build.
- Access to the target SQL Server endpoint and database.
- A database identity with permission to connect and execute any supplied query.
- Access to a NuGet package source for `Microsoft.Data.SqlClient` version `5.1.4`.

The project targets `net10.0`.
Authentication support depends on the operating system, identity setup, and SQL endpoint.
Windows integrated authentication requires a suitable Windows environment.
Managed identity requires an environment that supports the selected identity.

## Build and run

Run these commands from the `ConnectionTracker2` folder.

1. Build the Release configuration.

   ```powershell
   dotnet build .\ConnectionTrackerEverywhere\ConnectionTrackerEverywhere.csproj -c Release
   ```

2. Run the application with your server and authentication mode.

   ```powershell
   dotnet run --project .\ConnectionTrackerEverywhere\ConnectionTrackerEverywhere.csproj -c Release --no-launch-profile -- -Syourserver.database.windows.net -dyourdatabase -I -q
   ```

`--no-launch-profile` prevents the example arguments in `launchSettings.json` from replacing your arguments.
Without `-q`, the application waits for Enter before the first batch.
Use Ctrl+C to stop the application.

### Publish for Windows x64

The supplied publish profile creates a self-contained, single-file Windows x64 application.
The target machine does not need a separate .NET runtime.

```powershell
dotnet publish .\ConnectionTrackerEverywhere\ConnectionTrackerEverywhere.csproj -p:PublishProfile=FolderProfile
```

The profile sets the output folder to `ConnectionTrackerEverywhere\bin\Release\net10.0\publish\win-x64\`.
Other runtime targets require separate publish options and compatible authentication support.

## Command-line syntax

Switches are case-sensitive.
Attach each value directly to its switch, such as `-Slocalhost`, not `-S localhost`.
Enclose values that contain spaces in quotes, such as `-Q"SELECT @@version"`.
Supply at least two arguments, or the application prints help and exits.

### Connection and authentication

| Switch | Meaning | Default or requirement |
| --- | --- | --- |
| `-Sserver` | SQL Server instance or endpoint | `localhost` |
| `-ddatabase` | Database name | `master` |
| `-i` | Microsoft Entra integrated authentication | Default authentication mode |
| `-E` | Windows integrated authentication | Uses the current Windows identity |
| `-I` | Microsoft Entra interactive authentication | Supports interactive sign-in |
| `-Uusername` | SQL login name | Selects SQL authentication |
| `-Ppassword` | SQL login password | Selects SQL authentication |
| `-s` | Microsoft Entra service principal authentication | Requires `-a` and `-x` |
| `-aappId` | Application ID for a service principal | Also selects service principal authentication |
| `-xsecret` | Secret for a service principal | Also selects service principal authentication |
| `-j` | Microsoft Entra device code authentication | Uses a 180-second connection timeout |
| `-MclientId` | User-assigned managed identity | Supply the identity's client ID |
| `-D` | Microsoft Entra default authentication | Uses a 180-second connection timeout |
| `-tseconds` | Connection timeout | `15`, except with `-j` or `-D` |
| `-p` | Enable connection pooling | Pooling is off by default |

The last argument that selects an authentication mode takes effect.
Avoid arguments that select conflicting authentication modes.
The built-in help incorrectly lists the application ID switch as `-s`.
The parser uses `-a` for that value.

### Batches and queries

| Switch | Meaning | Default |
| --- | --- | --- |
| `-Tseconds` | Base delay between batches | `5` |
| `-Ffactor` | Multiplier for each subsequent delay | `1` |
| `-Hhours` | Requested run duration, in whole hours | `1` |
| `-bcount` | Sequential connection attempts per batch | `10` |
| `-Qquery` | Execute SQL after each successful connection | No query |
| `-R` | Fill an in-memory `DataSet` with query results | Off |
| `-q` | Skip the startup prompt and log header | Off |

Bare `-Q` executes `Select @@version`.
Without `-R`, the application uses `ExecuteNonQuery`.
With `-R`, it uses `SqlDataAdapter.Fill`.
Neither mode displays query results.
`-R` has no effect without `-Q`.
The connection timeout does not set the SQL command timeout.

The application starts the first batch immediately after the startup prompt, or immediately with `-q`.
The first delay equals `T * F`.
Each later delay multiplies the previous delay by `F`.
Batch execution time adds to these delays.

## Examples

These commands assume a published Windows executable in the current folder.
Replace the example server and database names before use.

### Windows integrated authentication

```powershell
.\ConnectionTrackerEverywhere.exe -Slocalhost -dmaster -E -T8 -b11
```

### Microsoft Entra interactive authentication with a query

```powershell
.\ConnectionTrackerEverywhere.exe -Syourserver.database.windows.net -dyourdatabase -I -Q"SELECT @@version" -T3 -b1 -H1 -q
```

### Microsoft Entra default authentication with result retrieval

```powershell
.\ConnectionTrackerEverywhere.exe -Syourserver.database.windows.net -dyourdatabase -D -Q"SELECT 1" -R -b1 -q
```

## Output

The application appends trace output to `ConnectionTrackerEverywhere.log` in the current working folder.
It does not read the log path from `app.config`, despite the startup message.
The log contains argument details and one timing record per connection attempt.

Without a query, the record fields are:

```text
Login Time,Server,Authentication Mode,Login (ms),Result
```

With a query, the record fields are:

```text
Login Time,Server,Authentication Mode,Login (ms),Query (ms),Result
```

`S_OK` means the connection and any requested query succeeded.
Otherwise, the result contains the exception message.
The console also shows progress, errors, and timing details.
`-q` does not suppress these console messages.

## Review findings and limits

These findings describe the current code.
This README does not change application behavior.

| Finding | Effect |
| --- | --- |
| Arguments reach the trace log without redaction | `-P` passwords, `-x` secrets, and query text appear in the log. Debug builds also print connection strings. |
| The parser lacks argument validation | Short arguments and invalid numbers can terminate the process. Unknown switches print an error but do not stop execution. |
| Delay values lack bounds checks | Negative, non-finite, or large delays can cause exceptions or an indefinite sleep. |
| The duration check occurs before sleep | A batch can start after the requested end time. The first batch runs even with `-H0`. |
| The first scheduling message uses an unset delay | The first displayed time does not describe the actual next batch time. |
| Failed connections leave query timestamps unset | A query record can show zero milliseconds even though the query never ran. |
| Log records lack CSV escaping | Commas, line breaks, and local date formats can prevent reliable CSV parsing. |

Treat the log as sensitive data.
Avoid password-based examples on shared machines.
Command-line credentials can also appear in shell history and process details.
Use a Release build to avoid debug output of connection strings.
Release builds still log argument values.

Use positive batch counts and nonnegative whole numbers for hours and timeouts.
Use positive, finite delay values that remain within the sleep limit throughout the run.
`-F` follows the current culture's number format.
Quotes do not change that format.
Pooling changes what the login measurement represents because connections can reuse physical connections.

SQL queries can change data.
Use read-only queries unless you intend to change the database.
Large results with `-R` can consume substantial memory.
