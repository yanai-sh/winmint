# Driver Payloads

Place optional offline driver payloads here when building an ISO for hardware that is not the build host.

Recommended layout:

```text
assets/drivers/
  arm64/
    SurfaceLaptop7.msi
  amd64/
    VendorDriverFolder/
      driver.inf
```

The build prefers `assets/drivers/<detected-arch>/` when it exists and contains `.inf` or `.msi` files. Otherwise it falls back to flat payloads directly under `assets/drivers/`.

MSI driver bundles are local build inputs and are ignored by git. For Surface Laptop 7 builds from a non-Surface host, download the Microsoft driver MSI and place it under `assets/drivers/arm64/` before running the build.
