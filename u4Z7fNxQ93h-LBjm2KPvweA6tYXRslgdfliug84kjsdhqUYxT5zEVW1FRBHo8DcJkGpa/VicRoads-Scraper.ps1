# VicRoads Prequalified Contractors Web Scraper v3
# Enhanced to capture all prequalification categories including Road & Bridge
#
# USAGE:
#   .\VicRoads-Scraper.ps1                           # Use cached HTML files (fast)
#   .\VicRoads-Scraper.ps1 -ForceRefresh             # Download fresh from website
#   .\VicRoads-Scraper.ps1 -Letters @('A','B')       # Only process specific letters
#   .\VicRoads-Scraper.ps1 -ForceRefresh -Letters @('A')  # Fresh download, letter A only

param(
    [switch]$ForceRefresh,      # If set, re-download all HTML files; otherwise use cached
    [string[]]$Letters = @()    # Specific letters to process (default: all A-Z)
)

# Set default letters if none specified
if ($Letters.Count -eq 0) {
    $Letters = @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
}

$allCompanies = @()
$baseUrl = "https://webapps.vicroads.vic.gov.au"
$outputDir = "VicRoads_Data"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VicRoads Data Extraction v3 - Enhanced" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Output directory: $outputDir" -ForegroundColor Yellow
Write-Host "Letters to process: $($Letters -join ', ')" -ForegroundColor Yellow

Write-Host ""
if ($ForceRefresh) {
    Write-Host "MODE: FORCE REFRESH" -ForegroundColor Magenta
    Write-Host "  -> Will re-download ALL HTML files from VicRoads website" -ForegroundColor Magenta
} else {
    Write-Host "MODE: USE CACHED FILES" -ForegroundColor Green
    Write-Host "  -> Will use existing HTML files in VicRoads_Data folder" -ForegroundColor Green
    Write-Host "  -> Only downloads if file doesn't exist" -ForegroundColor Green
    Write-Host "  -> To force fresh download, run: .\VicRoads-Scraper.ps1 -ForceRefresh" -ForegroundColor DarkGray
}
Write-Host ""

$debugLog = Join-Path $outputDir "debug.log"
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting extraction" | Out-File -FilePath $debugLog -Append

function Write-DebugLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $debugLog -Append
}

function Get-CompanyDetails {
    param (
        [string]$CompanyUrl,
        [string]$CompanyName
    )

    try {
        $safeFileName = $CompanyName -replace '[^\w]', '_'
        $htmlFile = Join-Path $outputDir "raw_html_$safeFileName.html"

        $bodyHtml = $null
        $dataSource = "Fresh"

        if ((Test-Path $htmlFile) -and -not $ForceRefresh) {
            Write-Host "  ✓ Using cached: $CompanyName" -ForegroundColor DarkYellow
            Write-DebugLog "Using cached HTML: $htmlFile"
            # Try reading with different encodings to handle UTF-16
            try {
                $bodyHtml = Get-Content $htmlFile -Raw -Encoding Unicode
                # Check if we got the spaced-out UTF-16 format and fix it
                if ($bodyHtml -match '< \! D O C T Y P E') {
                    # Remove null bytes/spaces between characters
                    $bodyHtml = $bodyHtml -replace '\x00', ''
                }
            }
            catch {
                $bodyHtml = Get-Content $htmlFile -Raw
            }
            $dataSource = "Cached"
            $extractDate = (Get-Item $htmlFile).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        else {
            Write-Host "  ↓ Downloading: $CompanyName" -ForegroundColor Cyan
            Write-DebugLog "Fetching URL: $CompanyUrl"

            try {
                $response = Invoke-WebRequest -Uri $CompanyUrl -UseBasicParsing
                $bodyHtml = $response.Content
            }
            catch {
                Write-DebugLog "Invoke-WebRequest failed, trying IE"
                $ie = New-Object -ComObject InternetExplorer.Application
                $ie.Visible = $false
                $ie.Navigate($CompanyUrl)

                while ($ie.Busy -or $ie.ReadyState -ne 4) {
                    Start-Sleep -Milliseconds 100
                }

                $doc = $ie.Document
                $bodyHtml = $doc.body.innerHTML
                $ie.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ie) | Out-Null
            }

            if ($bodyHtml) {
                # Save as UTF-8 for consistency
                $bodyHtml | Out-File -FilePath $htmlFile -Encoding UTF8
                Write-DebugLog "Saved HTML to: $htmlFile (Length: $($bodyHtml.Length))"
            }

            $extractDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $company = [PSCustomObject]@{
            Name = $CompanyName
            Url = $CompanyUrl
            DataSource = $dataSource
            ExtractedDate = $extractDate
        }

        if ($bodyHtml) {
            # Clean HTML for consistent parsing
            $cleanHtml = $bodyHtml -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&quot;', '"' -replace '&#160;', ' '

            Write-DebugLog "Parsing HTML (Length: $($cleanHtml.Length))"

            # ═══════════════════════════════════════════════════════════════════
            # SECTION 1: Parse Company Info Table (border="0")
            # ═══════════════════════════════════════════════════════════════════

            # Extract Firm Name - look for bgcolor="#D2D2D2" header row
            if ($cleanHtml -match 'Firm[:\s]*</font></b></td><td[^>]*bgcolor="#D2D2D2"[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'Firm_' -NotePropertyValue $matches[1].Trim() -Force
            }

            # Trading Name
            if ($cleanHtml -match 'Trading\s*Name[:\s]*</font></b></td><td[^>]*>.*?<font[^>]*color="#000080"[^>]*>([^<]*)</font>') {
                $tradingName = $matches[1].Trim()
                if ($tradingName) {
                    $company | Add-Member -NotePropertyName 'TradingName' -NotePropertyValue $tradingName -Force
                }
            }

            # Phone/Tel No
            if ($cleanHtml -match 'Tel\s*No[:\s]*</font></td><td[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'Phone' -NotePropertyValue $matches[1].Trim() -Force
            }

            # Fax No
            if ($cleanHtml -match 'Fax\s*No[:\s]*</font></td><td[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'Fax' -NotePropertyValue $matches[1].Trim() -Force
            }

            # Business Address - multiline
            if ($cleanHtml -match 'Business\s*Ad.*?dress[:\s]*</font></b></td><td[^>]*>.*?<font[^>]*>([\s\S]*?)</font>\s*&?n?b?s?p?') {
                $address = $matches[1] -replace '<br\s*/?>', ', ' -replace '<[^>]+>', '' -replace '\s+', ' '
                $company | Add-Member -NotePropertyName 'Address' -NotePropertyValue $address.Trim() -Force
            }

            # Contact Person
            if ($cleanHtml -match 'Person[:\s]*</font></td><td[^>]*>([\s\S]*?)</td>') {
                $person = $matches[1] -replace '<[^>]+>', ' ' -replace '\s+', ' '
                $company | Add-Member -NotePropertyName 'Contact' -NotePropertyValue $person.Trim() -Force
            }

            # Position
            if ($cleanHtml -match 'Position[:\s]*</font></td><td[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'Position' -NotePropertyValue $matches[1].Trim() -Force
            }

            # Mobile No
            if ($cleanHtml -match 'Mobile\s*No[:\s]*</font></td><td[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'Mobile_No_' -NotePropertyValue $matches[1].Trim() -Force
            }

            # Postal Address
            if ($cleanHtml -match 'Postal\s*Address[:\s]*</font></b></td><td[^>]*[^>]*>([\s\S]*?)</td>') {
                $postal = $matches[1] -replace '<br\s*/?>', ', ' -replace '<[^>]+>', '' -replace '\s+', ' '
                $company | Add-Member -NotePropertyName 'PostalAddress' -NotePropertyValue $postal.Trim() -Force
            }

            # Email Address - handle Cloudflare email protection
            if ($cleanHtml -match 'Email\s*Address[:\s]*</font></b></td><td[^>]*>([\s\S]*?)</td>') {
                $emailBlock = $matches[1]
                if ($emailBlock -match 'data-cfemail="([^"]+)"') {
                    # Cloudflare protected - decode it
                    $encoded = $matches[1]
                    $key = [Convert]::ToByte($encoded.Substring(0,2), 16)
                    $decoded = ""
                    for ($i = 2; $i -lt $encoded.Length; $i += 2) {
                        $byte = [Convert]::ToByte($encoded.Substring($i,2), 16)
                        $decoded += [char]($byte -bxor $key)
                    }
                    $company | Add-Member -NotePropertyName 'Email' -NotePropertyValue $decoded -Force
                }
                elseif ($emailBlock -match 'mailto:([^"]+)') {
                    $company | Add-Member -NotePropertyName 'Email' -NotePropertyValue $matches[1] -Force
                }
                elseif ($emailBlock -match '([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})') {
                    $company | Add-Member -NotePropertyName 'Email' -NotePropertyValue $matches[1] -Force
                }
            }

            # Website
            if ($cleanHtml -match 'Website[:\s]*</font></b></td><td[^>]*>([\s\S]*?)</td>') {
                $websiteBlock = $matches[1]
                if ($websiteBlock -match 'href="([^"]+)"') {
                    $company | Add-Member -NotePropertyName 'Website' -NotePropertyValue $matches[1] -Force
                }
                else {
                    $website = $websiteBlock -replace '<[^>]+>', ''
                    if ($website.Trim()) {
                        $company | Add-Member -NotePropertyName 'Website' -NotePropertyValue $website.Trim() -Force
                    }
                }
            }

            # ABN/ACN if present
            if ($cleanHtml -match 'ABN[:\s]*</font></b></td><td[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'ABN' -NotePropertyValue $matches[1].Trim() -Force
            }
            if ($cleanHtml -match 'ACN[:\s]*</font></b></td><td[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                $company | Add-Member -NotePropertyName 'ACN' -NotePropertyValue $matches[1].Trim() -Force
            }

            # Conditions relating to prequalification
            if ($cleanHtml -match 'Conditions\s*relating\s*to\s*prequalification[:\s]*</font></b></td><td[^>]*>.*?<font[^>]*>([^<]*)</font>') {
                $conditions = $matches[1].Trim()
                if ($conditions) {
                    $company | Add-Member -NotePropertyName 'Conditions' -NotePropertyValue $conditions -Force
                }
            }

            # ═══════════════════════════════════════════════════════════════════
            # SECTION 2: Parse Prequalification Tables (border="1")
            # Each table has: Header row (group name) → Categories/Levels row → Data rows
            # ═══════════════════════════════════════════════════════════════════

            # Find all tables with border="1"
            $prequalTablePattern = '<table\s+border="1">([\s\S]*?)</table>'
            $prequalTables = [regex]::Matches($cleanHtml, $prequalTablePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

            Write-DebugLog "Found $($prequalTables.Count) prequalification tables"

            $allPrequalCategories = @()

            foreach ($table in $prequalTables) {
                $tableHtml = $table.Groups[1].Value

                # Extract group name from first row (has colspan="2" and bgcolor="#D2D2D2")
                $groupName = ""
                if ($tableHtml -match '<tr[^>]*>.*?<td[^>]*bgcolor="#D2D2D2"[^>]*colspan="2"[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                    $groupName = $matches[1].Trim()
                }
                elseif ($tableHtml -match '<tr[^>]*>.*?<td[^>]*colspan="2"[^>]*bgcolor="#D2D2D2"[^>]*>.*?<font[^>]*>([^<]+)</font>') {
                    $groupName = $matches[1].Trim()
                }

                if (-not $groupName) {
                    Write-DebugLog "Could not find group name in table, skipping"
                    continue
                }

                Write-DebugLog "Processing prequalification group: $groupName"

                # Create clean field name from group name
                $fieldName = $groupName -replace '[^\w\s]', '' -replace '\s+', '_'

                # Find all data rows (skip header rows)
                # Data rows have 2 cells: Category name and Level(s)
                $rowPattern = '<tr[^>]*valign="top"[^>]*>\s*<td[^>]*width="263"[^>]*>\s*<font[^>]*>([^<]+)</font>\s*</td>\s*<td[^>]*width="340"[^>]*>\s*<font[^>]*>([\s\S]*?)</font>\s*</td>\s*</tr>'
                $dataRows = [regex]::Matches($tableHtml, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

                $categoryEntries = @()

                foreach ($row in $dataRows) {
                    $categoryName = $row.Groups[1].Value -replace '<[^>]+>', '' -replace '\s+', ' '
                    $categoryName = $categoryName.Trim()

                    $levels = $row.Groups[2].Value -replace '<br\s*/?>', ', ' -replace '<[^>]+>', '' -replace '\s+', ' '
                    $levels = $levels.Trim()

                    # Skip the header row (Categories: / Levels:)
                    if ($categoryName -match '^Categories' -or $categoryName -match '^Names') {
                        continue
                    }

                    if ($categoryName -and $levels) {
                        $categoryEntries += "$categoryName`: $levels"

                        # Also extract category codes for the flat categories list
                        $codePatterns = @(
                            'M\d+(?:-[A-Z]+)?',
                            'R\d+',
                            'B\d+',
                            'F\d+\+?',
                            'SCTV|SSLC|STCE\d*|STS\d*|SVDL|SOED',
                            '[A-Z]+-[A-Z]+',
                            '\b[A-Z]{2,4}\d*\b'
                        )
                        foreach ($codePattern in $codePatterns) {
                            $codeMatches = [regex]::Matches($levels, $codePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                            foreach ($code in $codeMatches) {
                                $allPrequalCategories += $code.Value.ToUpper()
                            }
                        }
                    }
                }

                # Store the prequalification group data
                if ($categoryEntries.Count -gt 0) {
                    $groupValue = $categoryEntries -join "; "
                    $company | Add-Member -NotePropertyName $fieldName -NotePropertyValue $groupValue -Force
                    Write-DebugLog "Added $fieldName with $($categoryEntries.Count) entries"
                }
            }

            # ═══════════════════════════════════════════════════════════════════
            # SECTION 3: Create unified PrequalificationCategories field
            # ═══════════════════════════════════════════════════════════════════

            if ($allPrequalCategories.Count -gt 0) {
                $uniqueCategories = $allPrequalCategories | Select-Object -Unique | Sort-Object
                $company | Add-Member -NotePropertyName 'PrequalificationCategories' -NotePropertyValue ($uniqueCategories -join ', ') -Force
            }

            # ═══════════════════════════════════════════════════════════════════
            # SECTION 4: Fallback - extract any category codes from full HTML
            # ═══════════════════════════════════════════════════════════════════

            if (-not $company.PrequalificationCategories) {
                $fallbackPatterns = @(
                    '\bM\d+(?:-[A-Z]+)?\b',
                    '\bR\d+\b',
                    '\bB\d+\b',
                    '\bF\d+\+?\b',
                    '\b(SCTV|SSLC|STCE\d*|STS\d*|SVDL|SOED)\b'
                )

                $fallbackCats = @()
                foreach ($pattern in $fallbackPatterns) {
                    $matches = [regex]::Matches($cleanHtml, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    foreach ($m in $matches) {
                        $fallbackCats += $m.Value.ToUpper()
                    }
                }

                if ($fallbackCats.Count -gt 0) {
                    $uniqueFallback = $fallbackCats | Select-Object -Unique | Sort-Object
                    $company | Add-Member -NotePropertyName 'PrequalificationCategories' -NotePropertyValue ($uniqueFallback -join ', ') -Force
                }
            }
        }

        Write-DebugLog "Company object has $($company.PSObject.Properties.Count) properties"
        return $company
    }
    catch {
        Write-Host "    ✗ Error: $_" -ForegroundColor Red
        Write-DebugLog "ERROR: $_"

        return [PSCustomObject]@{
            Name = $CompanyName
            Url = $CompanyUrl
            Error = $_.Exception.Message
            DataSource = "Error"
            ExtractedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

function Get-CompaniesFromLetter {
    param ([string]$Letter)
    
    $letterUrl = "https://webapps.vicroads.vic.gov.au/vrne/prequal.nsf/By+Name?openform&letter=$Letter"
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "Processing Letter: $Letter" -ForegroundColor Green
    Write-Host "URL: $letterUrl" -ForegroundColor Gray
    Write-DebugLog "Processing letter URL: $letterUrl"
    
    try {
        $letterHtmlFile = Join-Path $outputDir "letter_${Letter}_page.html"
        $html = $null
        
        if ((Test-Path $letterHtmlFile) -and -not $ForceRefresh) {
            Write-Host "Using cached letter page" -ForegroundColor DarkYellow
            $html = Get-Content $letterHtmlFile -Raw
        }
        else {
            try {
                $response = Invoke-WebRequest -Uri $letterUrl -UseBasicParsing
                $html = $response.Content
            }
            catch {
                $ie = New-Object -ComObject InternetExplorer.Application
                $ie.Visible = $false
                $ie.Navigate($letterUrl)
                
                while ($ie.Busy -or $ie.ReadyState -ne 4) {
                    Start-Sleep -Milliseconds 100
                }
                
                $doc = $ie.Document
                $html = $doc.body.innerHTML
                $ie.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ie) | Out-Null
            }
            
            if ($html) {
                $html | Out-File -FilePath $letterHtmlFile
            }
        }
        
        Write-DebugLog "Letter page HTML length: $($html.Length)"
        
        $patterns = @(
            '<a[^>]*href="(/vrne/prequal\.nsf/[^"]+\?OpenDocument)"[^>]*>([^<]+)</a>',
            '<a[^>]*href="([^"]*prequal\.nsf/[^"]+\?OpenDocument)"[^>]*>([^<]+)</a>',
            'href="(/vrne/prequal\.nsf/\w+/\w+\?OpenDocument)"[^>]*>([^<]+)'
        )
        
        $allMatches = @()
        foreach ($pattern in $patterns) {
            $matches = [regex]::Matches($html, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $allMatches += $matches
            Write-DebugLog "Pattern found $($matches.Count) matches"
        }
        
        $companies = @()
        $processedUrls = @{}
        
        foreach ($match in $allMatches) {
            $relativeUrl = $match.Groups[1].Value
            $companyName = $match.Groups[2].Value.Trim()
            
            if ($relativeUrl -notmatch '^http') {
                if ($relativeUrl -match '^/') {
                    $fullUrl = $baseUrl + $relativeUrl
                } else {
                    $fullUrl = $relativeUrl
                }
            } else {
                $fullUrl = $relativeUrl
            }
            
            if ($processedUrls.ContainsKey($fullUrl)) { continue }
            
            if ($companyName -notmatch '^(By Name|By Category|Search|Home|Next|Previous|\d+|[A-Z]|)$' -and 
                $companyName.Length -gt 1 -and
                $fullUrl -match 'OpenDocument') {
                
                $processedUrls[$fullUrl] = $true
                
                $companyDetails = Get-CompanyDetails -CompanyUrl $fullUrl -CompanyName $companyName
                $companyDetails | Add-Member -NotePropertyName 'Letter' -NotePropertyValue $Letter -Force
                
                $companies += $companyDetails
                
                if ($companyDetails.DataSource -eq "Fresh") {
                    Start-Sleep -Milliseconds 500
                }
            }
        }
        
        Write-Host "Found $($companies.Count) companies for letter $Letter" -ForegroundColor Yellow
        Write-DebugLog "Letter $Letter complete with $($companies.Count) companies"
        
        return $companies
    }
    catch {
        Write-Host "Error processing letter $Letter : $_" -ForegroundColor Red
        Write-DebugLog "ERROR processing letter $Letter : $_"
        return @()
    }
}

# MAIN EXECUTION
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Starting Extraction Process" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Processing letters: $($Letters -join ', ')" -ForegroundColor Yellow

$totalLetters = $Letters.Count
$letterIndex = 0
$startTime = Get-Date

foreach ($letter in $Letters) {
    $letterIndex++
    Write-Host "`n[$letterIndex/$totalLetters] Processing letter: $letter" -ForegroundColor Magenta
    
    $letterCompanies = Get-CompaniesFromLetter -Letter $letter
    $allCompanies += $letterCompanies
    
    if ($letterCompanies.Count -gt 0) {
        $letterFile = Join-Path $outputDir "Letter_$letter.csv"
        $letterCompanies | Export-Csv -Path $letterFile -NoTypeInformation
        Write-Host "Saved to: $letterFile" -ForegroundColor Gray
    }
    
    $elapsed = (Get-Date) - $startTime
    $avgTimePerLetter = $elapsed.TotalSeconds / $letterIndex
    $remainingLetters = $totalLetters - $letterIndex
    $estimatedRemaining = [TimeSpan]::FromSeconds($avgTimePerLetter * $remainingLetters)
    
    Write-Host "Progress: $($allCompanies.Count) companies | Elapsed: $($elapsed.ToString('mm\:ss')) | ETA: $($estimatedRemaining.ToString('mm\:ss'))" -ForegroundColor DarkCyan
}

# Save all results
$outputFile = Join-Path $outputDir "All_Companies.csv"
if ($allCompanies.Count -gt 0) {
    $allCompanies | Export-Csv -Path $outputFile -NoTypeInformation
    
    $jsonFile = Join-Path $outputDir "All_Companies.json"
    $allCompanies | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile
}

# Generate summary
$cachedCount = ($allCompanies | Where-Object { $_.DataSource -eq 'Cached' }).Count
$freshCount = ($allCompanies | Where-Object { $_.DataSource -eq 'Fresh' }).Count
$errorCount = ($allCompanies | Where-Object { $_.DataSource -eq 'Error' }).Count

# Show which categories were found
$categoriesFound = @()
$allCompanies | ForEach-Object {
    if ($_.PrequalificationCategories) { $categoriesFound += "PrequalificationCategories" }
    if ($_.Maintenance_and_General_Works__Group) { $categoriesFound += "Maintenance_and_General_Works__Group" }
    if ($_.Road_and_Bridge_Construction_Group) { $categoriesFound += "Road_and_Bridge_Construction_Group" }
    if ($_.Traffic_Management_Services__contract__Groups) { $categoriesFound += "Traffic_Management_Services__contract__Groups" }
}
$uniqueCategories = $categoriesFound | Select-Object -Unique

$summaryFile = Join-Path $outputDir "Summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$summary = @"
VicRoads Prequalified Contractors Data Extraction Summary
=========================================================
Extraction Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Total Time: $($elapsed.ToString('mm\:ss'))
Total Companies: $($allCompanies.Count)

Data Sources:
  Fresh Downloads: $freshCount
  Cached (Reused): $cachedCount
  Errors: $errorCount

Category Fields Found:
$(($uniqueCategories | ForEach-Object { "  - $_" }) -join "`n")

Companies by Letter:
"@

foreach ($letter in $Letters) {
    $count = ($allCompanies | Where-Object { $_.Letter -eq $letter }).Count
    if ($count -gt 0) {
        $summary += "`n  ${letter}: $count companies"
    }
}

$summary += @"

Files Generated:
  All Companies CSV: $outputFile
  All Companies JSON: $jsonFile
  Debug Log: $debugLog
"@

$summary | Out-File -FilePath $summaryFile
Write-Host "`n$summary" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✓ EXTRACTION COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

if ($allCompanies.Count -eq 0) {
    Write-Host "`n⚠ NO DATA EXTRACTED!" -ForegroundColor Red
} else {
    Write-Host "`nQuick Preview (First 3 companies):" -ForegroundColor Yellow
    $allCompanies | Select-Object -First 3 Name, ABN, Phone, Letter, DataSource | Format-Table -AutoSize
    
    Write-Host "`n💡 TIP: To run ABN verification after extraction:" -ForegroundColor Cyan
    Write-Host "   .\Verify-ABNs.ps1" -ForegroundColor Cyan
}