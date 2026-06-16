#Requires -Version 7.6

function Get-JsonSchemaValueType {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [int64]) { return 'integer' }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return 'number' }
    if ($Value -is [string] -or $Value -is [DateTime] -or $Value -is [DateTimeOffset]) { return 'string' }
    if ($Value -is [array]) { return 'array' }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [pscustomobject]) { return 'array' }
    return 'object'
}

function Test-JsonSchemaValueEquals {
    param($Left, $Right)
    $leftJson = $Left | ConvertTo-Json -Compress -Depth 20
    $rightJson = $Right | ConvertTo-Json -Compress -Depth 20
    return $leftJson -eq $rightJson
}

function Test-JsonSchemaNode {
    param(
        $Value,
        $Schema,
        [string]$Path,
        [System.Collections.Generic.List[string]]$Failures
    )

    $typeProp = $Schema.PSObject.Properties['type']
    if ($typeProp) {
        $actual = Get-JsonSchemaValueType -Value $Value
        $expected = [string]$typeProp.Value
        $typeOk = switch ($expected) {
            'number'  { $actual -in @('number', 'integer') }
            'integer' { $actual -eq 'integer' }
            default   { $actual -eq $expected }
        }
        if (-not $typeOk) {
            $Failures.Add("$Path expected $expected but got $actual.") | Out-Null
            return
        }
    }

    if ($Schema.PSObject.Properties['const']) {
        if (-not (Test-JsonSchemaValueEquals -Left $Value -Right $Schema.const)) {
            $expectedJson = $Schema.const | ConvertTo-Json -Compress -Depth 20
            $Failures.Add("$Path must be $expectedJson.") | Out-Null
        }
    }
    if ($Schema.PSObject.Properties['enum']) {
        $allowed = @($Schema.enum)
        if ($allowed -notcontains $Value) {
            $Failures.Add("$Path must be one of: $($allowed -join ', ').") | Out-Null
        }
    }
    if ($Schema.PSObject.Properties['minimum'] -and $Value -lt $Schema.minimum) {
        $Failures.Add("$Path must be >= $($Schema.minimum).") | Out-Null
    }

    if ($Schema.PSObject.Properties['allOf']) {
        foreach ($subSchema in @($Schema.allOf)) {
            Test-JsonSchemaNode -Value $Value -Schema $subSchema -Path $Path -Failures $Failures
        }
    }
    if ($Schema.PSObject.Properties['if']) {
        $conditionFailures = [System.Collections.Generic.List[string]]::new()
        Test-JsonSchemaNode -Value $Value -Schema $Schema.if -Path $Path -Failures $conditionFailures
        if ($conditionFailures.Count -eq 0 -and $Schema.PSObject.Properties['then']) {
            Test-JsonSchemaNode -Value $Value -Schema $Schema.then -Path $Path -Failures $Failures
        }
    }

    if ((Get-JsonSchemaValueType -Value $Value) -eq 'object') {
        $valueProps = @($Value.PSObject.Properties.Name)
        if ($Schema.PSObject.Properties['required']) {
            foreach ($required in @($Schema.required)) {
                if ($valueProps -notcontains $required) {
                    $Failures.Add("$Path.$required is required.") | Out-Null
                }
            }
        }
        if ($Schema.PSObject.Properties['properties']) {
            $schemaProps = @($Schema.properties.PSObject.Properties.Name)
            if ($Schema.PSObject.Properties['additionalProperties'] -and $Schema.additionalProperties -eq $false) {
                foreach ($prop in $valueProps) {
                    if ($schemaProps -notcontains $prop) {
                        $Failures.Add("$Path.$prop is not allowed by schema.") | Out-Null
                    }
                }
            }
            foreach ($prop in $Schema.properties.PSObject.Properties) {
                if ($valueProps -contains $prop.Name) {
                    Test-JsonSchemaNode -Value $Value.($prop.Name) -Schema $prop.Value -Path "$Path.$($prop.Name)" -Failures $Failures
                }
            }
        }
        if ($Schema.PSObject.Properties['additionalProperties'] -and
            $Schema.additionalProperties -is [pscustomobject]) {
            $schemaProps = if ($Schema.PSObject.Properties['properties']) {
                @($Schema.properties.PSObject.Properties.Name)
            } else {
                @()
            }
            foreach ($prop in $valueProps) {
                if ($schemaProps -notcontains $prop) {
                    Test-JsonSchemaNode -Value $Value.($prop) -Schema $Schema.additionalProperties -Path "$Path.$prop" -Failures $Failures
                }
            }
        }
    }

    if ((Get-JsonSchemaValueType -Value $Value) -eq 'array') {
        $items = @($Value)
        if ($Schema.PSObject.Properties['uniqueItems'] -and $Schema.uniqueItems -eq $true) {
            $seen = @{}
            foreach ($item in $items) {
                $key = $item | ConvertTo-Json -Compress -Depth 20
                if ($seen.ContainsKey($key)) {
                    $Failures.Add("$Path must contain unique items.") | Out-Null
                    break
                }
                $seen[$key] = $true
            }
        }
        if ($Schema.PSObject.Properties['items']) {
            for ($i = 0; $i -lt $items.Count; $i++) {
                Test-JsonSchemaNode -Value $items[$i] -Schema $Schema.items -Path "$Path[$i]" -Failures $Failures
            }
        }
        if ($Schema.PSObject.Properties['contains']) {
            $containsMatch = $false
            for ($i = 0; $i -lt $items.Count; $i++) {
                $containsFailures = [System.Collections.Generic.List[string]]::new()
                Test-JsonSchemaNode -Value $items[$i] -Schema $Schema.contains -Path "$Path[$i]" -Failures $containsFailures
                if ($containsFailures.Count -eq 0) {
                    $containsMatch = $true
                    break
                }
            }
            if (-not $containsMatch) {
                $Failures.Add("$Path must contain an item matching the required schema.") | Out-Null
            }
        }
    }
}

function Test-JsonObjectAgainstSchema {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json
        $failures = [System.Collections.Generic.List[string]]::new()
        Test-JsonSchemaNode -Value $Value -Schema $schema -Path '$' -Failures $failures
        if ($failures.Count -gt 0) {
            foreach ($f in $failures) { Add-ValidationError "$Label schema: $f" }
            return
        }
        Write-Host "OK JSON schema $Label"
    }
    catch {
        Add-ValidationError "$Label schema validation failed: $($_.Exception.Message)"
    }
}

function Test-JsonObjectRejectedBySchema {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json
        $failures = [System.Collections.Generic.List[string]]::new()
        Test-JsonSchemaNode -Value $Value -Schema $schema -Path '$' -Failures $failures
        if ($failures.Count -eq 0) {
            Add-ValidationError "$Label should have failed schema validation."
            return
        }
        Write-Host "OK JSON schema rejection $Label"
    }
    catch {
        Add-ValidationError "$Label schema rejection test failed: $($_.Exception.Message)"
    }
}

