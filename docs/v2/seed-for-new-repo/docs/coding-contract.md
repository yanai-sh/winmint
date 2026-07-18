# Coding contract (net11 / AOT)

## Project defaults

```xml
<PropertyGroup>
  <TargetFramework>net11.0</TargetFramework>
  <LangVersion>preview</LangVersion>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
  <!-- Executable / publish projects only -->
  <PublishAot>true</PublishAot>
  <!-- All projects in the AOT graph -->
  <IsAotCompatible>true</IsAotCompatible>
</PropertyGroup>
```

Pin the .NET SDK in `global.json` (e.g. `11.0.100-preview.6.x`). Avalonia wizard (later): **12.1.x**.

## Native AOT

- No reflection-driven pipeline code (`Type.GetType`, `Activator.CreateInstance`, etc.).
- JSON via `System.Text.Json` **source generation** (`JsonSerializerContext`).
- Win32 via `LibraryImport`, not `DllImport`.
- `PublishAot` on the main exe only; `IsAotCompatible` on libraries.

## C# patterns (use when they earn their keep)

**Unions (C# 15)** — compose existing types; exhaustive switches (no discard `_` for completeness):

```csharp
public record class RegistryOperation(/* ... */);
public record class AppxRemovalOperation(string PackagePrefix);
public union TweakOperation(RegistryOperation, AppxRemovalOperation);

var outcome = operation switch
{
    RegistryOperation r => ApplyReg(r),
    AppxRemovalOperation a => QueueAppx(a),
};
```

**`field` keyword** — C# **14** (not a C# 15 feature); fine on net11.

**`System.Threading.Lock`** — .NET **9+**; prefer over `object` locks.

**Collection expression `with(capacity:)`** — C# 15; use when capacity matters, not for one-element lists.

## Process constraints

- Unelevated Orchestrator/CLI; elevate only Servicing `pwsh`.
- No in-process WIM/hive work in the wizard or unelevated CLI.
- Leave one small runnable check for non-trivial logic (see project TDD / ponytail norms).
