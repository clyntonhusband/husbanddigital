# VicRoads ABN Lookup Script - CORRECTED VERSION
# Fixed to properly detect Active/Inactive status from ABR API

param(
    [string]$InputFile  = "VicRoads_Data\All_Companies.csv",
    [string]$OutputFile = "VicRoads_Data\All_Companies_ABN_Enriched.csv",
    [string]$GUID       = "43429c4b-39e6-4a50-9840-fa2b8653750b"
)

Write-Host "Loading companies from $InputFile..." -ForegroundColor Cyan
$companies = Import-Csv $InputFile

# Ensure enrichment columns exist
$ensureCols = @('ABN_Found','ABNStatus','YearsInOperation','RegisteredDate','EntityType','RegisteredName','State')
foreach ($c in $companies) {
    foreach ($col in $ensureCols) {
        if (-not $c.PSObject.Properties[$col]) {
            $c | Add-Member -NotePropertyName $col -NotePropertyValue ''
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SOAP callers
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-ABRByName {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Guid)

    $escaped = [System.Security.SecurityElement]::Escape($Name.Trim())

    $soap = @"
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <ABRSearchByNameAdvancedSimpleProtocol2017 xmlns="http://abr.business.gov.au/ABRXMLSearch/">
      <name>$escaped</name>
      <postcode></postcode>
      <legalName>Y</legalName>
      <tradingName>Y</tradingName>
      <NSW>Y</NSW><VIC>Y</VIC><QLD>Y</QLD><WA>Y</WA><SA>Y</SA><TAS>Y</TAS><NT>Y</NT><ACT>Y</ACT>
      <authenticationGuid>$Guid</authenticationGuid>
      <searchWidth>typical</searchWidth>
      <minimumScore>0</minimumScore>
      <maxSearchResults>10</maxSearchResults>
    </ABRSearchByNameAdvancedSimpleProtocol2017>
  </soap:Body>
</soap:Envelope>
"@

    $headers = @{
        "Content-Type" = "text/xml; charset=utf-8"
        "SOAPAction"   = '"http://abr.business.gov.au/ABRXMLSearch/ABRSearchByNameAdvancedSimpleProtocol2017"'
    }

    $resp = Invoke-RestMethod -Uri "https://abr.business.gov.au/abrxmlsearch/abrxmlsearch.asmx" `
                              -Method POST -Headers $headers -Body $soap
    return [xml]$resp
}

function Invoke-ABRByABN {
    param([Parameter(Mandatory)][string]$Abn,[Parameter(Mandatory)][string]$Guid)

    $abnClean = ($Abn -replace '\s','')

    $soap = @"
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <ABRSearchByABN xmlns="http://abr.business.gov.au/ABRXMLSearch/">
      <searchString>$abnClean</searchString>
      <includeHistoricalDetails>N</includeHistoricalDetails>
      <authenticationGuid>$Guid</authenticationGuid>
    </ABRSearchByABN>
  </soap:Body>
</soap:Envelope>
"@

    $headers = @{
        "Content-Type" = "text/xml; charset=utf-8"
        "SOAPAction"   = '"http://abr.business.gov.au/ABRXMLSearch/ABRSearchByABN"'
    }

    $resp = Invoke-RestMethod -Uri "https://abr.business.gov.au/abrxmlsearch/abrxmlsearch.asmx" `
                              -Method POST -Headers $headers -Body $soap
    return [xml]$resp
}

# ─────────────────────────────────────────────────────────────────────────────
# Namespace-agnostic XML helpers
# ─────────────────────────────────────────────────────────────────────────────

function Get-FirstInnerText {
    param([System.Xml.XmlNode]$Node, [string[]]$XPaths)
    if (-not $Node) { return "" }
    foreach ($xp in $XPaths) {
        $n = $Node.SelectSingleNode($xp)
        if ($n -and $n.InnerText) { return $n.InnerText }
    }
    return ""
}

function Get-AllNodes {
    param([System.Xml.XmlNode]$Node, [string]$XPath)
    if (-not $Node) { return @() }
    $nodes = $Node.SelectNodes($XPath)
    if ($nodes) { return $nodes } else { return @() }
}

# ─────────────────────────────────────────────────────────────────────────────
# Response parser - FIXED VERSION
# ─────────────────────────────────────────────────────────────────────────────

function Select-BestEntityFromResponse {
    param([xml]$Xml,[string]$TargetName)

    # Two possible shapes:
    # 1) //.../searchResultsList/searchResultsRecord (from name searches)
    # 2) //.../businessEntity (from ABN searches)
    $records  = Get-AllNodes -Node $Xml -XPath "//*[local-name()='searchResultsList']/*[local-name()='searchResultsRecord']"
    $entities = Get-AllNodes -Node $Xml -XPath "//*[local-name()='businessEntity']"

    $candidates = @()

    # Shape 1: searchResultsRecord (from name searches)
    foreach ($r in $records) {
        $abn = Get-FirstInnerText -Node $r -XPaths @(
            ".//*[local-name()='ABN']/*[local-name()='identifierValue']",
            ".//*[local-name()='identifierValue']"
        )
        
        # CRITICAL FIX: In name searches, status is at ABN/identifierStatus, NOT entityStatus/entityStatusCode
        $abnStatus = Get-FirstInnerText -Node $r -XPaths @(".//*[local-name()='ABN']/*[local-name()='identifierStatus']")
        
        $name = Get-FirstInnerText -Node $r -XPaths @(
            ".//*[local-name()='mainName']/*[local-name()='organisationName']",
            ".//*[local-name()='legalName']/*[local-name()='fullName']",
            ".//*[local-name()='businessName']/*[local-name()='organisationName']",
            ".//*[local-name()='otherTradingName']/*[local-name()='organisationName']"
        )
        
        $etype = Get-FirstInnerText -Node $r -XPaths @(
            ".//*[local-name()='entityType']/*[local-name()='entityDescription']",
            ".//*[local-name()='entityTypeCode']"
        )
        
        $state = Get-FirstInnerText -Node $r -XPaths @(".//*[local-name()='mainBusinessPhysicalAddress']/*[local-name()='stateCode']")
        $score = Get-FirstInnerText -Node $r -XPaths @(".//*[local-name()='score']")

        if ($abn -or $name) {
            # Status is "Active" or "Cancelled" in name search results
            $isActive = ($abnStatus -eq 'Active')
            
            $candidates += [pscustomobject]@{
                ABN            = $abn
                Status         = if ($isActive) {'Active'} else {'Inactive'}
                RegisteredName = $name
                EntityType     = $etype
                State          = $state
                Score          = ([int]$score)
            }
        }
    }

    # Shape 2: businessEntity (from direct ABN searches)
    foreach ($e in $entities) {
        $abn = Get-FirstInnerText -Node $e -XPaths @(".//*[local-name()='ABN']/*[local-name()='identifierValue']")
        $isCur = Get-FirstInnerText -Node $e -XPaths @(".//*[local-name()='ABN']/*[local-name()='isCurrentIndicator']")
        
        $name = Get-FirstInnerText -Node $e -XPaths @(
            ".//*[local-name()='mainName']/*[local-name()='organisationName']",
            ".//*[local-name()='legalName']/*[local-name()='fullName']",
            ".//*[local-name()='businessName']/*[local-name()='organisationName']",
            ".//*[local-name()='mainTradingName']/*[local-name()='organisationName']"
        )
        
        $etype = Get-FirstInnerText -Node $e -XPaths @(
            ".//*[local-name()='entityType']/*[local-name()='entityDescription']",
            ".//*[local-name()='entityTypeCode']"
        )
        
        $state = Get-FirstInnerText -Node $e -XPaths @(".//*[local-name()='mainBusinessPhysicalAddress']/*[local-name()='stateCode']")
        
        # In businessEntity responses, status is at entityStatus/entityStatusCode
        $entityStatus = Get-FirstInnerText -Node $e -XPaths @(".//*[local-name()='entityStatus']/*[local-name()='entityStatusCode']")

        if ($abn -or $name) {
            # Check both entityStatus and isCurrentIndicator
            $isActive = ($entityStatus -eq 'Active') -or ($isCur -eq 'Y')
            
            $candidates += [pscustomobject]@{
                ABN            = $abn
                Status         = if ($isActive) {'Active'} else {'Inactive'}
                RegisteredName = $name
                EntityType     = $etype
                State          = $state
                Score          = 100  # Direct ABN search has perfect score
            }
        }
    }

    if (-not $candidates -or $candidates.Count -eq 0) { return $null }

    # Prefer exact (case-insensitive) match, then highest score
    $exact = $candidates | Where-Object { 
        $_.RegisteredName -and ($_.RegisteredName -eq $TargetName -or $_.RegisteredName -like "*$TargetName*")
    }
    if ($exact) { 
        return $exact | Sort-Object Score -Descending | Select-Object -First 1 
    }

    return $candidates | Sort-Object Score -Descending | Select-Object -First 1
}

function Get-ABNDetails {
    param([string]$ABN,[string]$Guid)

    try {
        $xml = Invoke-ABRByABN -Abn $ABN -Guid $Guid
        $eff = Get-FirstInnerText -Node $xml -XPaths @("//*[local-name()='businessEntity']/*[local-name()='entityStatus']/*[local-name()='effectiveFrom']")
        if ($eff) {
            $d = [datetime]::Parse($eff)
            $yrs = [math]::Floor(((Get-Date) - $d).Days / 365.25)
            return @{ RegisteredDate = $eff; YearsInOperation = $yrs }
        }
    } catch {
        # ignore
    }
    return @{ RegisteredDate = ''; YearsInOperation = 0 }
}

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────

$total = $companies.Count
$foundCount = 0; $notFoundCount = 0; $activeCount = 0; $inactiveCount = 0; $current = 0

Write-Host "`n=== Starting ABN Lookup (Total: $total) ===" -ForegroundColor Green

foreach ($row in $companies) {
    $current++
    Write-Progress -Activity "Looking up ABNs" -Status "$current of $total" -PercentComplete (($current/$total)*100)

    # Clean company name
    $companyName = if ($row.Firm_) { $row.Firm_ } elseif ($row.Name) { $row.Name } else { $null }
    if ($companyName) { 
        # Clean HTML entities and special characters
        $companyName = $companyName -replace '&nbsp;?', ' '
        $companyName = $companyName -replace '&amp;', '&'
        $companyName = $companyName -replace '\*+$', ''
        $companyName = $companyName.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($companyName) -or $companyName.Length -lt 3) {
        Write-Host "[$current/$total] Skipping - no usable name" -ForegroundColor DarkGray
        continue
    }

    Write-Host "`n[$current/$total] $companyName" -ForegroundColor Cyan

    # Already has ABN in CSV?
    if ($row.ABN -and $row.ABN.ToString().Trim().Length -ge 9) {
        Write-Host "  ABN already present: $($row.ABN)" -ForegroundColor Gray
        $d = Get-ABNDetails -ABN $row.ABN -Guid $GUID
        $row.RegisteredDate = $d.RegisteredDate
        $row.YearsInOperation = $d.YearsInOperation
        if (-not $row.ABNStatus) { $row.ABNStatus = 'Active' }
        $activeCount++
        continue
    }

    try {
        $xml = Invoke-ABRByName -Name $companyName -Guid $GUID
        $best = Select-BestEntityFromResponse -Xml $xml -TargetName $companyName

        if ($best -and $best.ABN) {
            $row.ABN_Found = $best.ABN
            $row.ABNStatus = $best.Status
            $row.RegisteredName = $best.RegisteredName
            $row.EntityType = $best.EntityType
            $row.State = $best.State

            $d = Get-ABNDetails -ABN $best.ABN -Guid $GUID
            $row.RegisteredDate = $d.RegisteredDate
            $row.YearsInOperation = $d.YearsInOperation

            $foundCount++
            if ($best.Status -eq 'Active') { 
                $activeCount++ 
                $statusColor = 'Green'
            } else { 
                $inactiveCount++ 
                $statusColor = 'Yellow'
            }
            
            Write-Host "  Found ABN: $($best.ABN)  Status: $($row.ABNStatus)  Years: $($row.YearsInOperation)" -ForegroundColor $statusColor
        } else {
            $row.ABNStatus = 'Not Found'
            $notFoundCount++
            Write-Host "  Not Found" -ForegroundColor Yellow
        }
    } catch {
        $row.ABNStatus = 'Error'
        $notFoundCount++
        Write-Host "  Error: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300
}

Write-Host "`n=== Saving results ===" -ForegroundColor Green
$companies | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Companies: $total" -ForegroundColor White
Write-Host "Found: $foundCount" -ForegroundColor Green
Write-Host "  - Active: $activeCount" -ForegroundColor Green
Write-Host "  - Inactive: $inactiveCount" -ForegroundColor Yellow
Write-Host "Not Found: $notFoundCount" -ForegroundColor Yellow
Write-Host "Output saved to: $OutputFile" -ForegroundColor White