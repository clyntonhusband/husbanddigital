# VicRoads Prequalified Contractors Web Scraper v3
# Enhanced to capture all prequalification categories including Road & Bridge

param(
    [switch]$ForceRefresh,
    [string[]]$Letters = @()
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

if ($ForceRefresh) {
    Write-Host "MODE: FORCE REFRESH - Will re-download all files" -ForegroundColor Magenta
} else {
    Write-Host "MODE: SMART CACHE - Will skip existing HTML files" -ForegroundColor Cyan
}

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
            $bodyHtml = Get-Content $htmlFile -Raw
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
                $bodyHtml | Out-File -FilePath $htmlFile
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
            # Enhanced parsing for all table patterns
            # Pattern 1: Standard table rows
            $tablePattern = '<tr[^>]*>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?</tr>'
            $tableMatches = [regex]::Matches($bodyHtml, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
            
            Write-DebugLog "Found $($tableMatches.Count) table rows"
            
            # Track current section for context
            $currentSection = ""
            $categoriesBuffer = ""
            
            foreach ($match in $tableMatches) {
                $label = $match.Groups[1].Value -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '[\r\n\t]', ''
                $value = $match.Groups[2].Value -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '[\r\n\t]', ''
                
                $label = $label.Trim()
                $value = $value.Trim()
                
                if ($label -and $value) {
                    switch -Regex ($label) {
                        'Firm' { 
                            $company | Add-Member -NotePropertyName 'Firm_' -NotePropertyValue $value -Force 
                        }
                        'ABN' { 
                            $company | Add-Member -NotePropertyName 'ABN' -NotePropertyValue $value -Force 
                        }
                        'ACN' { 
                            $company | Add-Member -NotePropertyName 'ACN' -NotePropertyValue $value -Force 
                        }
                        'Business Address|^Address' { 
                            $company | Add-Member -NotePropertyName 'Address' -NotePropertyValue $value -Force 
                        }
                        'Tel.*No|Phone' { 
                            $company | Add-Member -NotePropertyName 'Phone' -NotePropertyValue $value -Force 
                        }
                        'Mobile.*No' { 
                            $company | Add-Member -NotePropertyName 'Mobile_No_' -NotePropertyValue $value -Force 
                        }
                        'Fax' { 
                            $company | Add-Member -NotePropertyName 'Fax' -NotePropertyValue $value -Force 
                        }
                        'Email' { 
                            $company | Add-Member -NotePropertyName 'Email' -NotePropertyValue $value -Force 
                        }
                        'Website|Web' { 
                            $company | Add-Member -NotePropertyName 'Website' -NotePropertyValue $value -Force 
                        }
                        'Person|Contact' { 
                            $company | Add-Member -NotePropertyName 'Contact' -NotePropertyValue $value -Force 
                        }
                        'Position' { 
                            $company | Add-Member -NotePropertyName 'Position' -NotePropertyValue $value -Force 
                        }
                        
                        # Prequalification categories - enhanced patterns
                        'Maintenance and General Works.*Group' { 
                            $currentSection = "Maintenance"
                            $company | Add-Member -NotePropertyName 'Maintenance_and_General_Works__Group' -NotePropertyValue "Categories: $value" -Force 
                        }
                        'Road and Bridge Construction.*Group' { 
                            $currentSection = "RoadBridge"
                            $company | Add-Member -NotePropertyName 'Road_and_Bridge_Construction_Group' -NotePropertyValue "Categories: $value" -Force 
                        }
                        'Traffic Management.*Group' { 
                            $currentSection = "Traffic"
                            $company | Add-Member -NotePropertyName 'Traffic_Management_Services__contract__Groups' -NotePropertyValue "Categories: $value" -Force 
                        }
                        'Traffic Control Systems' { 
                            $currentSection = "TrafficControl"
                            $company | Add-Member -NotePropertyName 'Traffic_Control_Systems_Supply___Maintenance__a' -NotePropertyValue "Categories: $value" -Force 
                        }
                        
                        # Category patterns within sections
                        'Maintenance' {
                            if ($currentSection -eq "Maintenance") {
                                $existing = $company.Maintenance_and_General_Works__Group
                                if ($existing) {
                                    $company.Maintenance_and_General_Works__Group = "$existing, $value"
                                } else {
                                    $company | Add-Member -NotePropertyName 'Maintenance' -NotePropertyValue $value -Force
                                }
                            }
                        }
                        'Road Construction' {
                            if ($currentSection -eq "RoadBridge") {
                                $existing = $company.Road_and_Bridge_Construction_Group
                                if ($existing) {
                                    $company.Road_and_Bridge_Construction_Group = "$existing, Road Construction: $value"
                                } else {
                                    $company | Add-Member -NotePropertyName 'Road_Construction' -NotePropertyValue $value -Force
                                }
                            }
                        }
                        'Bridge Construction' {
                            if ($currentSection -eq "RoadBridge") {
                                $existing = $company.Road_and_Bridge_Construction_Group
                                if ($existing) {
                                    $company.Road_and_Bridge_Construction_Group = "$existing, Bridge Construction: $value"
                                } else {
                                    $company | Add-Member -NotePropertyName 'Bridge_Construction' -NotePropertyValue $value -Force
                                }
                            }
                        }
                        'Financial' {
                            if ($currentSection -eq "RoadBridge") {
                                $existing = $company.Road_and_Bridge_Construction_Group
                                if ($existing) {
                                    $company.Road_and_Bridge_Construction_Group = "$existing, Financial: $value"
                                } else {
                                    $company | Add-Member -NotePropertyName 'Financial_Level' -NotePropertyValue $value -Force
                                }
                            }
                        }
                        
                        'Prequalif.*Categor|^Categor' { 
                            $company | Add-Member -NotePropertyName 'PrequalificationCategories' -NotePropertyValue $value -Force 
                        }
                        'Expir' { 
                            $company | Add-Member -NotePropertyName 'ExpiryDate' -NotePropertyValue $value -Force 
                        }
                        default { 
                            $fieldName = $label -replace '[^\w]', '_'
                            if ($fieldName) {
                                $company | Add-Member -NotePropertyName $fieldName -NotePropertyValue $value -Force
                            }
                        }
                    }
                }
            }
            
            # Pattern 2: Look for category codes directly in the HTML
            $categoryPatterns = @(
                'M\d+(?:-[A-Z]+)?',      # M1, M2-BW, M2-PW
                'R\d+',                  # R1, R2, R3
                'B\d+',                  # B1, B2, B3
                'F\d+\+?',              # F150, F150+
                'S[A-Z]+\d*',           # SCTV, STCE1, STS2
                'SCTV|SSLC|STCE|STS|SVDL|SOED'  # Traffic codes
            )
            
            $allCategories = @()
            foreach ($pattern in $categoryPatterns) {
                $catMatches = [regex]::Matches($bodyHtml, "\b($pattern)\b", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $catMatches) {
                    $allCategories += $match.Groups[1].Value
                }
            }
            
            if ($allCategories.Count -gt 0) {
                $uniqueCategories = $allCategories | Select-Object -Unique | Sort-Object
                $catString = "Categories: " + ($uniqueCategories -join ', ')
                
                # Add to PrequalificationCategories if not already present
                if (-not $company.PrequalificationCategories) {
                    $company | Add-Member -NotePropertyName 'PrequalificationCategories' -NotePropertyValue $catString -Force
                } else {
                    # Merge with existing
                    $existing = $company.PrequalificationCategories
                    if ($existing -notmatch [regex]::Escape($catString)) {
                        $company.PrequalificationCategories = "$existing; $catString"
                    }
                }
            }
            
            # Pattern 3: Alternative colon pattern
            $colonPattern = '<b>([^<:]+):</b>([^<]+)'
            $colonMatches = [regex]::Matches($bodyHtml, $colonPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            foreach ($match in $colonMatches) {
                $label = $match.Groups[1].Value.Trim()
                $value = $match.Groups[2].Value.Trim()
                
                if ($label -and $value -and $label -notmatch 'script|style') {
                    $fieldName = $label -replace '[^\w]', '_'
                    if (-not $company.PSObject.Properties[$fieldName]) {
                        $company | Add-Member -NotePropertyName $fieldName -NotePropertyValue $value -Force
                    }
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