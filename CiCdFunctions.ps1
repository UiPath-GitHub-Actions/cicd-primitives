
# Base WebRequest verbs

function GetOrchApi([string]$bearerToken, [string]$uri, $headers = $null, [string]$contentType = "application/json", [bool]$debug = $false) {
    $tenantName = ExtractTenantNameFromUri -uri $uri
    if($debug) {
        Write-Host $uri
    }
    if( $headers -eq $null ) {
        $headers = @{"Authorization"="Bearer $($bearerToken)"; "X-UIPATH-TenantName"="$($tenantName)"}
    }
    $response = Invoke-WebRequest -Method 'Get' -Uri $uri -Headers $headers -ContentType "$($contentType)"
    if($debug) {
        Write-Host $response
    }
    return ConvertFrom-Json $response.Content
}

function PostOrchApi([string]$bearerToken, [string]$uri, $body, $headers = $null, [string]$contentType = "application/json", [bool]$debug = $false) {
    if($contentType -eq "application/json")
    {
        $body_json = $body | ConvertTo-Json
    }
    else
    {
        $body_json = $body
    }
    $tenantName = ExtractTenantNameFromUri -uri $uri
    if($debug) {
        Write-Host $uri
        Write-Host $body
        Write-Host $headers
    }
    if( $headers -eq $null ) {
        $headers = @{"Authorization"="Bearer $($bearerToken)"; "X-UIPATH-TenantName"="$($tenantName)"}
    }
    $response = Invoke-WebRequest -Method 'Post' -Uri $uri -Headers $headers -ContentType "$($contentType)" -Body $body_json
    if($debug) {
        Write-Host $response
    }
    if( $response.StatusCode -ne 200 )
    {
        Write-Host "::error::### :warning: Problem with authentication (Orchestrator)"
        #exit 1
    }
    return ConvertFrom-Json $response.Content
}

# Interactions with the Orchestrator API

function AuthenticateToCloudAndGetBearerTokenClientCredentials([string]$clientId, [string]$clientSecret, [string]$scopes, [string]$tenantName, [string]$identityServer, [bool]$debug = $false) {
    $body = @{"grant_type"="client_credentials"; "client_id"="$($clientId)"; "client_secret"="$($clientSecret)";"scope"="$($scopes)"}
    $headers = @{}
    
    $uri = $identityServer
    $response = PostOrchApi -bearerToken "" -uri $uri -headers $headers -body $body -contentType "application/x-www-form-urlencoded" -debug $debug
    if($debug) {
        Write-Host $response
    }
    return $response.access_token
}

function GetFolderId([string]$orchestratorApiBaseUrl, [string]$bearerToken, [string]$folderName) {
    $result = GetOrchApi -bearerToken $bearerToken -uri "$($orchestratorApiBaseUrl)/odata/Folders?%24filter=FullyQualifiedName%20eq%20'$($folderName)'"
    $debugFolderID = $result.value[0]
    return $result.value[0].Id.ToString()
}

function GetProcessId([string]$orchestratorApiBaseUrl, [string]$bearerToken, [string]$folderId, [string]$processName) {
   $ErrorView = "NormalView"
   $headers = @{"Authorization"="Bearer $($bearerToken)"; "X-UIPATH-OrganizationUnitId"="$($folderId)"}
   $result = GetOrchApi -bearerToken $bearerToken -headers $headers -uri "$($orchestratorApiBaseUrl)/odata/Releases?%24filter=Name%20eq%20'$($processName)'"
   return $result.value[0].Id.ToString()
    
}


#function GetFolderFeedId([string]$orchestratorApiBaseUrl, [string]$bearerToken, [string]$folderId) {
#    $result = GetOrchApi -bearerToken $bearerToken -uri "$($orchestratorApiBaseUrl)/api/PackageFeeds/GetFolderFeed?folderId=$($folderId)"
#    if ($null -eq $result) {$result = "1.0.0"}
#    return $result.ToString()
#}

# Legacy: don't touch
function GetFinalVersionProcess([string]$orchestratorApiBaseUrl, [string]$bearerToken) {
    $processName = GetProcessName
    $processVersion = GetProcessVersion
    
    $uri = "$($orchestratorApiBaseUrl)/odata/Processes/UiPath.Server.Configuration.OData.GetProcessVersions(processId='$($processName)')?`$filter=startswith(Version,'$($processVersion)')&`$orderby=Published%20desc"
    $result = GetOrchApi -bearerToken $bearerToken -uri $uri # -debug $true
    
    if($result."@odata.count" -eq 0) {
        return $processVersion
    }
    else {
        $latestVersion = $result.value[0].Version
    }

    if ($processVersion -eq $latestVersion) {
        $finalVersion = "$($processVersion).1"
    }
    else {
        $finalVersion = IncrementVersion -version $latestVersion
    }
    return $finalVersion
}

function GetFinalVersionProcessFolderFeed([string]$orchestratorApiBaseUrl, [string]$folderName, [string]$bearerToken, [string]$enforceStrictVersioning = "False") {
    $processName = GetProcessName
    $processVersion = GetProcessVersion
    
    $tenantName = ExtractTenantNameFromUri -uri $orchestratorApiBaseUrl
    
    $folderId = GetFolderId -orchestratorApiBaseUrl "$($orchestratorApiBaseUrl)" -bearerToken "$($bearerToken)" -folderName "$($folderName)"
    $feedId = GetFolderFeedId -orchestratorApiBaseUrl "$($orchestratorApiBaseUrl)" -bearerToken "$($bearerToken)" -folderId "$($folderId)"
    
    $uri = "$($orchestratorApiBaseUrl)/odata/Processes/UiPath.Server.Configuration.OData.GetProcessVersions(processId='$($processName)')?feedId=$($feedId)&`$filter=startswith(Version,'$($processVersion)')&`$orderby=Published%20desc"
    $result = GetOrchApi -bearerToken $bearerToken -uri $uri # -debug $true
    
    if($result."@odata.count" -eq 0) {
        return $processVersion
    }
    else {
        $latestVersion = $result.value[0].Version
    }
    
    Write-Host "enforceStrictVersioning $($enforceStrictVersioning)" 
    
    if( $enforceStrictVersioning -eq "True")
    {
        Write-Host "::error::### :warning: Problem with versioning: a version of this package exists already in the Orchestrator"
        exit 1
    }
    
    if ($processVersion -eq $latestVersion) {
        $finalVersion = "$($processVersion).1"
    }
    else {
        $finalVersion = IncrementVersion -version $latestVersion
    }
    return $finalVersion
}

# Legacy: don't touch
function UploadPackageToOrchestrator([string]$orchestratorApiBaseUrl, [string]$bearerToken, [string]$filePath) {
    $tenantName = ExtractTenantNameFromUri -uri $orchestratorApiBaseUrl
    $headers = @{"Authorization"="Bearer $($bearerToken)"; "X-UIPATH-TenantName"="$($tenantName)"}
    $uri = "$($orchestratorApiBaseUrl)/odata/Processes/UiPath.Server.Configuration.OData.UploadPackage"
    $Form = @{
        file = Get-Item -Path $filePath
    }
    $response = Invoke-RestMethod -Uri $uri -Method Post -Form $Form -Headers $headers -ContentType "multipart/form-data"
}

function UploadPackageToFolder([string]$orchestratorApiBaseUrl, [string]$bearerToken, [string]$filePath) {
    $tenantName = ExtractTenantNameFromUri -uri $orchestratorApiBaseUrl
    
    $folderId = GetFolderId -orchestratorApiBaseUrl "$($orchestratorApiBaseUrl)" -bearerToken "$($bearerToken)" -folderName "$($folderName)"
    #$feedId = GetFolderFeedId -orchestratorApiBaseUrl "$($orchestratorApiBaseUrl)" -bearerToken "$($bearerToken)" -folderId "$($folderId)"
    
    $headers = @{"Authorization"="Bearer $($bearerToken)"; "X-UIPATH-TenantName"="$($tenantName)"}
    $uri = "$($orchestratorApiBaseUrl)/odata/Processes/UiPath.Server.Configuration.OData.UploadPackage"
    $Form = @{
        file = Get-Item -Path $filePath
    }
    $response = Invoke-RestMethod -Uri $uri -Method Post -Form $Form -Headers $headers -ContentType "multipart/form-data"
}

function BumpProcessVersion([string]$orchestratorApiBaseUrl, [string]$bearerToken, [string]$folderId, [string]$processId, [string]$processVersion) {
    $tenantName = ExtractTenantNameFromUri -uri $orchestratorApiBaseUrl
    $headers = @{"Authorization"="Bearer $($bearerToken)"; "X-UIPATH-TenantName"="$($tenantName)"; "X-UIPATH-OrganizationUnitId"="$($folderId)"}
    $body = @{"packageVersion"=$processVersion}
    $result = PostOrchApi -bearerToken $bearerToken -uri "$($orchestratorApiBaseUrl)/odata/Releases($($processId))/UiPath.Server.Configuration.OData.UpdateToSpecificPackageVersion" -headers $headers -body $body
}

# Helper functions

function GetUrlOrchestratorApiBaseCloud([string]$baseUrl, [string]$organizationId, [string]$tenantName) {
    return "$($baseUrl)/$($organizationId)/$($tenantName)/orchestrator_"
}

function GetProcessName() {
    $projectJson = Get-Content .\project.json -Raw | ConvertFrom-Json
    return $projectJson.name
}

function GetProcessVersion() {
    $projectJson = Get-Content .\project.json -Raw | ConvertFrom-Json
    return $projectJson.projectVersion
}

function IncrementVersion([string]$version) {
    $aFinalVersion = ""
    $anOriginalVersionArray = $version.Split('.')
    $lastNumber = 0
    if($anOriginalVersionArray.Count -eq 0) {
        return $version + ".1"
    }
    if( [int]::TryParse($anOriginalVersionArray[$anOriginalVersionArray.Length - 1], [ref]$lastNumber) ) {
        for ($num = 0 ; $num -lt $anOriginalVersionArray.Length - 1; $num++) {
            $aFinalVersion = $aFinalVersion + $anOriginalVersionArray[$num] + "."
        }
        $aFinalVersion = $aFinalVersion + ($lastNumber + 1).ToString()
    }
    else {
        return $version + ".1"
    }
    return $aFinalVersion
}

function ExtractTenantNameFromUri([string]$uri) {
    return "$uri" -replace "(?sm).*?.*/([^/]*?)/orchestrator_/(.*?)$.*","`$1"
}

function InterpretTestResults([string]$testResults) {
    $resultsObject = Get-Content $testResults -Raw | ConvertFrom-Json
    $statusPass = $true
    foreach ($elem in $resultsObject.TestSetExecutions) {
        if ($elem.Status -ne "Passed") {
            $statusPass = $false
        }
    }
    if($statusPass -ne $true) {
        return 1
    }
    return 0
}
