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

    # Normalize target name for comparison
    $targetNorm = $TargetName.Trim().ToUpper()

    # Score each candidate for matching quality
    foreach ($c in $candidates) {
        $nameNorm = if ($c.RegisteredName) { $c.RegisteredName.Trim().ToUpper() } else { "" }
        $matchScore = 0

        # PRIORITY 1: Exact name match (highest priority)
        if ($nameNorm -eq $targetNorm) {
            $matchScore = 1000
        }
        # PRIORITY 2: Name starts with target or target starts with name
        elseif ($nameNorm.StartsWith($targetNorm) -or $targetNorm.StartsWith($nameNorm)) {
            $matchScore = 500
        }
        # PRIORITY 3: Name contains full target name
        elseif ($nameNorm -like "*$targetNorm*") {
            $matchScore = 300
        }
        # PRIORITY 4: Target contains full registered name (dangerous - can match individuals)
        elseif ($targetNorm -like "*$nameNorm*" -and $nameNorm.Length -gt 5) {
            $matchScore = 100
        }

        # BONUS: Prefer Active businesses (+200)
        if ($c.Status -eq 'Active') {
            $matchScore += 200
        }

        # BONUS: Prefer companies over individuals (+150)
        # Individuals typically have entity types like "Individual/Sole Trader" or names in "SURNAME, FIRSTNAME" format
        $isIndividual = ($c.EntityType -match 'Individual|Sole Trader') -or
                        ($c.RegisteredName -match '^[A-Z]+,\s+[A-Z]+')
        if (-not $isIndividual) {
            $matchScore += 150
        }

        # BONUS: Prefer Pty Ltd companies when searching for Pty Ltd (+100)
        if ($targetNorm -match 'PTY\s*LTD' -and $nameNorm -match 'PTY\s*LTD') {
            $matchScore += 100
        }

        # BONUS: Prefer VIC-based businesses for VicRoads data (+50)
        if ($c.State -eq 'VIC') {
            $matchScore += 50
        }

        # Add the API score (typically 0-100)
        $matchScore += [int]$c.Score

        # Store the calculated match score
        $c | Add-Member -NotePropertyName 'MatchScore' -NotePropertyValue $matchScore -Force
    }

    # Sort by MatchScore descending and return the best match
    $sorted = $candidates | Sort-Object MatchScore -Descending

    # Only return if we have a reasonable match (MatchScore > 200 means at least active or some name match)
    $best = $sorted | Select-Object -First 1
    if ($best.MatchScore -ge 200) {
        return $best
    }

    # If no good match, return null rather than a bad match
    return $null
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