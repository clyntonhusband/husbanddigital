# Traffic Signals Contract Details Extractor - Selenium Version
# Adds: Company Search Mode (search contracts by supplier/company names)

param(
    [string]$InputCSV = "RoutineMaintenanceIndex.csv",
    [string]$OutputCSV = "RoutineMaintenanceIndexWithDetails.csv",
    [int]$DetailDelay = 1,  # Delay between detail page requests
    [bool]$HeadlessMode = $false,  # Run browser in background
    [string]$CompaniesCsv = ""     # NEW: comma-separated company list (optional)
)

# ─────────────────────────────────────────────────────────────────────────────
# Selenium module bootstrap (unchanged)
# ─────────────────────────────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Selenium)) {
    Write-Host "Selenium module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Selenium -Force -Scope CurrentUser
}
Import-Module Selenium

# ─────────────────────────────────────────────────────────────────────────────
# Utilities (existing + small helpers)
# ─────────────────────────────────────────────────────────────────────────────
function Find-ChromePath {
    $possiblePaths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LOCALAPPDATA}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles}\Google\Chrome Beta\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome Beta\Application\chrome.exe"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) { Write-Host "Found Chrome at: $path" -ForegroundColor Green; return $path }
    }
    return $null
}

# Simple normaliser to compare names safely
function Normalize-Text([string]$s) { ($s -as [string]).ToLowerInvariant() -replace '\s+', ' ' -replace '[^\p{L}\p{Nd}\s\.\-&/()]','' }

# ─────────────────────────────────────────────────────────────────────────────
# NEW: Search by Company helpers (keeps detail parser unchanged)
# ─────────────────────────────────────────────────────────────────────────────
# Known/likely search endpoints on VIC portals (we’ll try in order until results appear)
$Global:VicSearchEndpoints = @(
    "https://www.tenders.vic.gov.au/contract/search?query=",
    "https://www.tenders.vic.gov.au/contract/search?search=",
    "https://buyingfor.vic.gov.au/contract-search?query=",
    "https://buyingfor.vic.gov.au/contracts?search=",
    "https://www.tenders.vic.gov.au/contract/search"  # form-based (fallback)
)

function Invoke-SearchPage {
    param(
        [OpenQA.Selenium.IWebDriver]$Driver,
        [string]$BaseUrl,
        [string]$Company
    )
    # If BaseUrl ends with =, we can do querystring; otherwise, try simple form fill
    if ($BaseUrl -match '=$') {
        $url = $BaseUrl + [System.Web.HttpUtility]::UrlEncode($Company)
        $Driver.Navigate().GoToUrl($url)
        Start-Sleep -Milliseconds 800
        return $true
    } else {
        $Driver.Navigate().GoToUrl($BaseUrl)
        Start-Sleep -Milliseconds 800
        try {
            # Try a few common search boxes
            $boxes = @(
                { $Driver.FindElement([OpenQA.Selenium.By]::CssSelector("input[type='search']")) },
                { $Driver.FindElement([OpenQA.Selenium.By]::CssSelector("input[name='query']")) },
                { $Driver.FindElement([OpenQA.Selenium.By]::CssSelector("input[name='search']")) },
                { $Driver.FindElement([OpenQA.Selenium.By]::CssSelector("input[type='text']")) }
            )
            $box = $null
            foreach ($try in $boxes) { try { $box = & $try; if ($box) { break } } catch {} }
            if ($box) {
                $box.Clear(); $box.SendKeys($Company)
                # Press Enter
                $box.SendKeys([OpenQA.Selenium.Keys]::Enter)
                Start-Sleep -Milliseconds 1000
                return $true
            }
        } catch {}
    }
    return $false
}

function Parse-SearchResults {
    param(
        [string]$Html,
        [string]$Company
    )
    $contracts = @()

    # Pull detail links that look like contract pages
    $linkPatterns = @(
        '<a[^>]+href="([^"]*/contract/[^"]+)"[^>]*>(.*?)</a>',
        '<a[^>]+href="([^"]*/contracts/[^"]+)"[^>]*>(.*?)</a>'
    )

    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($pat in $linkPatterns) {
        $m = [regex]::Matches($Html, $pat, 'IgnoreCase')
        foreach ($x in $m) {
            $href = $x.Groups[1].Value
            $text = ($x.Groups[2].Value -replace '<[^>]+>','').Trim()
            if ([string]::IsNullOrWhiteSpace($href)) { continue }
            # Ensure absolute
            if ($href -notmatch '^https?://') {
                # Try to infer host from page (quick heuristic)
                if ($Html -match '(https?://(?:www\.)?(?:tenders\.vic\.gov\.au|buyingfor\.vic\.gov\.au))') {
                    $host = $matches[1]
                    if ($href.StartsWith('/')) { $href = "$host$href" } else { $href = "$host/$href" }
                }
            }
            if (-not $seen.Add($href)) { continue }

            # Try scrape Contract Number near the link context (best-effort)
            $ctx = $text
            if ($Html -match [Regex]::Escape($x.Value) + '.{0,400}') {
                $ctx += " " + ($matches[0] -replace '<[^>]+>','' -replace '\s+',' ').Trim()
            }
            $contractNumber = ""
            if ($ctx -match '(?i)\bContract\s*Number\b[:\s]*([A-Za-z0-9\-_/\.]+)') { $contractNumber = $matches[1].Trim() }

            $contracts += [PSCustomObject]@{
                ContractId     = ""
                ContractNumber = $contractNumber
                Title          = $text
                Status         = ""
                StartDate      = ""
                ExpiryDate     = ""
                TotalValue     = ""
                DetailUrl      = $href
                SearchedCompany= $Company
            }
        }
    }
    $contracts
}

function Get-Contracts-ForCompany {
    param(
        [OpenQA.Selenium.IWebDriver]$Driver,
        [string]$Company
    )
    Write-Host "🔎 Searching for company: $Company" -ForegroundColor Cyan
    $found = @()

    foreach ($base in $Global:VicSearchEndpoints) {
        try {
            $ok = Invoke-SearchPage -Driver $Driver -BaseUrl $base -Company $Company
            if (-not $ok) { continue }
            Start-Sleep -Milliseconds 800
            $html = $Driver.PageSource

            $batch = Parse-SearchResults -Html $html -Company $Company
            if ($batch.Count -gt 0) {
                $found += $batch
                # Some portals paginate; quick attempt to click "Next" a few times
                for ($p=0; $p -lt 4; $p++) {
                    try {
                        $next = $null
                        foreach ($sel in @("a[rel='next']","a.next","button[aria-label='Next']","a:contains('Next')")) {
                            try { $next = $Driver.FindElement([OpenQA.Selenium.By]::CssSelector($sel)); break } catch {}
                        }
                        if (-not $next) { break }
                        $next.Click()
                        Start-Sleep -Milliseconds 900
                        $html = $Driver.PageSource
                        $more = Parse-SearchResults -Html $html -Company $Company
                        if ($more.Count -eq 0) { break }
                        $found += $more
                    } catch { break }
                }
                break  # stop after first endpoint that returns results
            }
        } catch {
            Write-Host "  (warn) search endpoint failed: $base" -ForegroundColor DarkYellow
        }
    }

    # De-dupe by DetailUrl
    $found = $found | Sort-Object DetailUrl -Unique
    Write-Host ("  → Found {0} candidate contract(s) for {1}" -f $found.Count, $Company) -ForegroundColor Green
    return $found
}

# ─────────────────────────────────────────────────────────────────────────────
# Detail extractor (your existing function) — UNCHANGED
# ─────────────────────────────────────────────────────────────────────────────
function Get-ContractDetails-Selenium {
    param(
        [PSCustomObject]$Contract,
        $Driver
    )
    try {
        Write-Host "  Fetching: $($Contract.DetailUrl)" -ForegroundColor Gray
        $Driver.Navigate().GoToUrl($Contract.DetailUrl)
        Start-Sleep -Seconds $DetailDelay
        $pageSource = $Driver.PageSource

        if ($pageSource -match '<span class="LIST_TITLE">Public Body</span>[\s\S]*?<div class="col-sm-8"[^>]*?>(.*?)</div>') {
            $publicBody = $matches[1].Trim() -replace '<[^>]+>', ''
            $Contract | Add-Member -NotePropertyName "PublicBody" -NotePropertyValue $publicBody.Trim() -Force
        } else { $Contract | Add-Member -NotePropertyName "PublicBody" -NotePropertyValue "" -Force }

        if ($pageSource -match '<span class="LIST_TITLE">Type</span>[\s\S]*?<div class="col-sm-8"[^>]*?>(.*?)</div>') {
            $contractType = $matches[1].Trim() -replace '<[^>]+>', ''
            $Contract | Add-Member -NotePropertyName "ContractType" -NotePropertyValue $contractType.Trim() -Force
        } else { $Contract | Add-Member -NotePropertyName "ContractType" -NotePropertyValue "" -Force }

        if ($pageSource -match '<span class="LIST_TITLE">Description</span>[\s\S]*?<div class="col-sm-8"[^>]*?>[\s\S]*?<p>(.*?)</p>') {
            $description = $matches[1] -replace '<[^>]+>', '' -replace '\s+', ' '
            $Contract | Add-Member -NotePropertyName "Description" -NotePropertyValue $description.Trim() -Force
        } elseif ($pageSource -match '<span class="LIST_TITLE">Description</span>[\s\S]*?<div class="col-sm-8"[^>]*?>([\s\S]*?)</div>') {
            $description = $matches[1] -replace '<p>', '' -replace '</p>', '' -replace '<[^>]+>', '' -replace '\s+', ' '
            $Contract | Add-Member -NotePropertyName "Description" -NotePropertyValue $description.Trim() -Force
        } else { $Contract | Add-Member -NotePropertyName "Description" -NotePropertyValue "" -Force }

        if ($pageSource -match '<span class="LIST_TITLE">UNSPSC</span>[\s\S]*?<div class="col-sm-8"[^>]*?>([\s\S]*?)</div>') {
            $unspscRaw = $matches[1]
            $unspsc = $unspscRaw -replace '<[^>]+>', '' -replace '\s+', ' ' -replace '^\s+|\s+$', ''
            $Contract | Add-Member -NotePropertyName "UNSPSC" -NotePropertyValue $unspsc -Force
        } else { $Contract | Add-Member -NotePropertyName "UNSPSC" -NotePropertyValue "" -Force }

        if ($pageSource -match '<span class="LIST_TITLE">Starting Date</span>[\s\S]*?<div class="col-sm-8"[^>]*?>(.*?)</div>') {
            $Contract.StartDate = $matches[1].Trim()
        }
        if ($pageSource -match '<span class="LIST_TITLE">Expiry Date</span>[\s\S]*?<div class="col-sm-8"[^>]*?>(.*?)</div>') {
            $Contract.ExpiryDate = $matches[1].Trim()
        }

        if ($pageSource -match 'Total Value of the Contract</span>[\s\S]*?<div class="col-sm-8"[^>]*?>\s*([\$\d,\.]+)\s*(?:&nbsp;)?\s*\(([^)]+)\)') {
            $Contract.TotalValue = $matches[1].Trim()
            $Contract | Add-Member -NotePropertyName "ValueType" -NotePropertyValue $matches[2].Trim() -Force
        } else { $Contract | Add-Member -NotePropertyName "ValueType" -NotePropertyValue "" -Force }

        if ($pageSource -match '<span class="LIST_TITLE">Initial Expiry Date</span>[\s\S]*?<div class="col-sm-8"[^>]*?>(.*?)</div>') {
            $Contract | Add-Member -NotePropertyName "InitialExpiryDate" -NotePropertyValue $matches[1].Trim() -Force
        } else { $Contract | Add-Member -NotePropertyName "InitialExpiryDate" -NotePropertyValue "" -Force }

        if ($pageSource -match '<span class="LIST_TITLE">\s*Contact Person[\s\S]*?</span>[\s\S]*?<div class="col-sm-8"[^>]*?>\s*([\s\S]*?)\s*<table>') {
            $contactSection = $matches[1]
            $contactName = $contactSection -replace '<[^>]+>', '' -replace '\s+', ' '
            $contactName = $contactName.Trim()
            if ($pageSource -match '<a href="mailto:([^"]+)">') { $contactEmail = $matches[1] } else { $contactEmail = "" }
            $contactPhone = ""; if ($pageSource -match 'Office:\s*([+\d\s\(\)]+)</td>') { $contactPhone = $matches[1].Trim() }
            $contactInfo = $contactName
            if ($contactEmail) { $contactInfo += " ($contactEmail)" }
            if ($contactPhone) { $contactInfo += " - Phone: $contactPhone" }
            $Contract | Add-Member -NotePropertyName "ContactPerson" -NotePropertyValue $contactInfo -Force
        } else { $Contract | Add-Member -NotePropertyName "ContactPerson" -NotePropertyValue "" -Force }

        # Suppliers
        $suppliers = @()
        $supplierPattern = '<tr class="contractor">[\s\S]*?<td class="contractor-details">\s*([\s\S]*?)\s*</td>'
        $supplierMatches = [regex]::Matches($pageSource, $supplierPattern)
        foreach ($match in $supplierMatches) {
            if ($match.Success) {
                $supplierHtml = $match.Groups[1].Value
                $supplierName = ""; if ($supplierHtml -match '<b>(.*?)</b>') { $supplierName = $matches[1].Trim() -replace '&amp;', '&' }
                $abn=""; if ($supplierHtml -match '<strong>ABN</strong></td><td>([\d\s]+)') { $abn = $matches[1].Trim() -replace '\s','' }
                $acn=""; if ($supplierHtml -match '<strong>ACN</strong></td><td>([\d\s]+)') { $acn = $matches[1].Trim() -replace '\s','' }
                $supplierInfo = $supplierName
                if ($abn) { $supplierInfo += " (ABN: $abn)" }
                if ($acn -and ($acn -ne $abn)) { $supplierInfo += " (ACN: $acn)" }
                if ($supplierName) { $suppliers += $supplierInfo }
            }
        }
        $Contract | Add-Member -NotePropertyName "Suppliers" -NotePropertyValue ($suppliers -join "; ") -Force

        Write-Host "    ✓ Successfully extracted details" -ForegroundColor Green
    } catch {
        Write-Warning "    ✗ Failed to extract details: $($_.Exception.Message)"
        $Contract | Add-Member -NotePropertyName "PublicBody" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "ContractType" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "Description" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "UNSPSC" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "InitialExpiryDate" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "ContactPerson" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "Suppliers" -NotePropertyValue "" -Force
        $Contract | Add-Member -NotePropertyName "ValueType" -NotePropertyValue "" -Force
    }
    return $Contract
}

# ─────────────────────────────────────────────────────────────────────────────
# Main execution (adds Company mode, preserves CSV mode)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "=== Contract Details Extractor ===" -ForegroundColor Cyan
Write-Host "Using Selenium WebDriver to avoid web blocks" -ForegroundColor Yellow
Write-Host ""

# If not supplied, prompt for companies
if ([string]::IsNullOrWhiteSpace($CompaniesCsv)) {
    $CompaniesCsv = Read-Host "Paste company names separated by commas (or press Enter to use $InputCSV)"
}
$CompanyList = @()
if ($CompaniesCsv) {
    $CompanyList = $CompaniesCsv.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

# Find Chrome
$chromePath = Find-ChromePath
if (-not $chromePath) {
    Write-Host "Chrome browser not found!" -ForegroundColor Red
    Write-Host "Please install Google Chrome from: https://www.google.com/chrome/" -ForegroundColor Yellow
    exit 1
}

# Setup Chrome options (same as before)
$chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
$chromeOptions.BinaryLocation = $chromePath
$chromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
$chromeOptions.AddArgument("--disable-extensions")
$chromeOptions.AddArgument("--disable-plugins")
$chromeOptions.AddArgument("--no-sandbox")
$chromeOptions.AddArgument("--disable-dev-shm-usage")
$chromeOptions.AddArgument("--disable-gpu")
$chromeOptions.AddArgument("--disable-web-security")
$chromeOptions.AddArgument("--aggressive-cache-discard")
$chromeOptions.AddArgument("--memory-pressure-off")
$chromeOptions.AddArgument("--max_old_space_size=4096")
$chromeOptions.AddArgument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
if ($HeadlessMode) { $chromeOptions.AddArgument("--headless"); $chromeOptions.AddArgument("--window-size=1920,1080"); Write-Host "Running in headless mode" -ForegroundColor Cyan }

try {
    $driverPath = ".\chromedriver.exe"
    if (-not (Test-Path $driverPath)) {
        Write-Host "ChromeDriver not found. Place chromedriver.exe in the current directory." -ForegroundColor Yellow
        Write-Host "Download: https://chromedriver.chromium.org/" -ForegroundColor Yellow
        exit 1
    }

    $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService((Get-Location).Path, "chromedriver.exe")
    $service.HideCommandPromptWindow = $true

    Write-Host "Starting Chrome browser..." -ForegroundColor Yellow
    $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($service, $chromeOptions)
    $driver.Manage().Timeouts().PageLoad = [TimeSpan]::FromSeconds(15)
    $driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds(2)
    Write-Host "Browser started successfully." -ForegroundColor Green
    Write-Host ""

    $results = @()
    $startTime = Get-Date
    $successCount = 0
    $failCount = 0

    if ($CompanyList.Count -gt 0) {
        # ───────────── Company Search Mode ─────────────
        $perCompanyCounts = @()

        foreach ($company in $CompanyList) {
            $candidates = Get-Contracts-ForCompany -Driver $driver -Company $company
            if ($candidates.Count -eq 0) {
                $perCompanyCounts += [PSCustomObject]@{ Company=$company; Found=0 }
                continue
            }

            $idx = 0
            foreach ($cand in $candidates) {
                $idx++
                Write-Host ("[{0}/{1}] {2}: {3}" -f $idx,$candidates.Count,$company,$cand.Title) -ForegroundColor Yellow

                $contractObj = [PSCustomObject]@{
                    ContractId     = $cand.ContractId
                    ContractNumber = $cand.ContractNumber
                    Title          = $cand.Title
                    Status         = ""
                    StartDate      = $cand.StartDate
                    ExpiryDate     = $cand.ExpiryDate
                    TotalValue     = $cand.TotalValue
                    DetailUrl      = $cand.DetailUrl
                    SearchedCompany= $company
                }

                $withDetails = Get-ContractDetails-Selenium -Contract $contractObj -Driver $driver
                if ($withDetails.PublicBody -or $withDetails.Suppliers) { $successCount++ } else { $failCount++ }
                $results += $withDetails
            }

            $perCompanyCounts += [PSCustomObject]@{ Company=$company; Found=$candidates.Count }
            # Optional small delay between companies to be gentle
            Start-Sleep -Milliseconds 600
        }

        # Save per-company quick report
        $perCompanyCounts | Export-Csv -Path "CompanySearch_Summary.csv" -NoTypeInformation -Encoding UTF8
        $OutputCSV = "CompanySearch_WithDetails.csv"
    }
    else {
        # ───────────── Original CSV Mode ─────────────
        if (-not (Test-Path $InputCSV)) {
            Write-Error "Input CSV file not found: $InputCSV"
            Write-Host "Please ensure $InputCSV exists in the current directory." -ForegroundColor Yellow
            exit 1
        }
        try {
            $contracts = Import-Csv -Path $InputCSV
            Write-Host "Loaded $($contracts.Count) contracts from $InputCSV" -ForegroundColor Green
            Write-Host ""
        } catch {
            Write-Error "Failed to load CSV: $($_.Exception.Message)"
            exit 1
        }

        if ($contracts.Count -eq 0) { Write-Warning "No contracts found in the CSV file."; exit 0 }

        for ($i = 0; $i -lt $contracts.Count; $i++) {
            $contract = $contracts[$i]
            $progress = $i + 1

            Write-Progress -Activity "Extracting Contract Details" `
                           -Status "Processing $progress of $($contracts.Count) - $($contract.ContractNumber)" `
                           -PercentComplete (($progress / $contracts.Count) * 100)

            Write-Host "[$progress/$($contracts.Count)] Processing contract: $($contract.ContractNumber)" -ForegroundColor Yellow

            $contractObj = [PSCustomObject]@{
                ContractId     = $contract.ContractId
                ContractNumber = $contract.ContractNumber
                Title          = $contract.Title
                Status         = $contract.Status
                StartDate      = $contract.StartDate
                ExpiryDate     = $contract.ExpiryDate
                TotalValue     = $contract.TotalValue
                DetailUrl      = $contract.DetailUrl
                SearchedCompany= ""
            }

            $withDetails = Get-ContractDetails-Selenium -Contract $contractObj -Driver $driver
            if ($withDetails.PublicBody -or $withDetails.Suppliers) { $successCount++ } else { $failCount++ }
            $results += $withDetails
        }
        Write-Progress -Activity "Extracting Contract Details" -Completed
    }

    $endTime = Get-Date
    $totalTime = ($endTime - $startTime).TotalSeconds

    # Export results
    Write-Host ""
    Write-Host "Exporting results to $OutputCSV..." -ForegroundColor Green
    $results | Export-Csv -Path $OutputCSV -NoTypeInformation -Encoding UTF8

    # Summary
    Write-Host ""
    Write-Host "=== Extraction Complete ===" -ForegroundColor Green
    Write-Host ("Mode: {0}" -f ($(if ($CompanyList.Count -gt 0) {"Company Search"} else {"Input CSV"}))) -ForegroundColor White
    Write-Host ("Total items processed: {0}" -f $results.Count) -ForegroundColor White
    Write-Host ("Successfully extracted: {0}" -f $successCount) -ForegroundColor Green
    Write-Host ("Failed/Partial: {0}" -f $failCount) -ForegroundColor $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host ("Total time: {0} seconds" -f [math]::Round($totalTime, 1)) -ForegroundColor White
    if ($results.Count -gt 0) {
        Write-Host ("Average time per item: {0} seconds" -f [math]::Round($totalTime / $results.Count, 1)) -ForegroundColor White
    }
    Write-Host "Output file: $OutputCSV" -ForegroundColor Cyan

} catch {
    Write-Error "Error during extraction: $($_.Exception.Message)"
} finally {
    if ($driver) {
        Write-Host ""
        Write-Host "Closing browser..." -ForegroundColor Gray
        $driver.Quit()
        $driver.Dispose()
    }
}

Write-Host ""
Write-Host "Script completed." -ForegroundColor Green
